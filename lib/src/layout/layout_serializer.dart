import 'layout_exceptions.dart';
import 'layout_nodes.dart';
import 'layout_engine.dart';

/// JSON serialization and validation for layout trees.
class LayoutSerializer {
  const LayoutSerializer._();

  static Map<String, dynamic> toJson(LayoutNode node) {
    if (node is SlotNode) {
      return {'type': 'slot', 'slotId': node.slotId, 'zoomed': node.zoomed};
    }
    if (node is SplitNode) {
      return {
        'type': 'split',
        'direction': node.direction == SplitDirection.horizontal
            ? 'horizontal'
            : 'vertical',
        'children': node.children.map(toJson).toList(growable: false),
        'ratios': node.ratios,
      };
    }
    throw LayoutSerializationException('Unknown node type');
  }

  /// Serializes a full layout document including version.
  static Map<String, dynamic> toDocument(LayoutNode root) {
    return {'version': 1, 'root': toJson(root)};
  }

  static LayoutNode fromJson(Map<String, dynamic> json,
      {Set<String>? knownSlots,
      int maxDepth = LayoutEngine.maxDepth,
      bool strict = false}) {
    if (json.containsKey('root')) {
      final version = json['version'];
      if (version != null && version != 1) {
        throw LayoutSerializationException(
            'Unsupported layout version: $version');
      }
      final root = json['root'];
      if (root is! Map<String, dynamic>) {
        throw LayoutSerializationException('Invalid root');
      }
      final node = _parseNode(root, 0, maxDepth, strict);
      if (knownSlots != null) validate(node, knownSlots: knownSlots);
      return node;
    }
    // node-level
    if (json.containsKey('version')) {
      final version = json['version'];
      if (version != 1) {
        throw LayoutSerializationException(
            'Unsupported layout version: $version');
      }
    }
    final node = _parseNode(json, 0, maxDepth, strict);
    if (knownSlots != null) validate(node, knownSlots: knownSlots);
    return node;
  }

  static LayoutNode _parseNode(
      Map<String, dynamic> json, int depth, int maxDepth, bool strict) {
    if (depth > maxDepth) {
      throw LayoutSerializationException('Max depth exceeded');
    }
    final type = json['type'];
    if (type == 'slot') {
      final slotId = json['slotId'];
      if (slotId is! String || slotId.isEmpty) {
        throw LayoutSerializationException('Invalid slotId');
      }
      final zoomed = json['zoomed'];
      if (zoomed != null && zoomed is! bool) {
        throw LayoutSerializationException('Invalid zoomed flag');
      }
      return SlotNode(slotId: slotId, zoomed: zoomed == true);
    }
    if (type == 'split') {
      final dirStr = json['direction'];
      final direction = dirStr == 'horizontal'
          ? SplitDirection.horizontal
          : dirStr == 'vertical'
              ? SplitDirection.vertical
              : null;
      if (direction == null) {
        throw LayoutSerializationException('Invalid direction');
      }
      final childrenRaw = json['children'];
      final ratiosRaw = json['ratios'];
      if (childrenRaw is! List || ratiosRaw is! List) {
        throw LayoutSerializationException('Invalid children/ratios');
      }
      if (childrenRaw.length < 2 || childrenRaw.length != ratiosRaw.length) {
        throw LayoutSerializationException('Invalid split arity');
      }
      final children = <LayoutNode>[];
      for (final c in childrenRaw) {
        if (c is! Map<String, dynamic>) {
          throw LayoutSerializationException('Invalid child');
        }
        children.add(_parseNode(c, depth + 1, maxDepth, strict));
      }
      final ratios = <double>[];
      for (final r in ratiosRaw) {
        if (r is! num) {
          throw LayoutSerializationException('Invalid ratio');
        }
        ratios.add(r.toDouble());
      }
      if (strict) {
        final sum = ratios.fold<double>(0, (a, b) => a + b);
        if ((sum - 1.0).abs() > 1e-9) {
          throw LayoutSerializationException(
              'Ratios must sum to 1.0 in strict mode');
        }
      }
      // normalize ratios
      final normalized = LayoutEngine.normalizeRatios(ratios);
      return SplitNode(
          direction: direction, children: children, ratios: normalized);
    }
    throw LayoutSerializationException('Unknown node type: $type');
  }

  static void validate(LayoutNode node, {required Set<String> knownSlots}) {
    if (node is SlotNode) {
      if (!knownSlots.contains(node.slotId)) {
        throw LayoutValidationException('Unknown slot: ${node.slotId}');
      }
      return;
    }
    if (node is SplitNode) {
      if (node.children.length < 2) {
        throw LayoutValidationException('Split must have at least 2 children');
      }
      if (node.children.length != node.ratios.length) {
        throw LayoutValidationException('Ratios/children mismatch');
      }
      for (final r in node.ratios) {
        if (r < 0) {
          throw LayoutValidationException('Negative ratio');
        }
      }
      // reject any zero? spec says extreme ratios clamp; validation rejects 0? Test uses 0.0 ratio invalid.
      if (node.ratios.any((r) => r == 0.0)) {
        throw LayoutValidationException('Zero ratio not allowed');
      }
      for (final c in node.children) {
        validate(c, knownSlots: knownSlots);
      }
    }
  }
}
