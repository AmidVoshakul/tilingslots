import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class RecordingPlugin extends Plugin {
  RecordingPlugin(this.pluginId);

  @override
  String get id => pluginId;

  final String pluginId;
  final List<String> log = [];
  bool throwOnSetup = false;

  @override
  String get name => pluginId;

  @override
  String get version => '1.0.0';

  @override
  String? get slotId => pluginId;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    if (throwOnSetup) throw StateError('setup boom');
    log.add('setup');
    container.registerSingleton<String>('svc-$pluginId');
    scope.defer(() => log.add('effect-disposed'));
  }

  @override
  Future<void> teardown(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    log.add('teardown');
    if (container.contains<String>()) container.unregister<String>();
  }
}

void main() {
  group('PluginManager.replace', () {
    test('replaces a plugin in place with a new implementation', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final old = RecordingPlugin('p');
      pm.register(old);
      await pm.enable('p');

      final replacement = RecordingPlugin('p');
      await pm.replace('p', replacement);

      expect(old.log, ['setup', 'teardown', 'effect-disposed']);
      expect(replacement.log, ['setup']);
      expect(pm.isEnabled('p'), isTrue);
      expect(pm.plugins.single, same(replacement));
      expect(c.contains<String>(), isTrue);
    });

    test('publishes PluginReplacedEvent, not a disable', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(RecordingPlugin('p'));
      await pm.enable('p');
      final disabled = <PluginDisabledEvent>[];
      final replaced = <PluginReplacedEvent>[];
      bus.subscribe<PluginDisabledEvent>(disabled.add);
      bus.subscribe<PluginReplacedEvent>(replaced.add);
      await pm.replace('p', RecordingPlugin('p'));
      await Future<void>.delayed(Duration.zero);
      expect(disabled, hasLength(0));
      expect(replaced, hasLength(1));
    });

    test('a failing replacement restores the previous plugin', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final old = RecordingPlugin('p');
      pm.register(old);
      await pm.enable('p');

      final broken = RecordingPlugin('p')..throwOnSetup = true;
      await pm.replace('p', broken);

      expect(pm.isEnabled('p'), isTrue);
      expect(pm.plugins.single, same(old));
      expect(c.contains<String>(), isTrue);
      expect(broken.log, hasLength(0));
      expect(old.log, contains('teardown'));
    });

    test('replacing an unknown plugin throws', () {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      expect(() => pm.replace('ghost', RecordingPlugin('ghost')),
          throwsStateError);
    });

    test('replacement must use the same id', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(RecordingPlugin('p'));
      await pm.enable('p');
      expect(() => pm.replace('p', RecordingPlugin('other')), throwsStateError);
    });

    test('replace is rejected after dispose', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(RecordingPlugin('p'));
      await pm.enable('p');
      await pm.dispose();
      expect(() => pm.replace('p', RecordingPlugin('p')), throwsStateError);
    });

    test('replacing a disabled plugin swaps it without enabling', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(RecordingPlugin('p'));
      final replacement = RecordingPlugin('p');
      await pm.replace('p', replacement);
      expect(pm.isEnabled('p'), isFalse);
      expect(pm.plugins.single, same(replacement));
      expect(replacement.log, hasLength(0));
    });

    test('a replacement failing twice leaves no partial registrations',
        () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(_FlickeringPlugin());
      await pm.enable('p');
      final sizeBefore = c.capture().entries.length;

      // The replacement's setup fails, and restoring the old implementation
      // also fails (it only survives its first setup).
      await pm.replace('p', RecordingPlugin('p')..throwOnSetup = true);

      expect(c.capture().entries.length, sizeBefore);
      expect(pm.isEnabled('p'), isFalse);
      // The failed restore setup's partial registration must not survive.
      expect(c.resolve<String>(), 'ghost');
    });
  });

  group('SlotWorkspace.replace', () {
    test('keeps the pane assignment across a replace', () async {
      final ws = SlotWorkspace();
      ws.register(_SlotPlugin('a'));
      await ws.enable('a');
      await ws.replace('a', _SlotPlugin('a'));

      expect(ws.pluginForSlot('a')!.id, 'a');
      expect(ws.isEnabled('a'), isTrue);
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys, contains('a'));
    });

    test('records the replace in the workspace timeline', () async {
      final ws = SlotWorkspace();
      ws.register(_SlotPlugin('a'));
      await ws.enable('a');
      await ws.replace('a', _SlotPlugin('a'));
      expect(ws.timeline.map((e) => e.type), contains('replace'));
    });

    test('a failing replacement keeps the old pane content', () async {
      final ws = SlotWorkspace();
      ws.register(_SlotPlugin('a', failing: false));
      await ws.enable('a');
      await ws.replace('a', _SlotPlugin('a', failing: true));
      expect(ws.isEnabled('a'), isTrue);
      expect(ws.pluginForSlot('a')!.id, 'a');
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys, contains('a'));
    });

    test('replace is undoable: undo restores the previous implementation',
        () async {
      final ws = SlotWorkspace();
      final v1 = _SlotPlugin('a');
      ws.register(v1);
      await ws.enable('a');
      final v2 = _SlotPlugin('a', label: 'pane-a-v2');
      await ws.replace('a', v2);
      expect(ws.pluginManager.plugins.single, same(v2));

      await ws.undo();
      expect(ws.pluginManager.plugins.single, same(v1));
      expect(ws.pluginForSlot('a'), same(v1));

      await ws.redo();
      expect(ws.pluginManager.plugins.single, same(v2));
      expect(ws.pluginForSlot('a'), same(v2));
    });

    test('checkpoint restores the implementation captured at that point',
        () async {
      final ws = SlotWorkspace();
      final v1 = _SlotPlugin('a');
      ws.register(v1);
      await ws.enable('a');
      final cp = await ws.checkpoint('v1-era');
      await ws.replace('a', _SlotPlugin('a', label: 'pane-a-v2'));

      await ws.restoreCheckpoint(cp);
      expect(ws.pluginManager.plugins.single, same(v1));
    });
  });
}

class _SlotPlugin extends SlotPlugin {
  _SlotPlugin(this.pluginId, {this.failing = false, this.label});

  @override
  String get id => pluginId;

  final String pluginId;
  final bool failing;
  final String? label;

  @override
  String get name => pluginId;

  @override
  String get version => '1.0.0';

  @override
  String get slotId => pluginId;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    if (failing) throw StateError('setup boom');
  }

  @override
  Component build(SlotContext context) => Text(label ?? 'pane-$pluginId');
}

/// Fails on every setup after the first, so the replace rollback cannot
/// restore it.
class _FlickeringPlugin extends Plugin {
  @override
  String get id => 'p';
  @override
  String get name => 'p';
  @override
  String get version => '1.0.0';

  int setups = 0;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    if (setups++ > 0) {
      // Comes back half-initialized: overwrites, then fails.
      container.registerSingleton<String>('partial');
      throw StateError('cannot come back');
    }
    container.registerSingleton<String>('ghost');
  }
}
