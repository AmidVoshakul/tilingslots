import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('KeyboardBindings', () {
    test('resolves default next-focus shortcut', () {
      final kb = KeyboardBindings();
      final action = kb.resolve(KeyboardEvent(logicalKey: LogicalKey.tab));
      expect(action, TilingAction.nextFocus);
    });

    test('handle invokes callback and returns true', () {
      final kb = KeyboardBindings();
      TilingAction? got;
      final handled = kb.handle(
        KeyboardEvent(logicalKey: LogicalKey.tab),
        onAction: (a) => got = a,
      );
      expect(handled, isTrue);
      expect(got, TilingAction.nextFocus);
    });

    test('unknown key returns false', () {
      final kb = KeyboardBindings();
      final handled = kb.handle(
        KeyboardEvent(logicalKey: LogicalKey.keyA),
        onAction: (_) {},
      );
      expect(handled, isFalse);
    });
  });
}
