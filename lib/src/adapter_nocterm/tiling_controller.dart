import 'package:nocterm/nocterm.dart';
import '../core/event_bus.dart';
import '../layout/layout_events.dart';

import '../layout/layout_engine.dart';
import '../core/plugin_events.dart';
import '../layout/layout_nodes.dart';
import 'focus_manager.dart';
import 'keyboard_bindings.dart';

/// Coordinates layout, focus, and keyboard actions, and notifies listeners
/// after each executed action.
class TilingController extends ChangeNotifier {
  TilingController({
    required LayoutNode initialLayout,
    EventBus? bus,
    KeyboardBindings? keyboardBindings,
    bool removePluginPanes = true,
    this.onError,
  })  : _layout = initialLayout,
        _bus = bus,
        _keyboardBindings = keyboardBindings ?? KeyboardBindings() {
    _focus = FocusManager(slotOrder: _collectSlots(_layout));
    if (bus != null && removePluginPanes) {
      _pluginSub = bus.subscribe<PluginDisabledEvent>((e) {
        if (_handlingPluginDisabled) return null;
        _handlingPluginDisabled = true;
        try {
          final slotId = e.slotId ?? e.pluginId;
          try {
            _layout = LayoutEngine.remove(_layout, slotId, bus: bus);
          } catch (e, st) {
            // The disabled plugin owned the only pane: fall back to an empty slot.
            final slots = _collectSlots(_layout);
            if (slots.isNotEmpty && slots.every((s) => s == slotId)) {
              _layout = const SlotNode(slotId: '_empty');
            } else {
              _reportError(e, st);
            }
          }
          updateLayout(_layout);
        } finally {
          _handlingPluginDisabled = false;
        }
        return null;
      });
    }
  }

  final EventBus? _bus;
  bool _handlingPluginDisabled = false;
  Subscription? _pluginSub;
  final KeyboardBindings _keyboardBindings;
  int _nextSlotId = 2;

  /// Receives errors from rejected layout mutations (resize/split without a
  /// valid target) instead of silently dropping them.
  final void Function(Object error, StackTrace? stackTrace)? onError;

  bool _reportError(Object error, StackTrace? stackTrace) {
    onError?.call(error, stackTrace);
    return true;
  }

  LayoutNode _layout;
  late FocusManager _focus;

  LayoutNode get layout => _layout;
  FocusManager get focus => _focus;
  KeyboardBindings get keyboardBindings => _keyboardBindings;

  List<String> _collectSlots(LayoutNode node) =>
      LayoutEngine.computeRects(node, 1, 1).keys.toList();

  void updateLayout(LayoutNode newLayout) {
    _layout = newLayout;
    final slots = _collectSlots(_layout);
    _focus.updateSlots(slots);
    notifyListeners();
  }

  bool handleKeyEvent(KeyboardEvent event) {
    final action = _keyboardBindings.resolve(event);
    if (action == null) return false;
    handleAction(action);
    return true;
  }

  @override
  void dispose() {
    _pluginSub?.cancel();
    super.dispose();
  }

  void handleAction(TilingAction action) {
    switch (action) {
      case TilingAction.nextFocus:
        _focus.next();
        break;
      case TilingAction.prevFocus:
        _focus.prev();
        break;
      case TilingAction.resizeGrow:
        _resizeFocused(0.05);
        break;
      case TilingAction.resizeShrink:
        _resizeFocused(-0.05);
        break;
      case TilingAction.splitHorizontal:
        _splitFocused(SplitDirection.horizontal);
        break;
      case TilingAction.splitVertical:
        _splitFocused(SplitDirection.vertical);
        break;
      case TilingAction.close:
        _closeFocused();
        break;
      case TilingAction.zoom:
        _zoomFocused();
        break;
    }
    updateLayout(_layout);
  }

