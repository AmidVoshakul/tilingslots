import 'package:nocterm/nocterm.dart';

import '../layout/layout_engine.dart';
import '../layout/layout_nodes.dart';
import 'focus_manager.dart';
import 'keyboard_bindings.dart';
import 'tiling_controller.dart';

/// Minimum pane extent (in cells) before a pane is skipped instead of
/// rendered: smaller panes cannot host borders, padding, or text.
const int _kMinPaneExtent = 3;

/// An in-flight boundary drag owned by the capture region.
class _ActiveDrag {
  const _ActiveDrag(
      {required this.handler, required this.axis, required this.lastCell});

  /// Applies an incremental cell delta to the split boundary.
  final void Function(int cells) handler;
  final Axis axis;
  final int lastCell;
}

/// Adapter widget rendering a tiling layout in nocterm.
///
/// Mouse model: clicking a pane focuses it; pressing a pane edge that faces a
/// sibling starts a boundary drag, which keeps receiving deltas even when the
/// cursor crosses into sibling panes (nocterm routes mouse events by position
/// and has no pointer capture, so the whole area is one capture region).
class NoctermTilingWidget extends StatefulComponent {
  const NoctermTilingWidget({
    super.key,
    this.controller,
    this.layout,
    this.focus,
    required this.slotBuilder,
    this.onError,
    this.keyboardBindings,
    this.onUnhandledKeyEvent,
    this.onAction,
    this.slotTitle,
    this.onBoundaryResize,
    this.viewportSize,
    this.cachePanes = false,
    this.slotVersion,
  });

  final TilingController? controller;
  final LayoutNode? layout;
  final FocusManager? focus;
  final Component Function(String slotId) slotBuilder;
  final void Function(Object error, StackTrace? stackTrace)? onError;
  final KeyboardBindings? keyboardBindings;

  /// Receives key events the tiling keymap does not consume (e.g. digits for a
  /// plugin palette). Return `true` if the event was handled.
  final bool Function(KeyboardEvent event)? onUnhandledKeyEvent;

  /// Invoked after the controller performed a tiling action, so the host can
  /// sync external state (e.g. a workspace plugin registry).
  final void Function(TilingAction action)? onAction;

  /// Optional per-pane header text (e.g. plugin name and version). When null,
  /// no header row is rendered. The header consumes one cell of pane height;
  /// panes too short for a header keep their content only.
  final String Function(String slotId)? slotTitle;

  /// Drag-resize callback for split boundaries: receives the resize path
  /// (`[...splitPath, boundaryIndex]`), the cell delta, and the axis total.
  /// In controller mode this defaults to the controller's `resizeBoundary`.
  final void Function(List<int> path, int cells, int axisTotal)?
      onBoundaryResize;

  /// Optional override for the pane area size. When null, the widget uses the
  /// actual layout constraints (via `LayoutBuilder`), so panes only occupy the
  /// space the host really gives them (e.g. next to a status bar).
  final Size? viewportSize;

  /// Caches each pane's content and lets panes repaint their focus border
  /// independently, so focus, layout and data events rebuild only the affected
  /// panes (zero idle content rebuilds). Disable it if [slotBuilder] must run
  /// on every rebuild.
  final bool cachePanes;

  /// With [cachePanes], returns a version of the slot's content inputs. A pane
  /// rebuilds its cached content only when its version changes (e.g. the demo
  /// returns the workspace timeline length, so attaching a plugin invalidates
  /// that pane while focus events never do).
  final int Function(String slotId)? slotVersion;

  @override
  State<NoctermTilingWidget> createState() => _NoctermTilingWidgetState();
}

class _NoctermTilingWidgetState extends State<NoctermTilingWidget> {
  _ActiveDrag? _drag;
  final Map<String, Component> _paneCache = {};
  final Map<String, int> _paneVersions = {};
  Set<String> _cachedPaneIds = const {};

  void _registerDrag(
      void Function(int cells) handler, Axis axis, int startCell) {
    setState(() {
      _drag = _ActiveDrag(handler: handler, axis: axis, lastCell: startCell);
    });
  }

