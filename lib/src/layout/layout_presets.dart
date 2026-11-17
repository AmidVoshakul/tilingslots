import 'layout_nodes.dart';

/// Declarative workspace layout presets built from [LayoutNode]s.
class WorkspacePresets {
  const WorkspacePresets._();

  static SplitNode twoColumns() => const SplitNode(
        direction: SplitDirection.horizontal,
        children: <LayoutNode>[
          SlotNode(slotId: '_pane0'),
          SlotNode(slotId: '_pane1'),
        ],
        ratios: <double>[0.5, 0.5],
      );

  static SplitNode threeColumns() => const SplitNode(
        direction: SplitDirection.horizontal,
        children: <LayoutNode>[
          SlotNode(slotId: '_pane0'),
          SlotNode(slotId: '_pane1'),
          SlotNode(slotId: '_pane2'),
        ],
        ratios: <double>[1 / 3, 1 / 3, 1 / 3],
      );

  static SplitNode mainAndSidebar() => const SplitNode(
        direction: SplitDirection.horizontal,
        children: <LayoutNode>[
          SlotNode(slotId: '_main'),
          SlotNode(slotId: '_sidebar'),
        ],
        ratios: <double>[0.7, 0.3],
      );

  static SplitNode grid2x2() => SplitNode(
        direction: SplitDirection.vertical,
        children: <LayoutNode>[
          SplitNode(
            direction: SplitDirection.horizontal,
            children: const <LayoutNode>[
              SlotNode(slotId: '_pane0'),
              SlotNode(slotId: '_pane1'),
            ],
            ratios: const <double>[0.5, 0.5],
          ),
          SplitNode(
            direction: SplitDirection.horizontal,
            children: const <LayoutNode>[
              SlotNode(slotId: '_pane2'),
              SlotNode(slotId: '_pane3'),
            ],
            ratios: const <double>[0.5, 0.5],
          ),
        ],
        ratios: const <double>[0.5, 0.5],
      );
}
