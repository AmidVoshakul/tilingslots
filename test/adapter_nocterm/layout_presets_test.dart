import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class _P extends SlotPlugin {
  _P(this.id);
  @override
  final String id;
  @override
  String get name => id;
  @override
  String get version => '0.1.0';
  @override
  String get slotId => id;
  @override
  Component build(SlotContext context) => const Text('p');
}

void main() {
  group('SlotWorkspace.applyPreset', () {
    test('applies preset and updates focus', () async {
      final ws = SlotWorkspace();
      await ws.applyPreset(WorkspacePresets.twoColumns());
      expect(ws.layout, isA<SplitNode>());
      final slots = LayoutEngine.computeRects(ws.layout, 10, 10).keys.toList();
      expect(slots, containsAll(['_pane0', '_pane1']));
    });

    test('orphans enabled plugins on preset change', () async {
      final ws = SlotWorkspace();
      ws.register(_P('a'));
      await ws.enable('a');
      await ws.applyPreset(WorkspacePresets.twoColumns());
      expect(ws.isEnabled('a'), isFalse);
    });
  });
}
