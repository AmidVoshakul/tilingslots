import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('TilingController', () {
    test('resizeBoundary converts cell deltas to ratio deltas', () {
      final c = TilingController(
          initialLayout: const SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      ));
      c.resizeBoundary(const [0], 12, 80); // +12 cells of an 80-wide split
      final ratios = (c.layout as SplitNode).ratios;
      if ((ratios[0] - 0.65).abs() > 0.02) {
        throw StateError('expected ~0.65, got ${ratios[0]}');
      }
    });

    test('resizeBoundary clamps at the minimum ratio', () {
      final c = TilingController(
          initialLayout: const SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      ));
      c.resizeBoundary(const [0], -1000, 80);
      final ratios = (c.layout as SplitNode).ratios;
      expect(ratios[0], lessThanOrEqualTo(LayoutEngine.minRatio + 0.001));
      expect(ratios[1], greaterThan(0));
    });

    test('resizeBoundary rejects an invalid boundary', () {
      final c = TilingController(
          initialLayout: const SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      ));
      expect(() => c.resizeBoundary(const [1], 5, 80), throwsStateError);
      expect(() => c.resizeBoundary(const [9], 5, 80), throwsStateError);
    });

    test('resizeBoundary publishes a layout change event', () async {
      final bus = EventBus();
      final c = TilingController(
          initialLayout: const SplitNode(
            direction: SplitDirection.horizontal,
            children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
            ratios: [0.5, 0.5],
          ),
          bus: bus);
      LayoutChangedEvent? event;
      bus.subscribe<LayoutChangedEvent>((e) => event = e);
      c.resizeBoundary(const [0], 5, 80);
      await Future<void>.delayed(Duration.zero);
      expect(event?.operation, 'resize');
    });

    test('zoom action maximizes and restores the focused pane', () {
      final c = TilingController(
          initialLayout: const SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      ));
      c.focus.setFocus('a');
      c.handleAction(TilingAction.zoom);
      LayoutNode zoomed = c.layout;
      expect(_isZoomed(zoomed, 'a'), isTrue);
      final rects = LayoutEngine.computeRects(zoomed, 100, 30);
      expect(rects['a']!.width, 95);

      c.handleAction(TilingAction.zoom); // toggle back
      zoomed = c.layout;
      expect(_isZoomed(zoomed, 'a'), isFalse);
      final back = (zoomed as SplitNode).ratios;
      expect(back[0], closeTo(0.5, 0.001));
    });

    test('zoom moves to the newly focused pane', () {
      final c = TilingController(
          initialLayout: const SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.30, 0.70],
      ));
      c.focus.setFocus('b');
      c.handleAction(TilingAction.zoom);
      expect(_isZoomed(c.layout, 'b'), isTrue);
      // The previous zoom is released when another pane gets focus.
      c.focus.setFocus('a');
      c.handleAction(TilingAction.zoom);
      expect(_isZoomed(c.layout, 'a'), isTrue);
      expect(_isZoomed(c.layout, 'b'), isFalse);
    });

    test('zoom publishes a layout change event', () async {
      final bus = EventBus();
      final c = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
          ratios: [0.5, 0.5],
        ),
        bus: bus,
      );
      c.focus.setFocus('a');
      LayoutChangedEvent? event;
      bus.subscribe<LayoutChangedEvent>((e) => event = e);
      c.handleAction(TilingAction.zoom);
      await Future<void>.delayed(Duration.zero);
      expect(event?.operation, 'zoom');
    });

    test('next/prev focus', () {
      final c = TilingController(
          initialLayout: const SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      ));
      c.focus.setFocus('a');
      c.handleAction(TilingAction.nextFocus);
      expect(c.focus.current, 'b');
      c.handleAction(TilingAction.prevFocus);
      expect(c.focus.current, 'a');
    });

    test('split horizontal adds slot', () {
      final c = TilingController(initialLayout: const SlotNode(slotId: 'a'));
      c.focus.setFocus('a');
      c.handleAction(TilingAction.splitHorizontal);
      expect(
          LayoutEngine.computeRects(c.layout, 10, 10).keys, contains('a_new'));
    });

    test('close removes slot', () {
      final c = TilingController(
          initialLayout: const SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      ));
      c.focus.setFocus('a');
      c.handleAction(TilingAction.close);
      expect(LayoutEngine.computeRects(c.layout, 10, 10).keys,
          isNot(contains('a')));
    });

    test('repeated splits of the same slot produce unique ids', () {
      final c = TilingController(initialLayout: const SlotNode(slotId: 'a'));
      c.focus.setFocus('a');
      c.handleAction(TilingAction.splitHorizontal);
      c.focus.setFocus('a');
      c.handleAction(TilingAction.splitVertical);
      final slots = LayoutEngine.computeRects(c.layout, 10, 10).keys.toList();
      expect(slots, hasLength(3));
      expect(slots, containsAll(['a', 'a_new', 'a_new_2']));
    });

    test('a failing layout mutation is reported, not swallowed', () {
      Object? error;
      final c = TilingController(
        // Malformed: two children, one ratio.
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
          ratios: [0.5],
        ),
        onError: (e, st) => error ??= e,
      );
      c.focus.setFocus('a');
      c.handleAction(TilingAction.resizeGrow);
      if (error == null) throw StateError('failed resize was swallowed');
    });

    test('plugin disable removes the plugin slot, not the plugin id', () async {
      final workspace = SlotWorkspace();
      final controller = TilingController(
        initialLayout: workspace.layout,
        bus: workspace.bus,
      );
      final plugin = _SlotVariantPlugin('plug-a', 'slot-a');
      workspace.register(plugin);
      await workspace.enable('plug-a');
      controller.updateLayout(workspace.layout);
      expect(LayoutEngine.computeRects(controller.layout, 10, 10).keys,
          contains('slot-a'));
      await workspace.disable('plug-a');
      await Future<void>.delayed(Duration.zero);
      expect(LayoutEngine.computeRects(controller.layout, 10, 10).keys,
          isNot(contains('slot-a')));
    });

    test('unknown key event is ignored', () {
      final c = TilingController(initialLayout: const SlotNode(slotId: 'a'));
      c.focus.setFocus('a');
      final handled =
          c.handleKeyEvent(KeyboardEvent(logicalKey: LogicalKey.keyA));
      expect(handled, isFalse);
      expect(LayoutEngine.computeRects(c.layout, 10, 10).keys, contains('a'));
    });

    test('handleKeyEvent dispatches bound actions', () {
      final c = TilingController(initialLayout: const SlotNode(slotId: 'a'));
      c.focus.setFocus('a');
      expect(
          c.handleKeyEvent(KeyboardEvent(logicalKey: LogicalKey.keyS)), isTrue);
      expect(LayoutEngine.computeRects(c.layout, 10, 10).keys, hasLength(2));
    });

    test('resize grow then shrink is a near no-op', () {
      final c = TilingController(
          initialLayout: const SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      ));
      c.focus.setFocus('b');
      c.handleAction(TilingAction.resizeGrow);
      c.handleAction(TilingAction.resizeShrink);
      final ratios = (c.layout as SplitNode).ratios;
      expect(ratios[0], closeTo(0.5, 0.05));
    });

    test('custom keyboard bindings are honored', () {
      final bindings = KeyboardBindings(
        keymap: Keymap({LogicalKey.keyQ: TilingAction.close}),
      );
      final c = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
          ratios: [0.5, 0.5],
        ),
        keyboardBindings: bindings,
      );
      c.focus.setFocus('a');
      expect(c.keyboardBindings, same(bindings));
      expect(
          c.handleKeyEvent(KeyboardEvent(logicalKey: LogicalKey.keyQ)), isTrue);
      expect(LayoutEngine.computeRects(c.layout, 10, 10).keys,
          isNot(contains('a')));
    });

    test('updateLayout refreshes focus slots', () {
      final c = TilingController(initialLayout: const SlotNode(slotId: 'a'));
      c.updateLayout(const SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      ));
      expect(c.focus.traversalOrder, containsAll(['a', 'b']));
    });

    test('dispose releases the plugin subscription', () async {
      final workspace = SlotWorkspace();
      final controller = TilingController(
        initialLayout: workspace.layout,
        bus: workspace.bus,
      );
      final plugin = _SlotVariantPlugin('plug-b', 'slot-b');
      workspace.register(plugin);
      await workspace.enable('plug-b');
      controller.updateLayout(workspace.layout);
      controller.dispose();
      await workspace.disable('plug-b');
      await Future<void>.delayed(Duration.zero);
      // The cancelled subscription leaves the controller layout untouched.
      expect(LayoutEngine.computeRects(controller.layout, 10, 10).keys,
          contains('slot-b'));
    });

    test('plugin disable never wipes a childless layout', () async {
      final workspace = SlotWorkspace();
      final controller = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [],
          ratios: [],
        ),
        bus: workspace.bus,
      );
      workspace.register(_SlotVariantPlugin('plug-c', 'slot-c'));
      await workspace.enable('plug-c');
      await workspace.disable('plug-c');
      await Future<void>.delayed(Duration.zero);
      expect(controller.layout, isA<SplitNode>());
      expect((controller.layout as SplitNode).children.length, 0);
    });
  });
}

class _SlotVariantPlugin extends SlotPlugin {
  _SlotVariantPlugin(this.pluginId, this.slot);

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
  Component build(SlotContext context) => Text(slot);
}

bool _isZoomed(LayoutNode node, String slotId) {
  if (node is SlotNode) return node.slotId == slotId && node.zoomed;
  if (node is SplitNode) {
    return node.children.any((child) => _isZoomed(child, slotId));
  }
  return false;
}
