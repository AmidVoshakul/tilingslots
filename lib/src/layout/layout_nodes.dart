/// Tiling layout node model (pure Dart).

enum SplitDirection { horizontal, vertical }

/// Base layout node.
sealed class LayoutNode {
  const LayoutNode();
}

/// Container node splitting space.
class SplitNode extends LayoutNode {
  const SplitNode({
    required this.direction,
    required this.children,
    required this.ratios,
  });

  final SplitDirection direction;
  final List<LayoutNode> children;
  final List<double> ratios;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SplitNode) return false;
    if (direction != other.direction) return false;
    if (children.length != other.children.length) return false;
    for (var i = 0; i < children.length; i++) {
      if (children[i] != other.children[i]) return false;
    }
    if (ratios.length != other.ratios.length) return false;
    for (var i = 0; i < ratios.length; i++) {
      if (ratios[i] != other.ratios[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(direction, Object.hashAll(children), Object.hashAll(ratios));
}

/// Leaf node referencing a slot.
/// Leaf node referencing a slot. [zoomed] marks the pane as maximized: it
/// takes 95% of the workspace area and its siblings collapse out of view.
class SlotNode extends LayoutNode {
  const SlotNode({required this.slotId, this.zoomed = false});

  final String slotId;
  final bool zoomed;

  @override
  bool operator ==(Object other) =>
      other is SlotNode && other.slotId == slotId && other.zoomed == zoomed;

  @override
  int get hashCode => Object.hash(slotId, zoomed);
}

/// Rectangle in terminal grid.
class PaneRect {
  const PaneRect(
      {required this.x,
      required this.y,
      required this.width,
      required this.height});

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is PaneRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}
