import 'package:tilingslots/tilingslots_core.dart';

void main() {
  final layout = SplitNode(
    direction: SplitDirection.horizontal,
    children: const [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
    ratios: const [0.5, 0.5],
  );
  final rects = LayoutEngine.computeRects(layout, 80, 24);
  for (final entry in rects.entries) {
    print('${entry.key}: ${entry.value.x},${entry.value.y} '
        '${entry.value.width}x${entry.value.height}');
  }
}
