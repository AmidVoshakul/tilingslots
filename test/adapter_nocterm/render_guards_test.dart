import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

import '../../example/tiling_workspace_example.dart';
import 'demo_test_helper.dart';

Future<(SlotWorkspace, TilingController)> _demo() => demoWorkspace();

void main() {
  test('deep splits on a tiny terminal do not break rendering', () async {
    await testNocterm('deep splits on a tiny terminal', (tester) async {
      final (ws, controller) = await _demo();
      ws.register(ClockPlugin(id: 'clock', slot: 'clock'));
      await ws.enable('clock');
      controller.updateLayout(ws.layout);
      await tester.pumpComponent(buildDemoApp(ws, controller));

      // Hammer splits: every split halves the focused pane.
      for (var i = 0; i < 8; i++) {
        await tester.sendKey(LogicalKey.keyS);
      }
      for (var i = 0; i < 4; i++) {
        await tester.sendKey(LogicalKey.keyV);
      }
      final rendered = tester.terminalState.renderToString(showBorders: false);
      if (rendered.contains('Layout Error') ||
          rendered.contains('Paint Error')) {
        throw StateError('render error box appeared:\n$rendered');
      }
      if (!tester.terminalState.containsText('panes:')) {
        throw StateError('status bar lost after deep splits');
      }
    }, size: const Size(40, 16));
  });

  test('panes render on a very small terminal', () async {
    await testNocterm('panes render on a very small terminal', (tester) async {
      final (ws, controller) = await _demo();
      await tester.sendKey(LogicalKey.keyS);
      await tester.pumpComponent(buildDemoApp(ws, controller));
      final rendered = tester.terminalState.renderToString(showBorders: false);
      if (rendered.contains('Layout Error') ||
          rendered.contains('Paint Error')) {
        throw StateError('render error box appeared:\n$rendered');
      }
    }, size: const Size(24, 10));
  });

  test('demo layout survives terminal resize', () async {
    for (final size in [const Size(40, 16), const Size(120, 40)]) {
      await testNocterm('demo layout at ${size.width}x${size.height}',
          (tester) async {
        final (ws, controller) = await _demo();
        await tester.pumpComponent(buildDemoApp(ws, controller));
        if (!tester.terminalState.containsText('now:') &&
            !tester.terminalState.containsText('tilingslots')) {
          throw StateError('no pane rendered at $size');
        }
        if (!tester.terminalState.containsText('palette')) {
          throw StateError('status bar lost at $size');
        }
      }, size: size);
    }
  });
}
