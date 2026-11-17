import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('CommandPalette', () {
    test('filters commands case-insensitively', () {
      final palette = CommandPalette([
        const PaletteCommand(id: 'split', label: 'Split pane', run: _noop),
        const PaletteCommand(id: 'close', label: 'Close pane', run: _noop),
      ]);
      palette.query = 'split';
      expect(palette.filtered, hasLength(1));
      expect(palette.filtered.first.id, 'split');
    });

    test('executes a registered command', () {
      var called = false;
      final palette = CommandPalette([
        PaletteCommand(id: 'run', label: 'Run', run: () => called = true),
      ]);
      expect(palette.execute('run'), isTrue);
      expect(called, isTrue);
      expect(palette.execute('missing'), isFalse);
    });
  });
}

void _noop() {}
