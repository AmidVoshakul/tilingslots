import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class IdSlotPlugin extends SlotPlugin {
  IdSlotPlugin(this.pluginId, this.slot);
  final String pluginId;
  final String slot;

  @override
  String get id => pluginId;
  @override
  String get name => pluginId;
  @override
  String get version => '1.0.0';
  @override
  String get slotId => slot;
  @override
  List<Type> get providedServices => const [];
  @override
  List<Type> get consumedServices => const [];
  @override
  Future<void> setup(ServiceContainer c, EventBus b, PluginScope s) async {}
  @override
  Future<void> teardown(ServiceContainer c, EventBus b, PluginScope s) async {}
  @override
  Component build(SlotContext context) => Text('pane-$pluginId');
}

class DemoPlugin extends SlotPlugin {
  DemoPlugin(this.idName);
  final String idName;

  @override
  String get id => idName;
  @override
  String get name => idName;
  @override
  String get version => '1.0.0';
  @override
  String get slotId => idName;
  @override
  List<Type> get providedServices => [];
  @override
  List<Type> get consumedServices => [];
  @override
  Future<void> setup(ServiceContainer c, EventBus b, PluginScope s) async {}
  @override
  Future<void> teardown(ServiceContainer c, EventBus b, PluginScope s) async {}
  @override
  Component build(SlotContext context) => Text('pane-$idName');
}

class FailingPlugin extends SlotPlugin {
  @override
  String get id => 'failing';
  @override
  String get name => 'failing';
  @override
  String get version => '0.1.0';
  @override
  String get slotId => 'failing';
  @override
  List<Type> get providedServices => const [];
  @override
  List<Type> get consumedServices => const [];
  @override
  Future<void> setup(ServiceContainer _c, EventBus _b, PluginScope _s) async =>
      throw StateError('boom');
  @override
  Future<void> teardown(ServiceContainer c, EventBus b, PluginScope s) async {}
  @override
  Component build(SlotContext context) => const Text('x');
}

class _SlowTeardownPlugin extends SlotPlugin {
  @override
  String get id => 'slow';
  @override
  String get name => 'slow';
  @override
  String get version => '1.0.0';
  @override
  String get slotId => 'slow';
  @override
  Future<void> teardown(ServiceContainer c, EventBus b, PluginScope s) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  @override
  Component build(SlotContext context) => const Text('slow');
}

class _SetupCountingPlugin extends SlotPlugin {
  _SetupCountingPlugin(this.pluginId);

  final String pluginId;
  int setupCalls = 0;

  @override
  String get id => pluginId;
  @override
  String get name => pluginId;
  @override
  String get version => '1.0.0';
  @override
  String get slotId => pluginId;
  @override
  Future<void> setup(ServiceContainer c, EventBus b, PluginScope s) async {
    setupCalls++;
  }

  @override
  Component build(SlotContext context) => Text('pane-$pluginId');
}

