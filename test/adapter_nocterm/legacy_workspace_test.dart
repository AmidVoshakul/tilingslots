import 'dart:convert';
import 'dart:io';

import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

import 'demo_test_helper.dart';
import '../../example/tiling_workspace_example.dart';

Future<(SlotWorkspace, TilingController)> _demo() => demoWorkspace();

/// Mirrors main()'s restore-or-seed flow from the demo.
Future<void> restoreOrSeed(SlotWorkspace workspace, String path) async {
  final file = File(path);
  if (file.existsSync()) {
    try {
      await workspace
          .restore(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } on Object catch (error) {
      // ignore: avoid_print
      print(
          'Could not restore $path ($error) — starting with a fresh workspace.');
      await workspace.enable('header');
    }
  } else {
    // Mirrors main(): a fresh workspace starts with the header only; the
    // palette fills the rest.
    await workspace.enable('header');
  }
}

void main() {
  test('legacy workspace document does not break the demo', () async {
    final path = '${Directory.systemTemp.path}/tilingslots_legacy_ws.json';
    // Document written by the pre-0.1.0 demo (plugin ids no longer exist).
    File(path).writeAsStringSync(jsonEncode({
      'enabled': ['header', 'clock', 'status'],
      'layout': {
        'version': 1,
        'root': {
          'type': 'split',
          'direction': 'horizontal',
          'children': [
            {'type': 'slot', 'slotId': 'header'},
            {'type': 'slot', 'slotId': 'clock'},
            {'type': 'slot', 'slotId': 'status'},
          ],
          'ratios': [0.33, 0.33, 0.34],
        },
      },
    }));

    await testNocterm('legacy workspace document does not break the demo',
        (tester) async {
      final (ws, controller) = await _demo();
      await restoreOrSeed(ws, path);
      controller.updateLayout(ws.layout);
      await tester.pumpComponent(buildDemoApp(ws, controller));
      final rendered = tester.terminalState.renderToString(showBorders: false);
      if (rendered.contains('Layout Error') ||
          rendered.contains('Paint Error')) {
        throw StateError('render error box appeared:\n$rendered');
      }
    }, size: const Size(60, 18));

    File(path).deleteSync();
  });

  test('closing panes down to empty and re-splitting stays renderable',
      () async {
    await testNocterm('closing panes down to empty and re-splitting',
        (tester) async {
      final (ws, controller) = await _demo();
      await tester.pumpComponent(buildDemoApp(ws, controller));

      // Close panes one by one, then split the empty workspace again.
      for (var i = 0; i < 4; i++) {
        await tester.sendKey(LogicalKey.keyX);
      }
      await tester.sendKey(LogicalKey.keyS);
      await tester.sendKey(LogicalKey.tab);
      final rendered = tester.terminalState.renderToString(showBorders: false);
      if (rendered.contains('Layout Error') ||
          rendered.contains('Paint Error')) {
        throw StateError('render error box appeared:\n$rendered');
      }
      if (!tester.terminalState.containsText('panes:')) {
        throw StateError('status bar lost');
      }
    }, size: const Size(60, 18));
  });
}
