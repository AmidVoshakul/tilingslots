import 'package:nocterm/nocterm.dart';

import '../core/event_bus.dart';
import '../core/exceptions.dart';
import '../core/plugin.dart';
import '../core/plugin_events.dart';
import '../core/plugin_manager.dart';
import '../core/service_container.dart';
import '../layout/layout_engine.dart';
import '../layout/layout_exceptions.dart';
import '../layout/layout_nodes.dart';
import '../layout/layout_serializer.dart';
import 'focus_manager.dart';
import 'slot_plugin.dart';
import 'workspace_timeline.dart';

class SlotWorkspace extends ChangeNotifier {
  SlotWorkspace({
    LayoutNode? initialLayout,
    EventBus? bus,
    int maxLogEntries = 200,
  })  : _bus = bus ?? EventBus(),
        _services = ServiceContainer(),
        _layout = initialLayout ?? const SlotNode(slotId: '_empty'),
        _timeline = WorkspaceTimeline(maxEntries: maxLogEntries) {
    _plugins = PluginManager(
      container: _services,
      bus: _bus,
      slotResolver: (id) => _activeSlots[id],
    );
    _focus = FocusManager(slotOrder: _collectSlots(_layout));
    // Kernel-level crash containment: when a plugin's zone contains an
    // uncaught async error, the manager disables it and disposes its scope;
    // the workspace releases the pane so the dead plugin cannot hold UI.
    _crashSub = _bus.subscribe<PluginCrashedEvent>((event) {
      final slot = _activeSlots.remove(event.pluginId);
      if (slot == null) return;
      _removePane(slot);
      _focus.updateSlots(_collectSlots(_layout));
      notifyListeners();
    });
  }

  late final Subscription _crashSub;

  final EventBus _bus;
  final ServiceContainer _services;
  late final PluginManager _plugins;
  final Map<String, SlotPlugin> _registry = {};

  /// Active plugin id → slot id mapping for enabled plugins.
  final Map<String, String> _activeSlots = {};
  int _spawnCounter = 0;
  LayoutNode _layout;
  late FocusManager _focus;

  final WorkspaceTimeline _timeline;
  bool _applying = false;

  EventBus get bus => _bus;
  ServiceContainer get services => _services;
  PluginManager get pluginManager => _plugins;
  LayoutNode get layout => _layout;
  FocusManager get focus => _focus;

  /// Recorded mutations, oldest first.
  List<WorkspaceEventEntry> get timeline => _timeline.timeline;

  List<WorkspaceCheckpoint> get checkpoints => _timeline.checkpoints;

  bool get canUndo => _timeline.canUndo;
  bool get canRedo => _timeline.canRedo;

  List<String> _collectSlots(LayoutNode node) =>
      LayoutEngine.computeRects(node, 1, 1).keys.toList();

  void register(SlotPlugin plugin) {
    if (_registry.containsKey(plugin.id)) {
      throw StateError('Plugin already registered: ${plugin.id}');
    }
    if (_registry.values.any((p) => p.slotId == plugin.slotId)) {
      throw StateError(
          'Slot already claimed by another plugin: ${plugin.slotId}');
    }
    _registry[plugin.id] = plugin;
    _plugins.register(plugin);
  }

  bool isEnabled(String pluginId) => _plugins.isEnabled(pluginId);

  /// Registered slot plugins that are currently disabled (the palette).
  List<SlotPlugin> get available => _registry.values
      .where((p) => !_plugins.isEnabled(p.id))
      .toList(growable: false);

  /// Returns the enabled plugin rendering into [slotId], or `null`.
  SlotPlugin? pluginForSlot(String slotId) {
    for (final entry in _activeSlots.entries) {
      if (entry.value == slotId) return _registry[entry.key];
    }
    return null;
  }

