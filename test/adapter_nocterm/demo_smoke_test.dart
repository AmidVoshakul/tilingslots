import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

import 'demo_test_helper.dart';
import '../../example/tiling_workspace_example.dart';

Future<(SlotWorkspace, TilingController)> _demo() => demoWorkspace();
Future<void> _flush(NoctermTester tester) => flushFrames(tester);
int _paneCount(TilingController c) => paneCount(c);

void main() {
  test('demo starts with a single header pane', () async {
    await testNocterm('demo starts with a single header pane', (tester) async {
      final (ws, controller) = await _demo();
      await tester.pumpComponent(buildDemoApp(ws, controller));
      if (!tester.terminalState.containsText('tilingslots')) {
        throw StateError('header pane not rendered');
      }
      if (_paneCount(controller) != 1) {
        throw StateError('expected one pane, got ${_paneCount(controller)}');
      }
      if (!tester.terminalState.containsText('palette')) {
        throw StateError('status bar not rendered');
      }
    });
  });

  test('palette digit fills an empty pane with the chosen plugin', () async {
    await testNocterm('palette digit fills an empty pane', (tester) async {
      final (ws, controller) = await _demo();
      await tester.pumpComponent(buildDemoApp(ws, controller));

      // Split the workspace, then attach the clock to the new empty pane.
      await tester.sendKey(LogicalKey.keyS);
      await tester.sendTab();
      await tester.sendKey(LogicalKey.digit1);
      await _flush(tester);

      if (!tester.terminalState.containsText('now:')) {
        throw StateError('clock plugin was not attached to the pane');
      }
      if (!tester.terminalState.containsText('tilingslots')) {
        throw StateError('header pane lost after attach');
      }
      if (ws.pluginForSlot(controller.focus.current ?? '')?.id != 'clock') {
        throw StateError('clock is not mapped to the focused pane');
      }
      if (ws.available.map((p) => p.id).contains('clock')) {
        throw StateError('attached clock still listed as available');
      }
    });
  });

  test('palette swaps the occupying plugin of the focused pane', () async {
    await testNocterm('palette swaps the occupying plugin', (tester) async {
      final (ws, controller) = await _demo();
      await tester.pumpComponent(buildDemoApp(ws, controller));

      await tester.sendKey(LogicalKey.digit1); // clock into header's pane
      await _flush(tester);
      if (!tester.terminalState.containsText('now:')) {
        throw StateError('clock not attached');
      }
      await tester.sendKey(LogicalKey.digit2); // events over the same pane
      await _flush(tester);
      if (!tester.terminalState.containsText('workspace ready')) {
        throw StateError('event log did not replace the clock');
      }
      if (tester.terminalState.containsText('now:')) {
        throw StateError('clock pane was not vacated');
      }
    });
  });

  test('digit3 attaches the system graph pane', () async {
    await testNocterm('digit3 attaches the system graph pane', (tester) async {
      final (ws, controller) = await _demo();
      await tester.pumpComponent(buildDemoApp(ws, controller));

      await tester.sendKey(LogicalKey.keyS);
      await _flush(tester);
      await tester.sendKey(LogicalKey.digit3);
      await _flush(tester);

      // Gauges (block glyphs) prove the ring-buffer data path rendered.
      final rendered = tester.terminalState.renderToString(showBorders: false);
      if (!rendered.contains('█') &&
          !rendered.contains('░') &&
          !rendered.contains('▏')) {
        throw StateError('system graph gauges not rendered');
      }
      if (!ws.isEnabled('sys')) {
        throw StateError('sys plugin not enabled');
      }
    });
  });

  test('n spawns another clock instance (multi-instance)', () async {
    await testNocterm('n spawns another clock instance', (tester) async {
      final (ws, controller) = await _demo();
      await tester.pumpComponent(buildDemoApp(ws, controller));

      await tester.sendKey(LogicalKey.keyN);
      await _flush(tester);
      await tester.sendKey(LogicalKey.keyN);
      await _flush(tester);

      final clocks = ws.pluginManager.plugins
          .where((p) => p.id.startsWith('clock'))
          .toList();
      if (clocks.length != 2) {
        throw StateError('expected 2 spawned clocks, got ${clocks.length}');
      }
      if (_paneCount(controller) != 3) {
        throw StateError('spawned instances did not claim their own panes');
      }
    });
  });

  test('R swaps the focused plugin implementation live', () async {
    await testNocterm('R swaps the focused plugin implementation live',
        (tester) async {
      final (ws, controller) = await _demo();
      await tester.pumpComponent(buildDemoApp(ws, controller));

      await tester.sendKey(LogicalKey.digit1); // clock into the header pane
      await _flush(tester);
      if (!tester.terminalState.containsText('[v1]')) {
        throw StateError('clock v1 not rendered');
      }

      await tester.sendKey(LogicalKey.keyR);
      await _flush(tester);
      if (!tester.terminalState.containsText('[v2]')) {
        throw StateError('replacement implementation not rendered');
      }
      if (tester.terminalState.containsText('[v1]')) {
        throw StateError('old implementation still rendered');
      }
      // The workspace kept the plugin enabled and the pane intact.
      if (!ws.isEnabled('clock')) {
        throw StateError('plugin lost enabled state after replace');
      }
      if (ws.pluginForSlot(controller.focus.current ?? '')?.id != 'clock') {
        throw StateError('pane assignment lost after replace');
      }
      if (!ws.timeline.map((e) => e.type).contains('replace')) {
        throw StateError('replace not recorded in history');
      }
    });
  });

  test('u/r undo and redo keyboard shortcuts', () async {
    await testNocterm('u/r undo and redo keyboard shortcuts', (tester) async {
      final (ws, controller) = await _demo();
      await tester.pumpComponent(buildDemoApp(ws, controller));

      await tester.sendKey(LogicalKey.keyS);
      await _flush(tester);
      if (_paneCount(controller) != 2) {
        throw StateError('split did not add a pane');
      }

      await tester.sendKey(LogicalKey.keyU);
      await _flush(tester);
      if (_paneCount(controller) != 1) {
        throw StateError('undo did not restore the single pane');
      }

      await tester.sendKey(LogicalKey.keyY);
      await _flush(tester);
      if (_paneCount(controller) != 2) {
        throw StateError('redo did not re-apply the split');
      }
    });
  });

  test('closing a pane keeps the workspace registry consistent', () async {
    await testNocterm('closing a pane keeps the workspace registry consistent',
        (tester) async {
      final (ws, controller) = await _demo();
      await tester.pumpComponent(buildDemoApp(ws, controller));

      await tester.sendKey(LogicalKey.keyS);
      await _flush(tester);
      await tester.sendKey(LogicalKey.digit1);
      await _flush(tester);
      final panesBefore = _paneCount(controller);

      await tester.sendKey(LogicalKey.keyX); // close the clock pane
      await _flush(tester);
      if (_paneCount(controller) >= panesBefore) {
        throw StateError('close did not remove the pane');
      }
      if (ws.pluginForSlot(controller.focus.current ?? '') != null &&
          ws.available.isEmpty) {
        throw StateError('closed plugin did not return to the palette');
      }
      if (!ws.available.any((p) => p.id == 'clock')) {
        throw StateError('closed plugin did not return to the palette');
      }
    });
  });
}