  void _onCaptureHover(MouseEvent event) {
    final active = _drag;
    if (active == null) return;
    final pressed = event.pressed || event.isPrimaryButtonDown;
    if (pressed) {
      final current = active.axis == Axis.horizontal ? event.x : event.y;
      active.handler(current - active.lastCell);
      setState(() {
        _drag = _ActiveDrag(
            handler: active.handler, axis: active.axis, lastCell: current);
      });
    } else {
      setState(() => _drag = null); // release ends the drag
    }
  }

  @override
  Component build(BuildContext context) {
    // LayoutBuilder gives the pane area's real size (not the terminal size),
    // so panes never overlap sibling UI like status bars, and panes are
    // hit-testable in tests without injecting a terminal size.
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = component.viewportSize ??
            Size(
              constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
              constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
            );
        return _buildTiled(size);
      },
    );
  }

  Component _buildTiled(Size area) {
    final ctrl = component.controller;
    final content = ctrl != null
        ? ListenableBuilder(
            listenable: ctrl,
            builder: (BuildContext context, Component? child) {
              return Focusable(
                focused: true,
                onKeyEvent: (KeyboardEvent event) {
                  final kb =
                      component.keyboardBindings ?? ctrl.keyboardBindings;
                  final action = kb.resolve(event);
                  if (action == null) {
                    return component.onUnhandledKeyEvent?.call(event) ?? false;
                  }
                  ctrl.handleAction(action);
                  component.onAction?.call(action);
                  return true;
                },
                child: _buildNode(
                    ctrl.layout, ctrl.focus, _viewport(ctrl.layout, area)),
              );
            },
          )
        : ListenableBuilder(
            listenable: component.focus!,
            builder: (BuildContext context, Component? child) => _buildNode(
              component.layout!,
              component.focus!,
              _viewport(component.layout!, area),
            ),
          );
    // One capture region over the whole tiling area: boundary drags started on
    // a pane edge keep receiving deltas here even when the cursor crosses into
    // sibling panes.
    return MouseRegion(
      opaque: true,
      onHover: _onCaptureHover,
      child: content,
    );
  }

  Map<String, PaneRect>? _viewport(LayoutNode node, Size area) {
    if (area.width <= 0 || area.height <= 0) return null;
    return LayoutEngine.computeRects(
        node, area.width.toInt(), area.height.toInt());
  }

  Component _buildNode(
    LayoutNode node,
    FocusManager fm, [
    Map<String, PaneRect>? rects,
    List<int> path = const [],
    SplitNode? parent,
    int childIndex = -1,
  ]) {
    if (node is SlotNode) {
      final rect = rects?[node.slotId];
      if (rect != null &&
          (rect.width < _kMinPaneExtent || rect.height < _kMinPaneExtent)) {
        return const SizedBox.shrink();
      }
      try {
        if (component.cachePanes) {
          final paneIds = (rects?.keys.toSet() ?? const <String>{});
          // Incremental invalidation: drop panes that disappeared, rebuild
          // panes whose inputs version changed, keep everything else.
          for (final id in _cachedPaneIds.difference(paneIds)) {
            _paneCache.remove(id);
            _paneVersions.remove(id);
          }
          _cachedPaneIds = paneIds;
          final version = component.slotVersion?.call(node.slotId) ?? 0;
          if (_paneVersions[node.slotId] != version) {
            _paneCache.remove(node.slotId);
            _paneVersions[node.slotId] = version;
          }
          _paneCache.putIfAbsent(
              node.slotId, () => _paneContent(node.slotId, fm, rect));
        }
        final pane = _SlotPane(
          rect: rect ?? const PaneRect(x: 0, y: 0, width: 0, height: 0),
          slotId: node.slotId,
          focusManager: fm,
          handlers: _boundaryHandlers(parent, childIndex, rects, path),
          onDragStart: _registerDrag,
          child: component.cachePanes
              ? _paneCache[node.slotId]!
              : _paneContent(node.slotId, fm, rect),
        );
        if (rect == null) return pane;
        return SizedBox(
          width: rect.width.toDouble(),
          height: rect.height.toDouble(),
          child: pane,
        );
      } catch (e, st) {
        component.onError?.call(e, st);
        return Text('Error: $e');
      }
    }
    if (node is SplitNode) {
      final direction = node.direction == SplitDirection.horizontal
          ? Axis.horizontal
          : Axis.vertical;
      // Mirror LayoutEngine.computeRects: a split renders at most
      // min(children, ratios) panes so both layers agree on malformed input.
      final paneCount = node.children.length < node.ratios.length
          ? node.children.length
          : node.ratios.length;
      final children = <Component>[];
      for (var i = 0; i < paneCount; i++) {
        final child = node.children[i];
        final childPath = [...path, i];
        final grandChild = _buildNode(child, fm, rects, childPath, node, i);
        if (rects != null) {
          final extent = _extentAlong(child, rects, direction);
          children.add(direction == Axis.horizontal
              ? SizedBox(width: extent.toDouble(), child: grandChild)
              : SizedBox(height: extent.toDouble(), child: grandChild));
        } else {
          // Fallback: ratio-based flex layout when the pane area is unknown.
          final flex = (node.ratios[i] * 1000).round().clamp(1, 100000);
          children.add(Expanded(flex: flex, child: grandChild));
        }
      }
      if (children.isEmpty) return const SizedBox.shrink();
      if (direction == Axis.horizontal) return Row(children: children);
      return Column(children: children);
    }
    return const SizedBox.shrink();
  }

  /// Builds pane content: optional header row plus the plugin content. The
  /// focus border is drawn by [_SlotPane] around this.
  Component _paneContent(String slotId, FocusManager fm, PaneRect? rect) {
    final pane = component.slotBuilder(slotId);
    final title = component.slotTitle?.call(slotId);
    // Headers need the exact-rects path: a Column with an Expanded child
    // inside the ratio-based fallback layout is not reliably sized.
    final roomForHeader = rect != null && rect.height >= _kMinPaneExtent + 1;
    if (title == null || !roomForHeader) return pane;
    final focused = fm.current == slotId;
    return Column(
      children: [
        SizedBox(
          height: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            color: focused ? Colors.cyan : const Color.fromRGB(64, 64, 72),
            child: Text(
              title,
              style: TextStyle(color: focused ? Colors.black : Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Expanded(child: pane),
      ],
    );
  }

  /// Computes the four boundary drag handlers for the pane at [path] inside
  /// [parent]: only edges facing a sibling along the parent's split axis are
  /// draggable, each converting cell deltas via the resize callback.
  ({
    void Function(int cells)? left,
    void Function(int cells)? right,
    void Function(int cells)? top,
    void Function(int cells)? bottom
  }) _boundaryHandlers(
    SplitNode? parent,
    int childIndex,
    Map<String, PaneRect>? rects,
    List<int> path,
  ) {
    const none = (left: null, right: null, top: null, bottom: null);
    if (parent == null || childIndex < 0 || rects == null) return none;
    final ctrl = component.controller;
    if (component.onBoundaryResize == null && ctrl == null) return none;
    final resize = component.onBoundaryResize ??
        (List<int> p, int cells, int total) =>
            ctrl!.resizeBoundary(p, cells, total);
    final horizontal = parent.direction == SplitDirection.horizontal;
    final axisTotal = _extentAlong(
        parent, rects, horizontal ? Axis.horizontal : Axis.vertical);
    if (axisTotal <= 0) return none;
    final paneCount = parent.children.length < parent.ratios.length
        ? parent.children.length
        : parent.ratios.length;
    final parentPath =
        path.length > 1 ? path.sublist(0, path.length - 1) : const <int>[];
    void Function(int cells) handler(int boundaryIndex) =>
        (cells) => resize([...parentPath, boundaryIndex], cells, axisTotal);
    final before = childIndex > 0 ? handler(childIndex - 1) : null;
    final after = childIndex < paneCount - 1 ? handler(childIndex) : null;
    return horizontal
        ? (left: before, right: after, top: null, bottom: null)
        : (left: null, right: null, top: before, bottom: after);
  }

  int _extentAlong(LayoutNode node, Map<String, PaneRect> rects, Axis axis) {
    var min = 1 << 30;
    var max = -(1 << 30);
    void visit(LayoutNode current) {
      if (current is SlotNode) {
        final rect = rects[current.slotId];
        if (rect == null) return;
        final start = axis == Axis.horizontal ? rect.x : rect.y;
        final end =
            start + (axis == Axis.horizontal ? rect.width : rect.height);
        if (start < min) min = start;
        if (end > max) max = end;
      } else if (current is SplitNode) {
        for (final child in current.children) {
          visit(child);
        }
      }
    }

    visit(node);
    if (max < min) return 0;
    return max - min;
  }
}

/// A pane: click focuses; pressing a pane edge that faces a sibling registers
/// a boundary drag with the capturing root region.
///
/// The focus border repaints through its own listener, so a focus change
/// rebuilds this pane only — never its neighbours.
class _SlotPane extends StatefulComponent {
  const _SlotPane({
    required this.rect,
    required this.slotId,
    required this.focusManager,
    required this.handlers,
    required this.onDragStart,
    required this.child,
  });

  final PaneRect rect;
  final String slotId;
  final FocusManager focusManager;
  final ({
    void Function(int cells)? left,
    void Function(int cells)? right,
    void Function(int cells)? top,
    void Function(int cells)? bottom
  }) handlers;
  final void Function(
      void Function(int cells) handler, Axis axis, int startCell) onDragStart;
  final Component child;

  @override
  State<_SlotPane> createState() => _SlotPaneState();
}

class _SlotPaneState extends State<_SlotPane> {
  late bool _focused;
  VoidCallback? _focusListener;

  @override
  void initState() {
    super.initState();
    _focused = component.focusManager.current == component.slotId;
    _focusListener = () {
      final focused = component.focusManager.current == component.slotId;
      if (focused != _focused) {
        setState(() => _focused = focused);
      }
    };
    component.focusManager.addListener(_focusListener!);
  }

  @override
  void dispose() {
    final listener = _focusListener;
    if (listener != null) component.focusManager.removeListener(listener);
    super.dispose();
  }

  void Function(int cells)? _handlerFor(MouseEvent event) {
    if (event.x <= component.rect.x) return component.handlers.left;
    if (event.x >= component.rect.x + component.rect.width - 1) {
      return component.handlers.right;
    }
    if (event.y <= component.rect.y) return component.handlers.top;
    if (event.y >= component.rect.y + component.rect.height - 1) {
      return component.handlers.bottom;
    }
    return null;
  }

  void _onHover(MouseEvent event) {
    final handler = _handlerFor(event);
    if (handler == null) return;
    final pressed = event.pressed || event.isPrimaryButtonDown;
    if (!pressed) return;
    final horizontal = identical(handler, component.handlers.left) ||
        identical(handler, component.handlers.right);
    component.onDragStart(
      handler,
      horizontal ? Axis.horizontal : Axis.vertical,
      horizontal ? event.x : event.y,
    );
  }

  @override
  Component build(BuildContext context) {
    return GestureDetector(
      // Claim the whole pane: plugin content (e.g. Text) is not hit-testable.
      behavior: HitTestBehavior.opaque,
      onTap: () => component.focusManager.setFocus(component.slotId),
      // The capture region owns the drag after registration; this region only
      // reports edge presses.
      child: MouseRegion(
        opaque: false,
        onHover: _onHover,
        child: Container(
          decoration: BoxDecoration(
            border: BoxBorder.all(
              color: _focused ? Colors.cyan : const Color.fromRGB(80, 80, 88),
            ),
          ),
          child: component.child,
        ),
      ),
    );
  }
}