  /// Runs [mutation] as one recorded history entry. Mutations that throw are
  /// not recorded: the workspace state is unchanged by them.
  Future<void> _record(
      String type, String label, Future<void> Function() mutation) {
    return _timeline.enqueue(() async {
      if (_applying) {
        await mutation();
        return;
      }
      final before = toJson();
      final beforeImpls = _currentImplementations();
      await mutation();
      _timeline.append(
        type: type,
        label: label,
        before: before,
        after: toJson(),
        implementations: beforeImpls,
        afterImplementations: _currentImplementations(),
      );
    });
  }

  Future<void> enable(String pluginId, {String? into}) async {
    await _record(
        'enable', 'enable $pluginId', () => _enable(pluginId, into: into));
  }

  Future<void> _enable(String pluginId, {String? into}) async {
    final plugin = _registry[pluginId];
    if (plugin == null) throw StateError('Unknown plugin: $pluginId');
    if (_plugins.isEnabled(pluginId)) {
      // Already active: `into` moves the plugin, otherwise this is a no-op.
      if (into != null) await _attach(pluginId, into);
      return;
    }
    if (into != null) {
      // Validate the target pane before enabling, so a rejected claim cannot
      // leave a ghost-enabled plugin (setup already ran, no pane, not
      // available for retry).
      if (!_collectSlots(_layout).contains(into)) {
        throw StateError('Unknown pane: $into');
      }
      if (pluginForSlot(into) != null) {
        throw StateError('Pane already occupied: $into');
      }
    }
    await _plugins.enable(pluginId);
    if (!_plugins.isEnabled(pluginId)) return;
    final target = into ?? plugin.slotId;
    try {
      _claimPane(pluginId, target, create: into == null);
    } catch (_) {
      // Never leave a plugin enabled without a pane.
      await _plugins.disable(pluginId);
      rethrow;
    }
    _focus.updateSlots(_collectSlots(_layout));
    notifyListeners();
  }

  /// Claims [slotId] for [pluginId], creating the pane when [create] is set.
  void _claimPane(String pluginId, String slotId, {bool create = true}) {
    final slots = _collectSlots(_layout);
    if (slots.contains(slotId)) {
      if (pluginForSlot(slotId) != null) {
        throw StateError('Pane already occupied: $slotId');
      }
      _activeSlots[pluginId] = slotId;
      return;
    }
    if (!create) throw StateError('Unknown pane: $slotId');
    if (_layout is SlotNode && (_layout as SlotNode).slotId == '_empty') {
      _layout = SlotNode(slotId: slotId);
    } else if (_layout is SlotNode) {
      final existing = _layout as SlotNode;
      _layout = SplitNode(
        direction: SplitDirection.horizontal,
        children: [existing, SlotNode(slotId: slotId)],
        ratios: const [0.5, 0.5],
      );
    } else if (_layout is SplitNode) {
      final root = _layout as SplitNode;
      // A new pane joins with equal weight so the workspace stays even.
      final newChildren = <LayoutNode>[
        ...root.children,
        SlotNode(slotId: slotId)
      ];
      final newRatios = List<double>.filled(newChildren.length, 1.0);
      _layout = SplitNode(
        direction: root.direction,
        children: newChildren,
        ratios: LayoutEngine.normalizeRatios(newRatios),
      );
    }
    _activeSlots[pluginId] = slotId;
  }

  /// Moves an enabled plugin into an existing (empty) pane. The pane the
  /// plugin occupied before is removed from the layout.
  Future<void> attach(String pluginId, String slotId) async {
    await _record('attach', 'attach $pluginId → $slotId',
        () => _attach(pluginId, slotId));
  }

  Future<void> _attach(String pluginId, String slotId) async {
    if (!_plugins.isEnabled(pluginId)) {
      throw StateError('Plugin is not enabled: $pluginId');
    }
    final previousSlot = _activeSlots[pluginId];
    if (previousSlot == slotId) return;
    if (!_collectSlots(_layout).contains(slotId)) {
      throw StateError('Unknown pane: $slotId');
    }
    if (pluginForSlot(slotId) != null) {
      throw StateError('Pane already occupied: $slotId');
    }
    _activeSlots[pluginId] = slotId;
    if (previousSlot != null) {
      _removePane(previousSlot);
    }
    _focus.updateSlots(_collectSlots(_layout));
    notifyListeners();
  }

