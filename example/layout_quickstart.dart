import 'package:tilingslots/tilingslots_core.dart';

/// Headless layout demo: rect computation, split, and JSON round-trip.
void main() {
  // Build a 70/30 side-by-side layout for an 80x24 terminal.
  final layout = SplitNode(
    direction: SplitDirection.horizontal,
    children: const [SlotNode(slotId: 'logs'), SlotNode(slotId: 'metrics')],
    ratios: const [0.7, 0.3],
  );

  // Compute terminal-cell rectangles.
  for (final entry in LayoutEngine.computeRects(layout, 80, 24).entries) {
    final r = entry.value;
    print('${entry.key}: ${r.width}x${r.height} at (${r.x}, ${r.y})');
  }

  // Split the left slot into two stacked panes.
  final nested = LayoutEngine.split(
    layout,
    const [0],
    SplitDirection.vertical,
    'log-details',
  );

  // Serialize to a versioned document and restore it.
  final document = LayoutSerializer.toDocument(nested);
  final knownSlots = {'logs', 'metrics', 'log-details'};
  final restored = LayoutSerializer.fromJson(document);
  LayoutSerializer.validate(restored, knownSlots: knownSlots);
  print('restored slots: ${LayoutEngine.computeRects(restored, 80, 24).keys}');
}
