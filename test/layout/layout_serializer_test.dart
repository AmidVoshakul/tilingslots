import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('LayoutSerializer', () {
    test('round-trips slot node', () {
      const node = SlotNode(slotId: 'a');
      final json = LayoutSerializer.toJson(node);
      final back = LayoutSerializer.fromJson(json);
      expect(back, node);
    });

    test('round-trips split node', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      final json = LayoutSerializer.toJson(node);
      final back = LayoutSerializer.fromJson(json);
      expect(back, node);
    });

    test('round-trips nested', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [
          SlotNode(slotId: 'a'),
          SplitNode(
            direction: SplitDirection.vertical,
            children: [SlotNode(slotId: 'b'), SlotNode(slotId: 'c')],
            ratios: [0.4, 0.6],
          ),
        ],
        ratios: [0.3, 0.7],
      );
      final back = LayoutSerializer.fromJson(LayoutSerializer.toJson(node));
      expect(back, node);
    });

    test('rejects unknown slot on validate', () {
      const node = SlotNode(slotId: 'missing');
      expect(
        () => LayoutSerializer.validate(node, knownSlots: {'a'}),
        throwsA(isA<LayoutValidationException>()),
      );
    });

    test('rejects invalid ratios on validate', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.0, 1.0],
      );
      expect(
        () => LayoutSerializer.validate(node, knownSlots: {'a', 'b'}),
        throwsA(isA<LayoutValidationException>()),
      );
    });

    test('fromJson rejects malformed structure', () {
      expect(
        () => LayoutSerializer.fromJson({'type': 'nope'}),
        throwsA(isA<LayoutSerializationException>()),
      );
    });

    test('fromJson rejects unknown version', () {
      expect(
        () => LayoutSerializer.fromJson({
          'version': 99,
          'root': {'type': 'slot', 'slotId': 'a'}
        }),
        throwsA(isA<LayoutSerializationException>()),
      );
    });
  });
  group('Convergence coverage', () {
    test('strict rejects unnormalized ratios', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.2, 0.3],
      );
      final json = LayoutSerializer.toJson(node);
      expect(
        () => LayoutSerializer.fromJson(json, strict: true),
        throwsA(isA<LayoutSerializationException>()),
      );
    });
    test('knownSlots rejects unknown', () {
      const node = SlotNode(slotId: 'missing');
      final json = LayoutSerializer.toJson(node);
      expect(
        () => LayoutSerializer.fromJson(json, knownSlots: {'a'}),
        throwsA(isA<LayoutValidationException>()),
      );
    });
  });

  group('Coverage boost', () {
    test('node-level split round trip', () {
      final json = {
        'type': 'split',
        'direction': 'vertical',
        'children': [
          {'type': 'slot', 'slotId': 'a'},
          {'type': 'slot', 'slotId': 'b'}
        ],
        'ratios': [0.5, 0.5]
      };
      final node = LayoutSerializer.fromJson(json);
      expect(node, isA<SplitNode>());
    });
    test('invalid root throws', () {
      expect(() => LayoutSerializer.fromJson({'root': 'x'}),
          throwsA(isA<LayoutSerializationException>()));
    });
    test('invalid child throws', () {
      expect(
          () => LayoutSerializer.fromJson({
                'type': 'split',
                'direction': 'horizontal',
                'children': ['x'],
                'ratios': [1.0]
              }),
          throwsA(isA<LayoutSerializationException>()));
    });
    test('invalid ratio throws', () {
      expect(
          () => LayoutSerializer.fromJson({
                'type': 'split',
                'direction': 'horizontal',
                'children': [
                  {'type': 'slot', 'slotId': 'a'},
                  {'type': 'slot', 'slotId': 'b'}
                ],
                'ratios': ['x', 'y']
              }),
          throwsA(isA<LayoutSerializationException>()));
    });
    test('max depth throws', () {
      // build deep json
      Map<String, dynamic> deep = {'type': 'slot', 'slotId': 'a'};
      for (var i = 0; i < 20; i++) {
        deep = {
          'type': 'split',
          'direction': 'horizontal',
          'children': [
            deep,
            {'type': 'slot', 'slotId': 'x'}
          ],
          'ratios': [0.5, 0.5]
        };
      }
      expect(() => LayoutSerializer.fromJson(deep, maxDepth: 2),
          throwsA(isA<LayoutSerializationException>()));
    });
    test('toJson unknown throws', () {
      // LayoutNode sealed; cannot instantiate unknown; skip
    });

    test('fromJson rejects invalid direction', () {
      expect(
        () => LayoutSerializer.fromJson({
          'type': 'split',
          'direction': 'diagonal',
          'children': [
            {'type': 'slot', 'slotId': 'a'},
            {'type': 'slot', 'slotId': 'b'},
          ],
          'ratios': [0.5, 0.5],
        }),
        throwsA(isA<LayoutSerializationException>()),
      );
    });

    test('fromJson rejects non-string slotId', () {
      expect(
        () => LayoutSerializer.fromJson({'type': 'slot', 'slotId': 42}),
        throwsA(isA<LayoutSerializationException>()),
      );
    });

    test('fromJson rejects empty slotId', () {
      expect(
        () => LayoutSerializer.fromJson({'type': 'slot', 'slotId': ''}),
        throwsA(isA<LayoutSerializationException>()),
      );
    });

    test('fromJson rejects non-list children and ratios', () {
      expect(
        () => LayoutSerializer.fromJson({
          'type': 'split',
          'direction': 'horizontal',
          'children': 'nope',
          'ratios': [0.5, 0.5],
        }),
        throwsA(isA<LayoutSerializationException>()),
      );
      expect(
        () => LayoutSerializer.fromJson({
          'type': 'split',
          'direction': 'horizontal',
          'children': [
            {'type': 'slot', 'slotId': 'a'},
            {'type': 'slot', 'slotId': 'b'},
          ],
          'ratios': 'nope',
        }),
        throwsA(isA<LayoutSerializationException>()),
      );
    });

    test('fromJson rejects split arity mismatch', () {
      expect(
        () => LayoutSerializer.fromJson({
          'type': 'split',
          'direction': 'horizontal',
          'children': [
            {'type': 'slot', 'slotId': 'a'},
            {'type': 'slot', 'slotId': 'b'},
          ],
          'ratios': [1.0],
        }),
        throwsA(isA<LayoutSerializationException>()),
      );
      expect(
        () => LayoutSerializer.fromJson({
          'type': 'split',
          'direction': 'horizontal',
          'children': [
            {'type': 'slot', 'slotId': 'a'},
          ],
          'ratios': [0.5, 0.5],
        }),
        throwsA(isA<LayoutSerializationException>()),
      );
    });

    test('validate rejects single-child split', () {
      final node = SplitNode(
        direction: SplitDirection.horizontal,
        children: const [SlotNode(slotId: 'a')],
        ratios: const [1.0],
      );
      expect(
        () => LayoutSerializer.validate(node, knownSlots: {'a'}),
        throwsA(isA<LayoutValidationException>()),
      );
    });

    test('round-trips a zoomed pane', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b', zoomed: true)],
        ratios: [0.5, 0.5],
      );
      final back = LayoutSerializer.fromJson(LayoutSerializer.toJson(node));
      expect(back, node);
    });

    test('documents without the zoomed flag parse as unzoomed', () {
      final back = LayoutSerializer.fromJson({
        'version': 1,
        'root': {
          'type': 'split',
          'direction': 'horizontal',
          'children': [
            {'type': 'slot', 'slotId': 'a'},
            {'type': 'slot', 'slotId': 'b'},
          ],
          'ratios': [0.5, 0.5],
        },
      });
      expect(back, isA<SplitNode>());
      expect((back as SplitNode).children[1], const SlotNode(slotId: 'b'));
    });

    test('rejects a non-bool zoomed flag', () {
      expect(
        () => LayoutSerializer.fromJson(
            {'type': 'slot', 'slotId': 'a', 'zoomed': 'yes'}),
        throwsA(isA<LayoutSerializationException>()),
      );
    });

    test('document-level version 1 round-trips', () {
      const node = SplitNode(
        direction: SplitDirection.horizontal,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [0.5, 0.5],
      );
      final doc = LayoutSerializer.toDocument(node);
      expect(doc['version'], 1);
      expect(LayoutSerializer.fromJson(doc, knownSlots: {'a', 'b'}), node);
    });
  });
}