  /// Registers and enables a new instance of a plugin blueprint. [factory]
  /// receives a generated nominal slot id (unique per instance); when [into]
  /// is given, the instance is placed into that existing pane instead of
  /// creating one.
  Future<SlotPlugin> spawn(
    SlotPlugin Function(String slotId) factory, {
    String? into,
  }) async {
    final nominal = 'spawn-${++_spawnCounter}';
    final plugin = factory(nominal);
    await _record('spawn', 'spawn ${plugin.id}', () async {
      register(plugin);
      try {
        await _enable(plugin.id, into: into);
      } catch (_) {
        // A rejected claim must not leave the instance anywhere: neither the
        // workspace registry nor the plugin manager.
        _registry.remove(plugin.id);
        await _plugins.unregister(plugin.id);
        rethrow;
      }
    });
    return plugin;
  }

  Future<void> disable(String pluginId, {bool keepPane = false}) async {
    await _record(
      'disable',
      keepPane ? 'vacate $pluginId' : 'disable $pluginId',
      () => _disable(pluginId, keepPane: keepPane),
    );
  }

  Future<void> _disable(String pluginId, {bool keepPane = false}) async {
    final plugin = _registry[pluginId];
    if (plugin == null) throw StateError('Unknown plugin: $pluginId');
    final beforeEnabled = _registry.keys.where(isEnabled).toSet();
    // Report the pane the plugin actually occupies (attach/into can differ
    // from the declared slotId), so listeners remove the right pane.
    final activeSlot = _activeSlots[pluginId];
    await _plugins.disable(pluginId, slotId: activeSlot ?? plugin.slotId);
    final afterEnabled = _registry.keys.where(isEnabled).toSet();
    final newlyDisabled = beforeEnabled.difference(afterEnabled);
    for (final id in newlyDisabled) {
      final slot = _activeSlots.remove(id);
      if (slot == null) continue;
      if (!keepPane) _removePane(slot);
    }
    _focus.updateSlots(_collectSlots(_layout));
    notifyListeners();
  }

  void _removePane(String slotId) {
    if (!_collectSlots(_layout).contains(slotId)) return;
    if (_layout is SlotNode && (_layout as SlotNode).slotId == slotId) {
      _layout = const SlotNode(slotId: '_empty');
      return;
    }
    try {
      _layout = LayoutEngine.remove(_layout, slotId);
    } catch (_) {
      return;
    }
    if (_collectSlots(_layout).isEmpty) {
      _layout = const SlotNode(slotId: '_empty');
    }
  }

  /// Adopts a layout driven by a [TilingController] (e.g. after keyboard
  /// splits and closes) so workspace rendering follows the mutated tree.
  /// Plugins whose pane disappeared are disabled and return to the palette.
  Future<void> updateLayoutFrom(LayoutNode newLayout) async {
    if (identical(newLayout, _layout)) return; // focus-only update: not history
    await _record('layout', 'update layout', () async {
      await _adoptLayout(newLayout);
    });
  }

