import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';

import '../../example/tiling_workspace_example.dart';

/// Shared setup for the demo smoke tests: a palette-driven workspace
/// (header only) plus its controller, mirroring `main()`.
Future<(SlotWorkspace, TilingController)> demoWorkspace() async {
  final ws = SlotWorkspace()..register(const HeaderPlugin());
  final controller = TilingController(
    initialLayout: ws.layout,
    bus: ws.bus,
    removePluginPanes: false,
  );
  await ws.enable('header');
  controller.updateLayout(ws.layout);
  return (ws, controller);
}

/// Waits for fire-and-forget key handlers and flushes a rendered frame
/// (testNocterm only paints on pump).
Future<void> flushFrames(NoctermTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await tester.pump();
}

int paneCount(TilingController controller) =>
    LayoutEngine.computeRects(controller.layout, 1, 1).keys.length;