void main() {
  group('SlotWorkspace', () {
    test('enable adds slot', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      expect(LayoutEngine.computeRects(ws.layout, 10, 10).keys, contains('a'));
    });

    test('disable removes slot', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      await ws.disable('a');
      expect(LayoutEngine.computeRects(ws.layout, 10, 10).keys,
          isNot(contains('a')));
    });

    test('toggle', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.toggle('a');
      expect(ws.isEnabled('a'), isTrue);
      await ws.toggle('a');
      expect(ws.isEnabled('a'), isFalse);
    });

    test('save/restore', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      final json = ws.toJson();
      final ws2 = SlotWorkspace();
      ws2.register(DemoPlugin('a'));
      await ws2.restore(json);
      expect(ws2.isEnabled('a'), isTrue);
    });
  });
  group('Coverage boost', () {
    test('id may differ from slot id', () async {
      final ws = SlotWorkspace();
      ws.register(IdSlotPlugin('plugin-id', 'slot-id'));
      await ws.enable('plugin-id');
      expect(ws.pluginManager.isEnabled('plugin-id'), isTrue);
      expect(LayoutEngine.computeRects(ws.layout, 10, 10).keys,
          contains('slot-id'));
      await ws.disable('plugin-id');
      expect(LayoutEngine.computeRects(ws.layout, 10, 10).keys,
          isNot(contains('slot-id')));
    });

    test('enable failure leaves layout unchanged', () async {
      final ws = SlotWorkspace();
      ws.register(FailingPlugin());
      await ws.enable('failing');
      expect(ws.pluginManager.isEnabled('failing'), isFalse);
      expect(LayoutEngine.computeRects(ws.layout, 10, 10).keys,
          isNot(contains('failing')));
    });

    test('restore unknown plugin throws', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      expect(
          () => ws.restore({
                'enabled': ['missing'],
                'layout': LayoutSerializer.toJson(const SlotNode(slotId: 'a'))
              }),
          throwsA(isA<UnknownSlotPluginError>()));
    });

    test('restore unknown slot throws', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      expect(
          () => ws.restore({
                'enabled': [],
                'layout':
                    LayoutSerializer.toJson(const SlotNode(slotId: 'missing'))
              }),
          throwsA(isA<UnknownSlotPluginError>()));
    });

    test('restore into workspace', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      final json = ws.toJson();
      final ws2 = SlotWorkspace();
      ws2.register(DemoPlugin('a'));
      await ws2.restore(json);
      expect(ws2.isEnabled('a'), isTrue);
    });
  });

  group('Runtime assembly', () {
    test('enable into an existing empty pane adds no new pane', () async {
      final ws = SlotWorkspace(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      ws.register(DemoPlugin('x'));
      await ws.enable('x', into: 'right');
      final after = LayoutEngine.computeRects(ws.layout, 30, 10).keys.toList();
      expect(after, hasLength(2));
      expect(ws.pluginForSlot('right')!.id, 'x');
      expect(ws.pluginForSlot('x'), isNull);
    });

    test('enable into an occupied pane throws', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      ws.register(DemoPlugin('b'));
      expect(() => ws.enable('b', into: 'a'), throwsStateError);
    });

    test('rejected pane claim has no side effects', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      final bystander = _SetupCountingPlugin('b');
      ws.register(bystander);
      expect(() => ws.enable('b', into: 'a'), throwsStateError);
      expect(ws.pluginManager.isEnabled('b'), isFalse);
      expect(bystander.setupCalls, 0);
      expect(ws.available.map((p) => p.id), contains('b'));
      // A retry with a free pane still works.
      await ws.enable('b');
      expect(ws.pluginForSlot('b')!.id, 'b');
    });

    test('vacated pane renders blank, not an error', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      await ws.disable('a', keepPane: true);
      final built = ws.buildSlot('a', isFocused: false);
      expect(built, isNot(isA<Text>()));
    });

    test('save/restore preserves pane assignment', () async {
      final ws = SlotWorkspace(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a', into: 'left');
      await ws.enable('b', into: 'right');
      final json = ws.toJson();
      expect(json['slots'], {'a': 'left', 'b': 'right'});

      final ws2 = SlotWorkspace(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      ws2.register(DemoPlugin('a'));
      ws2.register(DemoPlugin('b'));
      await ws2.restore(json);
      final slots = LayoutEngine.computeRects(ws2.layout, 30, 10).keys.toList();
      expect(slots, hasLength(2));
      expect(ws2.pluginForSlot('left')!.id, 'a');
      expect(ws2.pluginForSlot('right')!.id, 'b');
    });

    test('enable into an unknown pane throws', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      expect(() => ws.enable('a', into: 'ghost'), throwsStateError);
    });

    test('attach moves an enabled plugin to an empty pane', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');
      // Split: create a fresh empty pane, then move 'a' into it.
      final c = TilingController(
          initialLayout: ws.layout, bus: ws.bus, removePluginPanes: false);
      c.focus.setFocus('b');
      c.handleAction(TilingAction.splitHorizontal);
      await ws.updateLayoutFrom(c.layout);
      final emptyPane = LayoutEngine.computeRects(ws.layout, 30, 10)
          .keys
          .firstWhere((s) => ws.pluginForSlot(s) == null);
      await ws.attach('a', emptyPane);
      expect(ws.pluginForSlot(emptyPane)!.id, 'a');
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys,
          isNot(contains('a')));
      expect(ws.isEnabled('a'), isTrue);
    });

    test('spawn registers and enables a fresh instance', () async {
      final ws = SlotWorkspace();
      final first =
          await ws.spawn((slotId) => IdSlotPlugin('notes#$slotId', slotId));
      final second =
          await ws.spawn((slotId) => IdSlotPlugin('notes#$slotId', slotId));
      expect(first.id, isNot(second.id));
      expect(ws.isEnabled(first.id), isTrue);
      expect(ws.isEnabled(second.id), isTrue);
      final slots = LayoutEngine.computeRects(ws.layout, 30, 10).keys.toList();
      expect(slots, hasLength(2));
      expect(ws.pluginForSlot(first.slotId)!.id, first.id);
      expect(ws.pluginForSlot(second.slotId)!.id, second.id);
    });

    test('spawn into an existing pane does not grow the layout', () async {
      final ws = SlotWorkspace(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      ws.register(DemoPlugin('a'));
      await ws.enable('a', into: 'left');
      await ws.spawn((slotId) => IdSlotPlugin('x#$slotId', slotId),
          into: 'right');
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys, hasLength(2));
      expect(ws.pluginForSlot('right')!.id, startsWith('x#'));
      expect(ws.pluginForSlot('left')!.id, 'a');
    });

    test('disable can keep the pane for reuse', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');
      await ws.disable('a', keepPane: true);
      expect(ws.isEnabled('a'), isFalse);
      expect(ws.pluginForSlot('a'), isNull);
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys,
          containsAll(['a', 'b']));
      ws.register(DemoPlugin('c'));
      await ws.enable('c', into: 'a');
      expect(ws.pluginForSlot('a')!.id, 'c');
    });

    test('disable reports the pane actually occupied', () async {
      final ws = SlotWorkspace(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      ws.register(DemoPlugin('a'));
      await ws.enable('a', into: 'right');
      PluginDisabledEvent? event;
      ws.bus.subscribe<PluginDisabledEvent>((e) => event = e);
      await ws.disable('a');
      await Future<void>.delayed(Duration.zero);
      expect(event!.slotId, 'right');
    });

    test('a failed spawn does not leave the instance registered', () async {
      final ws = SlotWorkspace(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      ws.register(DemoPlugin('a'));
      await ws.enable('a', into: 'left');
      // Await: expect() with a sync closure races the async failure.
      await expectLater(
        () => ws.spawn((slotId) => IdSlotPlugin('x#$slotId', slotId),
            into: 'left'),
        throwsStateError,
      );
      // The failed instance must be gone from both registries.
      expect(ws.available.map((p) => p.id), isNot(contains(startsWith('x#'))));
      expect(ws.pluginManager.plugins.map((p) => p.id), ['a']);
      // A retry into a free pane still works (counter advanced past the
      // failed attempt, which is fine: ids stay unique).
      await ws.spawn((slotId) => IdSlotPlugin('x#$slotId', slotId),
          into: 'right');
      expect(ws.pluginManager.plugins.map((p) => p.id),
          containsAll(['a', startsWith('x#')]));
    });

    test('available lists registered but disabled slot plugins', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      expect(ws.available.map((p) => p.id), unorderedEquals(['a', 'b']));
      await ws.enable('a');
      expect(ws.available.map((p) => p.id), ['b']);
    });
  });

  group('Review fixes', () {
    test('registering two plugins for the same slot throws', () {
      final ws = SlotWorkspace();
      ws.register(IdSlotPlugin('p1', 'shared'));
      expect(() => ws.register(IdSlotPlugin('p2', 'shared')), throwsStateError);
    });

    test('buildSlot for unknown slot renders blank, not throw', () {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      final built = ws.buildSlot('ghost', isFocused: false);
      expect(built, isNot(isA<Text>()));
    });

    test('enable appends slot to an existing split root', () async {
      final initial = SplitNode(
        direction: SplitDirection.horizontal,
        children: const [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: const [0.5, 0.5],
      );
      final ws = SlotWorkspace(initialLayout: initial);
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      ws.register(DemoPlugin('c'));
      await ws.enable('c');
      final slots = LayoutEngine.computeRects(ws.layout, 12, 10).keys.toList();
      expect(slots, containsAll(['a', 'b', 'c']));
      expect(ws.layout, isA<SplitNode>());
      expect((ws.layout as SplitNode).ratios.length, 3);
    });

    test('enable equalizes panes of a split root', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      ws.register(DemoPlugin('c'));
      await ws.enable('a');
      await ws.enable('b');
      await ws.enable('c');
      final rects = LayoutEngine.computeRects(ws.layout, 90, 24);
      expect(rects['a']!.width, 30);
      expect(rects['b']!.width, 30);
      expect(rects['c']!.width, 30);
    });

    test('disable removes slot from a multi-pane split', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');
      expect(LayoutEngine.computeRects(ws.layout, 10, 10).keys.toList(),
          hasLength(2));
      await ws.disable('a');
      expect(ws.layout, isA<SlotNode>());
      expect(LayoutEngine.computeRects(ws.layout, 10, 10).keys,
          isNot(contains('a')));
    });

    test('restore rejects a non-map layout document', () {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      expect(
        () => ws.restore({
          'enabled': ['a'],
          'layout': 'garbage'
        }),
        throwsA(isA<LayoutSerializationException>()),
      );
    });

    test('restore rejects non-string plugin ids', () {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      expect(
        () => ws.restore({
          'enabled': const [42]
        }),
        throwsA(isA<UnknownSlotPluginError>()),
      );
    });

    test('concurrent enables keep every slot', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await Future.wait([ws.enable('a'), ws.enable('b')]);
      final slots = LayoutEngine.computeRects(ws.layout, 10, 10).keys.toList();
      expect(slots, containsAll(['a', 'b']));
      expect(slots, hasLength(2));
      expect(ws.isEnabled('a'), isTrue);
      expect(ws.isEnabled('b'), isTrue);
    });

    test('concurrent toggles settle in a consistent state', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await Future.wait([ws.toggle('a'), ws.toggle('b')]);
      final slots = LayoutEngine.computeRects(ws.layout, 10, 10).keys.toList();
      expect(slots, hasLength(2));
      expect(ws.isEnabled('a'), isTrue);
      expect(ws.isEnabled('b'), isTrue);
      await Future.wait([ws.disable('a'), ws.disable('b')]);
      expect(LayoutEngine.computeRects(ws.layout, 10, 10).keys,
          contains('_empty'));
    });

    test('pluginForSlot resolves the plugin owning a slot', () async {
      final ws = SlotWorkspace();
      ws.register(IdSlotPlugin('plug-id', 'slot-id'));
      await ws.enable('plug-id');
      expect(ws.pluginForSlot('slot-id')!.id, 'plug-id');
      expect(ws.pluginForSlot('missing'), isNull);
    });

    test('dispose tears down services with dispose hooks', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      var disposed = false;
      ws.services
          .registerSingleton<String>('svc', dispose: (_) => disposed = true);
      await ws.disposeAsync();
      expect(disposed, isTrue);
    });

    test('services are disposed only after async teardown completes', () async {
      final ws = SlotWorkspace();
      ws.register(_SlowTeardownPlugin());
      await ws.enable('slow');
      var disposedEarly = false;
      ws.services.registerSingleton<String>('svc', dispose: (_) {
        disposedEarly = true;
      });
      final done = ws.disposeAsync();
      // The synchronous window must not have disposed services yet.
      expect(disposedEarly, isFalse);
      await done;
      expect(disposedEarly, isTrue);
    });
  });
}