  Future<void> _adoptLayout(LayoutNode newLayout) async {
    _layout = newLayout;
    final slots = _collectSlots(_layout).toSet();
    final orphaned = _activeSlots.entries
        .where((entry) => !slots.contains(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in orphaned) {
      await _disable(id);
    }
    _focus.updateSlots(slots.toList());
    notifyListeners();
  }

  /// Swaps a plugin implementation in place, keeping its pane assignment and
  /// the workspace timeline. See [PluginManager.replace] for failure semantics.
  Future<void> replace(String pluginId, SlotPlugin newPlugin) async {
    await _record('replace', 'replace $pluginId', () async {
      await _plugins.replace(pluginId, newPlugin);
      // Only adopt the new implementation if the manager actually swapped.
      final swapped = _plugins.plugins.any((p) => identical(p, newPlugin));
      if (swapped) _registry[pluginId] = newPlugin;
      // Re-claim the pane if the swap dropped the mapping (defensive: the
      // manager keeps enabled state, so this is normally a no-op).
      final slot = _activeSlots[pluginId];
      if (slot != null && pluginForSlot(slot) == null) {
        _activeSlots.remove(pluginId);
        _claimPane(pluginId, slot, create: false);
      }
      _focus.updateSlots(_collectSlots(_layout));
      notifyListeners();
    });
  }

  Future<void> toggle(String pluginId) async {
    if (isEnabled(pluginId)) {
      await disable(pluginId);
    } else {
      await enable(pluginId);
    }
  }

  Component buildSlot(String slotId, {required bool isFocused}) {
    final ctx = SlotContext(
      slotId: slotId,
      isFocused: isFocused,
      services: _services,
      events: _bus,
    );
    final plugin = pluginForSlot(slotId);
    if (plugin == null) {
      // A vacated but kept pane: render nothing rather than an error.
      return const SizedBox.shrink();
    }
    try {
      return plugin.build(ctx);
    } catch (e) {
      return Text('Error: $e');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': _registry.keys.where(isEnabled).toList(),
      // plugin id → pane assignment, so restore keeps plugins in their panes.
      'slots': Map<String, String>.from(_activeSlots),
      'layout': LayoutSerializer.toJson(_layout),
    };
  }

  Future<void> restore(Map<String, dynamic> json) async {
    await _record('restore', 'restore workspace', () => _restore(json));
  }

  Future<void> _restore(Map<String, dynamic> json,
      {bool strictSlots = true}) async {
    final rawEnabled = (json['enabled'] as List?) ?? [];
    final enabled = <String>[];
    for (final id in rawEnabled) {
      if (id is! String) {
        throw UnknownSlotPluginError('Plugin id must be a string: $id');
      }
      if (!_registry.containsKey(id)) {
        throw UnknownSlotPluginError('Unknown plugin: $id');
      }
      enabled.add(id);
    }
    final layoutJson = json['layout'];
    LayoutNode? parsedLayout;
    if (layoutJson != null) {
      if (layoutJson is! Map<String, dynamic>) {
        throw LayoutSerializationException('Layout document must be a map');
      }
      final parsed = LayoutSerializer.fromJson(layoutJson);
      final slots = _collectSlots(parsed);
      final assignments =
          (json['slots'] as Map?)?.cast<String, String>() ?? const {};
      for (final s in slots) {
        // Strict validation guards externally supplied documents; internal
        // snapshots (undo/redo/checkpoints) may legitimately contain empty
        // panes that no plugin claims.
        if (!strictSlots) continue;
        final known = s == '_empty' ||
            pluginForSlot(s) != null ||
            _registry.values.any((p) => p.slotId == s) ||
            assignments.containsValue(s);
        if (!known) {
          throw UnknownSlotPluginError('Unknown slot: $s');
        }
      }
      parsedLayout = parsed;
    }

    final oldLayout = _layout;
    final oldEnabled = _registry.keys.where(isEnabled).toSet();
    if (parsedLayout != null) {
      _layout = parsedLayout;
    }

    try {
      for (final id in List<String>.from(_registry.keys)) {
        if (isEnabled(id) && !enabled.contains(id)) {
          await _disable(id);
        }
      }
      final assignments =
          (json['slots'] as Map?)?.cast<String, String>() ?? const {};
      for (final id in enabled) {
        if (!_registry.containsKey(id)) continue;
        final pane = assignments[id];
        if (pane != null && _collectSlots(_layout).contains(pane)) {
          await _enable(id, into: pane);
        } else {
          await _enable(id);
        }
      }
    } catch (_) {
      _layout = oldLayout;
      for (final id in _registry.keys) {
        final shouldEnable = oldEnabled.contains(id);
        if (shouldEnable && !isEnabled(id)) {
          try {
            await _enable(id);
          } catch (_) {}
        } else if (!shouldEnable && isEnabled(id)) {
          try {
            await _disable(id);
          } catch (_) {}
        }
      }
      _reconcileActiveSlots();
      _focus.updateSlots(_collectSlots(_layout));
      notifyListeners();
      rethrow;
    }

    _reconcileActiveSlots();
    _focus.updateSlots(_collectSlots(_layout));
    notifyListeners();
  }

  /// Drops pane mappings whose pane no longer exists (after layout rollbacks).
  void _reconcileActiveSlots() {
    final slots = _collectSlots(_layout).toSet();
    _activeSlots.removeWhere((_, slot) => !slots.contains(slot));
  }

  // ---------------------------------------------------------------------------
  // Time machine: checkpoints and undo/redo
  // ---------------------------------------------------------------------------

  /// Captures a named snapshot of the current workspace document.
  Future<WorkspaceCheckpoint> checkpoint([String? name]) async {
    return _timeline.addCheckpoint(
      name: name,
      document: toJson(),
      implementations: _currentImplementations(),
    );
  }

  /// Restores the document captured by [checkpoint].
  Future<void> restoreCheckpoint(WorkspaceCheckpoint checkpoint) async {
    await _record('checkpoint', 'restore ${checkpoint.name}', () async {
      await _applyDocument(
        checkpoint.document,
        implementations: checkpoint.implementations,
      );
    });
  }

  /// Steps one recorded mutation back.
  Future<void> undo() {
    // Routed through the timeline queue so overlapping keypresses stay ordered.
    return _timeline.enqueue(() async {
      final entry = _timeline.stepBack();
      if (entry == null) return;
      await _applyDocument(entry.before,
          implementations: entry.implementations);
    });
  }

  /// Re-applies the mutation one step ahead.
  Future<void> redo() {
    return _timeline.enqueue(() async {
      final entry = _timeline.stepForward();
      if (entry == null) return;
      await _applyDocument(entry.after,
          implementations: entry.afterImplementations);
    });
  }

  Map<String, Plugin> _currentImplementations() {
    final impls = <String, Plugin>{};
    for (final plugin in _plugins.plugins) {
      final registered = _registry[plugin.id];
      if (registered != null) impls[plugin.id] = registered;
    }
    return impls;
  }

  Future<void> _applyDocument(
    Map<String, dynamic> document, {
    Map<String, Plugin> implementations = const {},
  }) async {
    _applying = true;
    try {
      await _restore(document, strictSlots: false);
      // Restore which implementation each enabled plugin had at that point.
      for (final entry in implementations.entries) {
        final id = entry.key;
        final wanted = entry.value;
        if (!_plugins.isEnabled(id)) continue;
        if (identical(_registry[id], wanted)) continue;
        await _plugins.replace(id, wanted);
        if (wanted is SlotPlugin) _registry[id] = wanted;
      }
    } finally {
      _applying = false;
    }
  }

  /// Disposes the workspace synchronously: plugin teardown (including async
  /// `teardown` implementations) completes before services are disposed.
  /// Prefer [disposeAsync] when the caller can await.
  @override
  void dispose() {
    // Chain service disposal behind async plugin teardown, swallow unexpected
    // teardown failures so they cannot become unhandled async errors, and let
    // listeners go on the sync path too.
    _plugins
        .dispose()
        .then((_) => _services.dispose())
        .catchError((Object _) {});
    _crashSub.cancel();
    super.dispose();
  }

  /// Awaited variant of [dispose]: runs plugin `teardown` for enabled plugins,
  /// then disposes the service container.
  Future<void> disposeAsync() async {
    _crashSub.cancel();
    await _plugins.dispose();
    _services.dispose();
    super.dispose();
  }
}
