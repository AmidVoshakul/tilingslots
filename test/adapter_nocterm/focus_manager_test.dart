import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('FocusManager', () {
    test('traversal order and initial focus', () {
      final f = FocusManager(slotOrder: ['a', 'b', 'c']);
      expect(f.traversalOrder, ['a', 'b', 'c']);
      expect(f.current, isNull);
    });

    test('setFocus and next/prev', () {
      final f = FocusManager(slotOrder: ['a', 'b', 'c']);
      f.setFocus('a');
      expect(f.current, 'a');
      f.next();
      expect(f.current, 'b');
      f.next();
      expect(f.current, 'c');
      f.next();
      expect(f.current, 'a'); // wrap
      f.prev();
      expect(f.current, 'c');
    });

    test('setFocus unknown throws', () {
      final f = FocusManager(slotOrder: ['a']);
      expect(() => f.setFocus('z'), throwsStateError);
    });
  });
}
