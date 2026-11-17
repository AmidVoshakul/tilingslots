import '../core/event_bus.dart';
import 'layout_events.dart';
import 'layout_exceptions.dart';
import 'layout_nodes.dart';

/// Pure layout math engine.
class LayoutEngine {
  const LayoutEngine._();

  static const int maxDepth = 16;
  static const double minRatio = 0.05;

  static Map<String, PaneRect> computeRects(
      LayoutNode root, int width, int height) {
    if (width <= 0 || height <= 0) return <String, PaneRect>{};
    final result = <String, PaneRect>{};
    _compute(root, 0, 0, width, height, result);
    final zoomedSlot = _findZoomedSlot(root);
    if (zoomedSlot == null) return result;
    // The zoomed pane takes 95% of the area; siblings collapse (and get
    // skipped by renderers below the minimum pane extent).
    final zoomedRect = PaneRect(
      x: 0,
      y: 0,
      width: (width * 19 ~/ 20).clamp(0, width),
      height: (height * 19 ~/ 20).clamp(0, height),
    );
    result[zoomedSlot] = zoomedRect;
    for (final slot in result.keys.toList()) {
      if (slot == zoomedSlot) continue;
      final rect = result[slot]!;
      result[slot] = PaneRect(
        x: (rect.x * 19 ~/ 1000).clamp(0, width),
        y: (rect.y * 19 ~/ 1000).clamp(0, height),
        width: (rect.width * 19 ~/ 1000).clamp(0, width),
        height: (rect.height * 19 ~/ 1000).clamp(0, height),
      );
    }
    return result;
  }

