import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('WorkspacePresets', () {
    test('twoColumns has two panes', () {
      final preset = WorkspacePresets.twoColumns();
      expect(preset, isA<SplitNode>());
      final split = preset;
      expect(split.direction, SplitDirection.horizontal);
      expect(split.children, hasLength(2));
      expect(split.ratios, [0.5, 0.5]);
    });

    test('threeColumns has three panes', () {
      final preset = WorkspacePresets.threeColumns();
      final split = preset;
      expect(split.children, hasLength(3));
    });

    test('grid2x2 has nested splits', () {
      final preset = WorkspacePresets.grid2x2();
      final split = preset;
      expect(split.children, hasLength(2));
      expect(split.children.first, isA<SplitNode>());
    });
  });
}
