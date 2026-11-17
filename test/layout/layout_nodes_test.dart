import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('LayoutNodes', () {
    test('SplitNode stores fields', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      expect(node.direction, SplitDirection.horizontal);
      expect(node.children.length, 2);
      expect(node.ratios, [0.5, 0.5]);
    });

    test('SlotNode stores slotId', () {
      const node = SlotNode(slotId: 'x');
      expect(node.slotId, 'x');
    });

    test('SplitNode equality by value', () {
      const a = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a')],
        ratios: [1.0],
      );
      const b = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a')],
        ratios: [1.0],
      );
      // Note: single-child split is structurally allowed here; validation later.
      expect(a, equals(b));
    });

    test('SplitNode inequality by direction, children, ratios', () {
      const base = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      const otherDirection = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      const otherChildren = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'c')],
        ratios: [0.5, 0.5],
      );
      const otherRatios = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.4, 0.6],
      );
      const otherChildCount = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a')],
        ratios: [0.5, 0.5],
      );
      expect(base, isNot(otherDirection));
      expect(base, isNot(otherChildren));
      expect(base, isNot(otherRatios));
      expect(base, isNot(otherChildCount));
      expect(base, isNot(equals(const SlotNode(slotId: 'a'))));
    });

    test('SplitNode hashCode is stable for equal nodes', () {
      const a = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      const b = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      expect(a.hashCode, b.hashCode);
    });

    test('SlotNode equality and hashCode', () {
      const a = SlotNode(slotId: 'a');
      const b = SlotNode(slotId: 'a');
      const c = SlotNode(slotId: 'c');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(equals('a')));
    });

    test('PaneRect equality and hashCode', () {
      const a = PaneRect(x: 1, y: 2, width: 3, height: 4);
      const b = PaneRect(x: 1, y: 2, width: 3, height: 4);
      const c = PaneRect(x: 1, y: 2, width: 3, height: 5);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(equals(0)));
    });
  });
}