  void _resizeFocused(double delta) {
    final slot = _focus.current;
    if (slot == null) return;
    final path = _findPath(_layout, slot);
    if (path == null || path.isEmpty) return;
    final boundaryIndex = path.last > 0 ? path.last - 1 : 0;
    final resizePath = [...path.sublist(0, path.length - 1), boundaryIndex];
    final effectiveDelta = path.last > 0 ? -delta : delta;
    try {
      _layout =
          LayoutEngine.resize(_layout, resizePath, effectiveDelta, bus: _bus);
    } catch (e, st) {
      _reportError(e, st);
    }
  }

  void _splitFocused(SplitDirection direction) {
    final slot = _focus.current;
    if (slot == null) return;
    final path = _findPath(_layout, slot);
    if (path == null) return;
    try {
      final newSlotId = _uniqueSlotId('${slot}_new');
      _layout =
          LayoutEngine.split(_layout, path, direction, newSlotId, bus: _bus);
    } catch (e, st) {
      _reportError(e, st);
    }
  }

  /// Maximizes the focused pane (95% of the area, siblings collapsed) or
  /// restores it when it is already zoomed. Zooming another pane moves it.
  void _zoomFocused() {
    final slot = _focus.current;
    if (slot == null) return;
    final currentlyZoomed = _zoomedSlot(_layout);
    _layout = _setZoomed(_layout, currentlyZoomed == slot ? null : slot);
    _bus?.publish(LayoutChangedEvent(operation: 'zoom', slotId: slot));
  }

  static String? _zoomedSlot(LayoutNode node) {
    if (node is SlotNode) return node.zoomed ? node.slotId : null;
    if (node is SplitNode) {
      for (final child in node.children) {
        final found = _zoomedSlot(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  static LayoutNode _setZoomed(LayoutNode node, String? slotId) {
    if (node is SlotNode) {
      return SlotNode(slotId: node.slotId, zoomed: node.slotId == slotId);
    }
    if (node is SplitNode) {
      return SplitNode(
        direction: node.direction,
        children: node.children
            .map((child) => _setZoomed(child, slotId))
            .toList(growable: false),
        ratios: node.ratios,
      );
    }
    return node;
  }

  void _closeFocused() {
    final slot = _focus.current;
    if (slot == null) return;
    try {
      _layout = LayoutEngine.remove(_layout, slot, bus: _bus);
    } catch (e, st) {
      _reportError(e, st);
    }
  }

  /// Returns the first unused variant of [candidate], appending a numeric
  /// suffix so repeated splits can never produce duplicate slot ids.
  String _uniqueSlotId(String candidate) {
    final existing = _collectSlots(_layout).toSet();
    if (!existing.contains(candidate)) return candidate;
    var candidateId = _nextSlotId++;
    while (existing.contains('${candidate}_$candidateId')) {
      candidateId = _nextSlotId++;
    }
    return '${candidate}_$candidateId';
  }

  /// Resizes the split boundary at [path] by [cells] of an [axisTotal]-cell
  /// axis (e.g. +12 cells on an 80-column split). Converts cells to the ratio
  /// delta expected by [LayoutEngine.resize]; out-of-range paths and
  /// boundaries throw `StateError`.
  void resizeBoundary(List<int> path, int cells, int axisTotal) {
    if (axisTotal <= 0) throw StateError('axisTotal must be positive');
    if (path.isEmpty) throw StateError('Boundary path must identify a split');
    _layout = LayoutEngine.resize(
      _layout,
      path,
      cells / axisTotal,
      bus: _bus,
    );
    notifyListeners();
  }

  List<int>? _findPath(LayoutNode node, String slotId,
      [List<int> path = const []]) {
    if (node is SlotNode) {
      return node.slotId == slotId ? List<int>.from(path) : null;
    }
    if (node is SplitNode) {
      for (var i = 0; i < node.children.length; i++) {
        final found = _findPath(node.children[i], slotId, [...path, i]);
        if (found != null) return found;
      }
    }
    return null;
  }
}
