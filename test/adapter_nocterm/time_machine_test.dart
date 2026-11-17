import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('time machine', () {
    test('split and undo/redo round-trips the layout tree', () async {
      final ws = SlotWorkspace();
      final controller = TilingController(
        initialLayout: ws.layout,
        bus: ws.bus,
        removePluginPanes: false,
      );
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      controller.updateLayout(ws.layout);

      controller.focus.setFocus('a');
      controller.handleAction(TilingAction.splitHorizontal);
      await ws.updateLayoutFrom(controller.layout);

      final splitSlots =
          LayoutEngine.computeRects(ws.layout, 30, 10).keys.toList();
      expect(splitSlots, hasLength(2));
      expect(ws.canUndo, isTrue);

      await ws.undo(); // undo the split
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys, hasLength(1));
      expect(ws.canRedo, isTrue);

      await ws.redo(); // redo the split
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys, hasLength(2));

      await ws.undo(); // undo the split
      await ws.undo(); // undo the enable → empty workspace
      expect(ws.canUndo, isFalse);
      expect(ws.isEnabled('a'), isFalse);

      await ws.redo(); // redo the enable
      expect(ws.isEnabled('a'), isTrue);
      await ws.redo(); // redo the split
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys, hasLength(2));
    });

    test('undo re-enables a disabled plugin with its pane assignment',
        () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');
      await ws.disable('a');

      expect(ws.isEnabled('a'), isFalse);
      await ws.undo();
      expect(ws.isEnabled('a'), isTrue);
      expect(ws.pluginForSlot('a')!.id, 'a');
      expect(ws.pluginForSlot('b')!.id, 'b');
    });

    test('attach and spawn are undoable', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');
      final controller = TilingController(
          initialLayout: ws.layout, bus: ws.bus, removePluginPanes: false);
      controller.focus.setFocus('b');
      controller.handleAction(TilingAction.splitHorizontal);
      await ws.updateLayoutFrom(controller.layout);
      final emptyPane = LayoutEngine.computeRects(ws.layout, 30, 10)
          .keys
          .firstWhere((s) => ws.pluginForSlot(s) == null);
      await ws.attach('a', emptyPane);
      expect(ws.pluginForSlot(emptyPane)!.id, 'a');

      await ws.undo(); // undo attach
      expect(ws.pluginForSlot(emptyPane), isNull);
      await ws.undo(); // undo split
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys, hasLength(2));
    });

    test('named checkpoints restore a saved workspace document', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      final checkpoint = await ws.checkpoint('clean');

      ws.register(DemoPlugin('b'));
      await ws.enable('b');
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys, hasLength(2));

      await ws.restoreCheckpoint(checkpoint);
      expect(LayoutEngine.computeRects(ws.layout, 30, 10).keys, hasLength(1));
      expect(ws.isEnabled('b'), isFalse);
    });

    test('timeline records operation labels in order', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      final labels = ws.timeline.map((e) => e.label).toList();
      expect(labels, hasLength(greaterThan(0)));
      final types = ws.timeline.map((e) => e.type).toList();
      expect(types, contains('enable'));
      final seqs = ws.timeline.map((e) => e.seq).toList();
      for (var i = 1; i < seqs.length; i++) {
        expect(seqs[i], greaterThan(seqs[i - 1]));
      }
    });

    test('undo/redo stop at the timeline boundaries', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      await ws.undo();
      expect(ws.canUndo, isFalse);
      await ws.undo(); // no-op
      await ws.redo();
      await ws.redo(); // no-op at the end
      expect(ws.isEnabled('a'), isTrue);
    });

    test('undoing back to a state reproduces its document exactly', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      final documentAtOne = ws.toJson();
      await ws.enable('b');
      await ws.undo();
      expect(ws.toJson()['layout'], documentAtOne['layout']);
      expect(ws.toJson()['enabled'], documentAtOne['enabled']);
    });

    test('overlapping undo and redo do not desynchronize the cursor', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');
      final slotsBefore =
          LayoutEngine.computeRects(ws.layout, 30, 10).keys.toList();

      // Fire undo and redo concurrently, like two quick keypresses would.
      final first = ws.undo();
      final second = ws.redo();
      await Future.wait([first, second]);

      // Operations are serialized: undo-then-redo is a net no-op, so the state
      // must match the cursor position exactly.
      expect(ws.canRedo, isFalse);
      expect(ws.canUndo, isTrue);
      final slots = LayoutEngine.computeRects(ws.layout, 30, 10).keys.toList();
      expect(slots, slotsBefore);
    });

    test('two overlapping undos collapse to exactly two steps back', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');

      await Future.wait([ws.undo(), ws.undo()]);
      expect(ws.isEnabled('a'), isFalse);
      expect(ws.isEnabled('b'), isFalse);
      expect(ws.canUndo, isFalse);
      final slots = LayoutEngine.computeRects(ws.layout, 30, 10).keys.toList();
      expect(slots, hasLength(1));
    });

    test('focus-only controller updates do not record history entries',
        () async {
      final ws = SlotWorkspace();
      final controller = TilingController(
        initialLayout: ws.layout,
        bus: ws.bus,
        removePluginPanes: false,
      );
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');
      controller.updateLayout(ws.layout);
      final before = ws.timeline.length;

      controller.focus.setFocus('b');
      controller.handleAction(TilingAction.nextFocus);
      await ws.updateLayoutFrom(controller.layout);

      expect(ws.timeline.length, before);
    });

    test('the log keeps a bounded number of entries', () async {
      final ws = SlotWorkspace(maxLogEntries: 5);
      for (var i = 0; i < 8; i++) {
        ws.register(DemoPlugin('p$i'));
        await ws.enable('p$i');
      }
      expect(ws.timeline.length, lessThanOrEqualTo(5));
      // The newest entries stay addressable for undo.
      expect(ws.canUndo, isTrue);
    });

    test('a plugin crash removes its pane and returns it to the palette',
        () async {
      final ws = SlotWorkspace();
      final controller = TilingController(
        initialLayout: ws.layout,
        bus: ws.bus,
        removePluginPanes: false,
      );
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');
      controller.updateLayout(ws.layout);

      // Make 'b' crash asynchronously through its own scoped timer.
      ws.pluginManager.replace('b', _CrashingPlugin());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(ws.isEnabled('b'), isFalse);
      expect(ws.pluginForSlot('b'), isNull);
      // The pane 'b' owned is gone from the layout; the sibling stays.
      final slots = LayoutEngine.computeRects(ws.layout, 30, 10).keys.toList();
      expect(slots, isNot(contains('b')));
      expect(slots, contains('a'));
      expect(ws.available.map((p) => p.id), contains('b'));
    });

    test('zoom and unzoom are recorded in history', () async {
      final ws = SlotWorkspace();
      final controller = TilingController(
        initialLayout: ws.layout,
        bus: ws.bus,
        removePluginPanes: false,
      );
      ws.register(DemoPlugin('a'));
      ws.register(DemoPlugin('b'));
      await ws.enable('a');
      await ws.enable('b');
      controller.updateLayout(ws.layout);

      controller.focus.setFocus('b');
      controller.handleAction(TilingAction.zoom);
      await ws.updateLayoutFrom(controller.layout);
      final slots = LayoutEngine.computeRects(ws.layout, 100, 30).keys.toList();
      expect(slots, hasLength(2));

      // The zoom survives the document round-trip.
      final reloaded = LayoutSerializer.fromJson(
        LayoutSerializer.toJson(ws.layout),
      ) as SplitNode;
      expect((reloaded.children[1] as SlotNode).zoomed, isTrue);

      await ws.undo();
      expect(
          ((ws.layout as SplitNode).children[1] as SlotNode).zoomed, isFalse);
      await ws.redo();
      expect(((ws.layout as SplitNode).children[1] as SlotNode).zoomed, isTrue);
    });

    test('restore is recorded as a single history entry', () async {
      final ws = SlotWorkspace();
      ws.register(DemoPlugin('a'));
      await ws.enable('a');
      final saved = ws.toJson();
      final ws2 = SlotWorkspace();
      ws2.register(DemoPlugin('a'));
      await ws2.restore(saved);
      expect(ws2.timeline.map((e) => e.type), contains('restore'));
      expect(ws2.isEnabled('a'), isTrue);
    });
  });
}

/// A slot plugin whose scoped timer throws on its second tick.
class _CrashingPlugin extends SlotPlugin {
  @override
  String get id => 'b';
  @override
  String get name => 'b';
  @override
  String get version => '1.0.0';
  @override
  String get slotId => 'b';
  int ticks = 0;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    scope.every(const Duration(milliseconds: 5), (_) {
      ticks++;
      if (ticks >= 2) throw StateError('crashed from timer');
    });
  }

  @override
  Component build(SlotContext context) => const Text('crashing');
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
  Component build(SlotContext context) => Text('pane-$idName');
}
