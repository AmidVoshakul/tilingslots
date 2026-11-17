import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('LayoutEngine.computeRects', () {
    test('single slot fills area', () {
      final rects =
          LayoutEngine.computeRects(const SlotNode(slotId: 'a'), 80, 24);
      expect(rects['a'], const PaneRect(x: 0, y: 0, width: 80, height: 24));
    });

    test('horizontal split divides width', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      final rects = LayoutEngine.computeRects(node, 80, 24);
      expect(rects['a']!.width, 40);
      expect(rects['b']!.width, 40);
      expect(rects['a']!.height, 24);
    });

    test('vertical split divides height', () {
      const node = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      final rects = LayoutEngine.computeRects(node, 80, 24);
      expect(rects['a']!.height, 12);
      expect(rects['b']!.height, 12);
    });

    test('nested split', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [
          SlotNode(slotId: 'a'),
          SplitNode(
            direction: SplitDirection.vertical,
            children: [SlotNode(slotId: 'b'), SlotNode(slotId: 'c')],
            ratios: [0.5, 0.5],
          ),
        ],
        ratios: [0.5, 0.5],
      );
      final rects = LayoutEngine.computeRects(node, 80, 24);
      expect(rects.keys, containsAll(['a', 'b', 'c']));
      expect(rects['a']!.width, 40);
      expect(rects['b']!.width, 40);
    });
  });

  group('LayoutEngine.normalizeRatios', () {
    test('normalizes to sum 1', () {
      expect(LayoutEngine.normalizeRatios([2.0, 3.0]), [0.4, 0.6]);
    });
    test('handles zero sum', () {
      final r = LayoutEngine.normalizeRatios([0.0, 0.0]);
      expect(r, [0.5, 0.5]);
    });
  });

  group('LayoutEngine mutations', () {
    test('split replaces slot with split', () {
      const root = SlotNode(slotId: 'a');
      final r = LayoutEngine.split(root, [], SplitDirection.horizontal, 'b');
      expect(r, isA<SplitNode>());
      final s = r as SplitNode;
      expect(s.children.length, 2);
      expect(s.children[1], const SlotNode(slotId: 'b'));
    });

    test('remove removes slot and unwraps', () {
      const root = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      final r = LayoutEngine.remove(root, 'a');
      expect(r, const SlotNode(slotId: 'b'));
    });

    test('resize adjusts ratios', () {
      const root = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      final r = LayoutEngine.resize(root, [0], 0.1) as SplitNode;
      expect(r.ratios[0], greaterThan(0.5));
      expect(r.ratios[1], lessThan(0.5));
    });
  });

  group('Convergence edge cases', () {
    test('max depth enforced', () {
      LayoutNode node = const SlotNode(slotId: 'a');
      final path = <int>[];
      for (var i = 0; i < LayoutEngine.maxDepth; i++) {
        node = SplitNode(
          direction: SplitDirection.horizontal,
          children: [node, SlotNode(slotId: 'x$i')],
          ratios: [0.5, 0.5],
        );
        path.insert(0, 0);
      }
      expect(
        () => LayoutEngine.split(node, path, SplitDirection.horizontal, 'new'),
        throwsA(isA<LayoutValidationException>()),
      );
    });

    test('zero area returns empty', () {
      final r = LayoutEngine.computeRects(const SlotNode(slotId: 'a'), 0, 10);
      expect(r, isEmpty);
    });

    test('layout change event emitted on split', () async {
      final bus = EventBus();
      LayoutChangedEvent? ev;
      bus.subscribe<LayoutChangedEvent>((e) => ev = e);
      LayoutEngine.split(
          const SlotNode(slotId: 'a'), [], SplitDirection.horizontal, 'b',
          bus: bus);
      await Future<void>.delayed(Duration.zero);
      expect(ev, isNotNull);
      expect(ev!.operation, 'split');
    });
  });

  group('Convergence coverage', () {
    test('extreme ratios clamped in compute', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.0, 1.0],
      );
      final rects = LayoutEngine.computeRects(node, 10, 10);
      expect(rects['a']!.width, greaterThanOrEqualTo(1));
      expect(rects['b']!.width, greaterThanOrEqualTo(1));
    });

    test('empty split computes no panes', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [],
        ratios: [],
      );
      expect(LayoutEngine.computeRects(node, 80, 24), isEmpty);
    });

    test('zero-width panes are reseeded from the largest pane', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [
          SlotNode(slotId: 'a'),
          SlotNode(slotId: 'b'),
          SlotNode(slotId: 'c'),
        ],
        ratios: [0.0001, 0.0001, 0.9998],
      );
      final rects = LayoutEngine.computeRects(node, 10, 10);
      expect(rects['a']!.width, 1);
      expect(rects['b']!.width, 1);
      expect(rects['c']!.width, 8);
    });

    test('remove publishes layout change event', () async {
      final bus = EventBus();
      LayoutChangedEvent? ev;
      bus.subscribe<LayoutChangedEvent>((e) => ev = e);
      const root = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      final r = LayoutEngine.remove(root, 'a', bus: bus);
      await Future<void>.delayed(Duration.zero);
      expect(ev, isNotNull);
      expect(ev!.operation, 'remove');
      expect(ev!.slotId, 'a');
      expect(r, const SlotNode(slotId: 'b'));
    });

    test('remove rejects removing the root slot', () {
      expect(
        () => LayoutEngine.remove(const SlotNode(slotId: 'a'), 'a'),
        throwsStateError,
      );
    });

    test('split on a non-root slot node path', () {
      const root = SplitNode(
        direction: SplitDirection.horizontal,
        children: [
          SplitNode(
            direction: SplitDirection.vertical,
            children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
            ratios: [0.5, 0.5],
          ),
          SlotNode(slotId: 'c'),
        ],
        ratios: [0.5, 0.5],
      );
      final r =
          LayoutEngine.split(root, const [0, 1], SplitDirection.horizontal, 'x')
              as SplitNode;
      final inner = r.children[0] as SplitNode;
      expect(inner.children[1], isA<SplitNode>());
      expect(r.ratios, [0.5, 0.5]);
    });

    test('split rejects splitting a non-slot root', () {
      const root = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      expect(() => LayoutEngine.split(root, [], SplitDirection.horizontal, 'x'),
          throwsStateError);
    });

    test('resize adjusts a nested boundary', () {
      const root = SplitNode(
        direction: SplitDirection.horizontal,
        children: [
          SplitNode(
            direction: SplitDirection.vertical,
            children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
            ratios: [0.5, 0.5],
          ),
          SlotNode(slotId: 'c'),
        ],
        ratios: [0.5, 0.5],
      );
      final r = LayoutEngine.resize(root, const [0, 0], 0.1) as SplitNode;
      final inner = r.children[0] as SplitNode;
      expect(inner.ratios[0], greaterThan(0.5));
      expect(inner.ratios[1], lessThan(0.5));
      expect(r.ratios, [0.5, 0.5]);
    });

    test('resize publishes layout change event', () async {
      final bus = EventBus();
      LayoutChangedEvent? ev;
      bus.subscribe<LayoutChangedEvent>((e) => ev = e);
      const root = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      LayoutEngine.resize(root, const [0], 0.1, bus: bus);
      await Future<void>.delayed(Duration.zero);
      expect(ev, isNotNull);
      expect(ev!.operation, 'resize');
    });

    test('resize rejects empty path', () {
      expect(
        () => LayoutEngine.resize(const SlotNode(slotId: 'a'), const [], 0.1),
        throwsStateError,
      );
    });

    test('resize rejects invalid boundary', () {
      const root = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      expect(() => LayoutEngine.resize(root, const [1], 0.1), throwsStateError);
      expect(() => LayoutEngine.resize(root, const [5], 0.1), throwsStateError);
    });
  });

  group('zoom', () {
    const tree = SplitNode(
      direction: SplitDirection.horizontal,
      children: [
        SlotNode(slotId: 'a'),
        SlotNode(slotId: 'b', zoomed: true),
      ],
      ratios: [0.5, 0.5],
    );

    test('a zoomed pane takes 95% of the area', () {
      final rects = LayoutEngine.computeRects(tree, 100, 40);
      expect(rects['b']!.width, 95);
      expect(rects['b']!.height, 38);
      expect(rects['b']!.x, 0);
      // The neighbour collapses below the render threshold (3 cells).
      expect(rects['a']!.width, lessThan(3));
    });

    test('without a zoomed pane the split is even', () {
      const plain = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      final rects = LayoutEngine.computeRects(plain, 100, 40);
      expect(rects['a']!.width, 50);
      expect(rects['b']!.width, 50);
    });

    test('nested zoom works from any depth', () {
      final zoomedTree = SplitNode(
        direction: SplitDirection.horizontal,
        children: [
          SplitNode(
            direction: SplitDirection.vertical,
            children: [
              SlotNode(slotId: 'a'),
              SlotNode(slotId: 'b', zoomed: true)
            ],
            ratios: [0.5, 0.5],
          ),
          SlotNode(slotId: 'c'),
        ],
        ratios: [0.5, 0.5],
      );
      final rects = LayoutEngine.computeRects(zoomedTree, 100, 40);
      expect(rects['b']!.width, 95);
      expect(rects['a']!.width, lessThan(3));
      expect(rects['c']!.width, lessThan(3));
    });
  });

  group('Convergence integrity', () {
    test('split clamps and normalizes the new ratio', () {
      const root = SlotNode(slotId: 'a');
      final wild = LayoutEngine.split(root, [], SplitDirection.horizontal, 'b',
          ratio: 5.0) as SplitNode;
      expect(wild.ratios.every((r) => r >= LayoutEngine.minRatio), isTrue);
      expect(wild.ratios.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
      final tiny = LayoutEngine.split(root, [], SplitDirection.horizontal, 'c',
          ratio: -3.0) as SplitNode;
      expect(tiny.ratios.every((r) => r >= LayoutEngine.minRatio), isTrue);
      expect(tiny.ratios.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
    });

    test('split with zero ratio keeps both panes alive', () {
      const root = SlotNode(slotId: 'a');
      final r = LayoutEngine.split(root, [], SplitDirection.horizontal, 'b',
          ratio: 0.0) as SplitNode;
      final rects = LayoutEngine.computeRects(r, 10, 10);
      expect(rects.keys, hasLength(2));
      expect(rects.values.every((rect) => rect.width >= 1), isTrue);
    });

    test('split rejects invalid deep path', () {
      final node = SplitNode(
        direction: SplitDirection.horizontal,
        children: const [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: const [0.5, 0.5],
      );
      expect(
        () =>
            LayoutEngine.split(node, const [9], SplitDirection.horizontal, 'x'),
        throwsA(isA<LayoutValidationException>()),
      );
    });

    test('split rejects path through a slot node', () {
      final node = SplitNode(
        direction: SplitDirection.horizontal,
        children: const [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: const [0.5, 0.5],
      );
      expect(
        () => LayoutEngine.split(
            node, const [0, 0], SplitDirection.horizontal, 'x'),
        throwsA(isA<LayoutValidationException>()),
      );
    });

    test('resize rejects malformed ratios', () {
      final node = SplitNode(
        direction: SplitDirection.horizontal,
        children: const [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: const [0.5],
      );
      expect(
        () => LayoutEngine.resize(node, const [0], 0.1),
        throwsA(isA<LayoutValidationException>()),
      );
    });
  });
}