  static String? _findZoomedSlot(LayoutNode node) {
    if (node is SlotNode) return node.zoomed ? node.slotId : null;
    if (node is SplitNode) {
      for (final child in node.children) {
        final found = _findZoomedSlot(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  static void _compute(
    LayoutNode node,
    int x,
    int y,
    int width,
    int height,
    Map<String, PaneRect> result,
  ) {
    if (node is SlotNode) {
      result[node.slotId] = PaneRect(x: x, y: y, width: width, height: height);
      return;
    }
    if (node is SplitNode) {
      final ratios = _clampedNormalized(node.ratios);
      final n = node.children.length < ratios.length
          ? node.children.length
          : ratios.length;
      if (n == 0) return;
      if (node.direction == SplitDirection.horizontal) {
        final sizes = _distribute(width, ratios, n);
        var cx = x;
        for (var i = 0; i < n; i++) {
          final w = sizes[i].clamp(0, width);
          _compute(node.children[i], cx, y, w, height, result);
          cx += w;
        }
      } else {
        final sizes = _distribute(height, ratios, n);
        var cy = y;
        for (var i = 0; i < n; i++) {
          final h = sizes[i].clamp(0, height);
          _compute(node.children[i], x, cy, width, h, result);
          cy += h;
        }
      }
    }
  }

  static List<double> _clampedNormalized(List<double> ratios) {
    if (ratios.isEmpty) return ratios;
    final clamped =
        ratios.map((r) => r.clamp(minRatio, 1.0).toDouble()).toList();
    return normalizeRatios(clamped);
  }

  static List<int> _distribute(int total, List<double> ratios, int n) {
    final normalized = _clampedNormalized(ratios).sublist(0, n);
    final raw = List<double>.generate(n, (i) => total * normalized[i]);
    final floors = raw.map((v) => v.floor()).toList();
    var leftover = total - floors.fold<int>(0, (a, b) => a + b);
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => (raw[b] - floors[b]).compareTo(raw[a] - floors[a]));
    var i = 0;
    while (leftover > 0 && n > 0) {
      floors[order[i % n]] += 1;
      leftover -= 1;
      i++;
    }
    // ensure no zero-size panes when space allows
    if (total >= n) {
      for (var j = 0; j < n; j++) {
        if (floors[j] == 0) {
          // steal from largest
          var maxIdx = 0;
          for (var k = 1; k < n; k++) {
            if (floors[k] > floors[maxIdx]) maxIdx = k;
          }
          if (floors[maxIdx] > 1) {
            floors[maxIdx] -= 1;
            floors[j] = 1;
          }
        }
      }
    }
    return floors;
  }

  static List<double> normalizeRatios(List<double> ratios) {
    if (ratios.isEmpty) return ratios;
    final sum = ratios.fold<double>(0, (a, b) => a + b);
    if (sum == 0) {
      return List<double>.filled(ratios.length, 1.0 / ratios.length);
    }
    return ratios.map((r) => r / sum).toList(growable: false);
  }

  static LayoutNode split(
    LayoutNode root,
    List<int> path,
    SplitDirection direction,
    String newSlotId, {
    double ratio = 0.5,
    EventBus? bus,
    bool publishEvent = true,
  }) {
    _validatePath(root, path);
    final targetDepth = _depth(root, path) + 1;
    if (targetDepth > maxDepth) {
      throw LayoutValidationException('Max depth exceeded');
    }
    final clampedRatio = ratio.clamp(minRatio, 1.0 - minRatio).toDouble();
    final ratios = normalizeRatios([1 - clampedRatio, clampedRatio]);
    LayoutNode result;
    if (path.isEmpty) {
      if (root is SlotNode) {
        result = SplitNode(
          direction: direction,
          children: [root, SlotNode(slotId: newSlotId)],
          ratios: ratios,
        );
      } else {
        throw StateError('Can only split a slot node');
      }
    } else if (root is SplitNode) {
      final idx = path.first;
      final rest = path.sublist(1);
      final newChildren = List<LayoutNode>.from(root.children);
      newChildren[idx] = split(newChildren[idx], rest, direction, newSlotId,
          ratio: ratio, bus: bus, publishEvent: false);
      result = SplitNode(
        direction: root.direction,
        children: newChildren,
        ratios: List<double>.from(root.ratios),
      );
    } else {
      throw StateError('Invalid path');
    }
    if (publishEvent) {
      bus?.publish(LayoutChangedEvent(operation: 'split', slotId: newSlotId));
    }
    return result;
  }

  /// Rejects paths that do not resolve to a slot node in [root].
  static void _validatePath(LayoutNode node, List<int> path) {
    if (path.isEmpty) return;
    if (node is! SplitNode) {
      throw LayoutValidationException('Path continues past a slot node');
    }
    final idx = path.first;
    if (idx < 0 || idx >= node.children.length) {
      throw LayoutValidationException('Invalid path index: $idx');
    }
    _validatePath(node.children[idx], path.sublist(1));
  }

  static int _depth(LayoutNode node, List<int> path) {
    if (path.isEmpty) return 0;
    if (node is SplitNode) {
      final idx = path.first;
      return 1 + _depth(node.children[idx], path.sublist(1));
    }
    return 0;
  }

  static LayoutNode remove(LayoutNode root, String slotId, {EventBus? bus}) {
    final result = _remove(root, slotId);
    if (result == null) {
      throw StateError('Cannot remove root slot');
    }
    bus?.publish(LayoutChangedEvent(operation: 'remove', slotId: slotId));
    return result;
  }

  static LayoutNode? _remove(LayoutNode node, String slotId) {
    if (node is SlotNode) {
      return node.slotId == slotId ? null : node;
    }
    if (node is SplitNode) {
      final newChildren = <LayoutNode>[];
      final newRatios = <double>[];
      for (var i = 0; i < node.children.length; i++) {
        final r = _remove(node.children[i], slotId);
        if (r != null) {
          newChildren.add(r);
          newRatios.add(i < node.ratios.length ? node.ratios[i] : 1.0);
        }
      }
      if (newChildren.isEmpty) return null;
      if (newChildren.length == 1) return newChildren.first;
      return SplitNode(
        direction: node.direction,
        children: newChildren,
        ratios: normalizeRatios(newRatios),
      );
    }
    return node;
  }

  static LayoutNode resize(LayoutNode root, List<int> path, double delta,
      {EventBus? bus, bool publishEvent = true}) {
    LayoutNode result;
    if (path.isEmpty) {
      throw StateError('Resize path must identify a split boundary');
    }
    if (path.length == 1) {
      if (root is! SplitNode) throw StateError('Root is not a split');
      final boundary = path.first;
      if (boundary < 0 || boundary + 1 >= root.children.length) {
        throw StateError('Invalid boundary index');
      }
      if (boundary + 1 >= root.ratios.length) {
        throw LayoutValidationException('Ratios/children mismatch');
      }
      final ratios = List<double>.from(root.ratios);
      ratios[boundary] =
          (ratios[boundary] + delta).clamp(minRatio, 1 - minRatio);
      ratios[boundary + 1] =
          (ratios[boundary + 1] - delta).clamp(minRatio, 1 - minRatio);
      result = SplitNode(
        direction: root.direction,
        children: List<LayoutNode>.from(root.children),
        ratios: normalizeRatios(ratios),
      );
    } else if (root is SplitNode) {
      final idx = path.first;
      if (idx < 0 || idx >= root.children.length) {
        throw StateError('Invalid path');
      }
      final rest = path.sublist(1);
      final newChildren = List<LayoutNode>.from(root.children);
      newChildren[idx] =
          resize(newChildren[idx], rest, delta, bus: bus, publishEvent: false);
      result = SplitNode(
        direction: root.direction,
        children: newChildren,
        ratios: List<double>.from(root.ratios),
      );
    } else {
      throw StateError('Invalid path');
    }
    if (publishEvent) {
      bus?.publish(LayoutChangedEvent(operation: 'resize'));
    }
    return result;
  }
}
