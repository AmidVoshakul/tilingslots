import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('LayoutSerializer.migrate', () {
    test('wraps a node-level document into v1', () {
      final migrated = LayoutSerializer.migrate({
        'type': 'slot',
        'slotId': 'a',
      });
      expect(migrated['version'], 1);
      expect((migrated['root'] as Map)['type'], 'slot');
    });

    test('keeps a v1 document unchanged', () {
      final doc = LayoutSerializer.toDocument(const SlotNode(slotId: 'a'));
      final migrated = LayoutSerializer.migrate(doc);
      expect(migrated, doc);
    });

    test('migrated document parses back', () {
      final migrated = LayoutSerializer.migrate({
        'type': 'slot',
        'slotId': 'a',
      });
      final node = LayoutSerializer.fromJson(migrated);
      expect(node, const SlotNode(slotId: 'a'));
    });

    test('rejects unsupported version', () {
      expect(
        () => LayoutSerializer.migrate({
          'version': 2,
          'root': {'type': 'slot', 'slotId': 'a'}
        }),
        throwsA(isA<LayoutSerializationException>()),
      );
    });
  });
}
