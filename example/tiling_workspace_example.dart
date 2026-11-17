import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';

/// Pre-launch `stty -g` snapshot, replayed on exit.
///
/// Why: nocterm puts the terminal into raw mode (`stdin.echoMode = false`),
/// and on shutdown its restore runs *after* the stdin subscription is
/// cancelled — the descriptor is then broken (EBADF), the restore throws
/// internally and is swallowed, leaving the shell without echo and with chopped
/// input lines. Replaying the snapshot through `stty` on `/dev/tty` restores the
/// exact pre-launch state.
String? _terminalSnapshot;

Future<void> _snapshotTerminal() async {
  if (Platform.isWindows) return;
  try {
    final result = await Process.run('stty', ['-g']);
    if (result.exitCode == 0) {
      _terminalSnapshot = (result.stdout as String).trim();
    }
  } catch (_) {}
}

/// Synchronous terminal restore for exit paths where the async version cannot
/// finish before the process is torn down (nocterm's `shutdownApp()` calls
/// `exit()` after flushing stdout).
void _restoreTerminalSync() {
  try {
    if (stdin.hasTerminal) {
      try {
        stdin.echoMode = true;
      } catch (_) {}
      try {
        stdin.lineMode = true;
      } catch (_) {}
    }
  } catch (_) {}
  final snapshot = _terminalSnapshot;
  if (snapshot == null || Platform.isWindows) return;
  final flag = Platform.isMacOS ? '-f' : '-F';
  try {
    Process.runSync('stty', [flag, '/dev/tty', snapshot]);
  } catch (_) {}
}

Future<void> _restoreTerminal() async {
  try {
    if (stdin.hasTerminal) {
      try {
        stdin.echoMode = true;
      } catch (_) {}
      try {
        stdin.lineMode = true;
      } catch (_) {}
    }
  } catch (_) {}
  final snapshot = _terminalSnapshot;
  if (snapshot == null || Platform.isWindows) return;
  // Linux wants -F, macOS -f for the device file.
  final flag = Platform.isMacOS ? '-f' : '-F';
  try {
    // Replay on a fresh /dev/tty handle: the stdin descriptor is dead by now.
    await Process.run('stty', [flag, '/dev/tty', snapshot]);
  } catch (_) {}
}

/// A service shared between demo plugins.
class WorkspaceInfo {
  const WorkspaceInfo({required this.title});
  final String title;
}

extension _ServiceLookup on ServiceContainer {
  T? tryResolve<T>() => contains<T>() ? resolve<T>() : null;
}

Component _pane(Component child,
    {Color background = Colors.black, BoxBorder? border}) {
  return Container(
    decoration: BoxDecoration(color: background, border: border),
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: child,
  );
}

/// Title pane with the keyboard cheat sheet. Always the first pane.
class HeaderPlugin extends SlotPlugin {
  const HeaderPlugin({this.slot = 'header'});

  final String slot;

  @override
  String get id => 'header';

  @override
  String get name => 'Header';

  @override
  String get version => '1.0.0';

  @override
  String get slotId => slot;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    container.registerSingleton<WorkspaceInfo>(
        const WorkspaceInfo(title: 'tilingslots'));
  }

  @override
  Component build(SlotContext context) {
    final info = context.services.tryResolve<WorkspaceInfo>();
    return _pane(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${info?.title ?? 'tilingslots'}',
              style: TextStyle(color: Colors.yellow)),
          const Text('LEGO workspace'),
          const Text(''),
          const Text('S/V   split'),
          const Text('Z     zoom pane'),
          const Text('↑/↓   resize / X close'),
          const Text('Tab   focus · тап мышью'),
        ],
      ),
      background: const Color.fromRGB(20, 20, 32),
      border: BoxBorder.all(color: Colors.cyan),
    );
  }
}

/// Ticking clock pane. Parametric so it can be spawned many times.
class ClockPlugin extends SlotPlugin {
  ClockPlugin({required this.id, required this.slot, this.generation = 1});

  @override
  final String id;

  final String slot;

  /// Implementation generation, bumped by live `replace` swaps.
  final int generation;
  late final ClockTicker ticker;

  @override
  String get name => 'Clock';

  @override
  String get version => '1.0.0';

  @override
  String get slotId => slot;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    ticker = ClockTicker();
    // Scoped effect: the timer dies with the plugin, no manual teardown.
    scope.every(const Duration(seconds: 1), (_) => ticker.tick());
  }

  @override
  Component build(SlotContext context) {
    return _pane(
      ListenableBuilder(
        listenable: ticker,
        builder: (context, _) => Center(
          child: Text('now: ${ticker.now}  [v$generation]',
              style: TextStyle(color: Colors.green)),
        ),
      ),
      background: const Color.fromRGB(16, 24, 16),
      border: BoxBorder.all(color: Colors.green),
    );
  }
}

class ClockTicker extends ChangeNotifier {
  DateTime _value = DateTime.now();

  DateTime get now => _value;

  void tick() {
    _value = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}

/// Live view of kernel traffic: proves the plugin kernel and event bus work.
class EventLogPlugin extends SlotPlugin {
  EventLogPlugin({this.slot = 'events'});

  final String slot;
  final EventLog log = EventLog();

  @override
  String get id => 'events';

  @override
  String get name => 'Event log';

  @override
  String get version => '1.0.0';

  @override
  String get slotId => slot;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    // Scoped effects: subscriptions die with the plugin.
    scope.on<PluginEnabledEvent>(
        bus, (e) => log.add('plugin on    ${e.pluginId}'));
    scope.on<PluginDisabledEvent>(
        bus, (e) => log.add('plugin off   ${e.pluginId}'));
    scope.on<PluginReplacedEvent>(
        bus, (e) => log.add('plugin SWAP  ${e.pluginId}'));
    scope.on<PluginErrorEvent>(
        bus, (e) => log.add('plugin ERR   ${e.pluginId}'));
    scope.on<LayoutChangedEvent>(
        bus,
        (e) => log.add(
            'layout ${e.operation.padRight(7)} ${e.slotId ?? ''}'.trimRight()));
    log.add('workspace ready');
  }

  @override
  Component build(SlotContext context) {
    return _pane(
      ListenableBuilder(
        listenable: log,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('event log (${log.lines.length})',
                style: TextStyle(color: Colors.magenta)),
            ...log.lines.map((line) => Text(line)),
          ],
        ),
      ),
      background: const Color.fromRGB(24, 16, 24),
      border: BoxBorder.all(color: Colors.magenta),
    );
  }
}

/// Append-only log of recent kernel events.
class EventLog extends ChangeNotifier {
  final List<String> lines = [];

  void add(String line) {
    lines.add(line);
    if (lines.length > 6) lines.removeAt(0);
    notifyListeners();
  }
}

/// Workspace history: the time-machine timeline (checkpoints + undo/redo).
class HistoryPlugin extends SlotPlugin {
  HistoryPlugin({this.slot = 'history'});

  final String slot;
  final EventLog lines = EventLog();

  @override
  String get id => 'history';

  @override
  String get name => 'History';

  @override
  String get version => '1.0.0';

  @override
  String get slotId => slot;

  @override
  Component build(SlotContext context) {
    return _pane(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('workspace history', style: TextStyle(color: Colors.yellow)),
          const Text(''),
          const Text('u  undo       y  redo'),
          const Text('c  checkpoint'),
          const Text('R  swap plugin impl'),
          const Text(''),
        ],
      ),
      background: const Color.fromRGB(24, 24, 16),
      border: BoxBorder.all(color: Colors.yellow),
    );
  }
}

/// Plugin blueprints the palette can attach or spawn, with their hotkeys.
/// Digits map to palette entries in order; the status bar shows the same.
const _paletteEntries = <(String key, String label, String pluginId)>[
  ('digit1', 'clock', 'clock'),
  ('digit2', 'events', 'events'),
  ('digit3', 'sys', 'sys'),
];

Future<void> _attachFromPalette(
    SlotWorkspace ws, TilingController c, int paletteIndex) async {
  if (paletteIndex < 0 || paletteIndex >= _paletteEntries.length) return;
  final pluginId = _paletteEntries[paletteIndex].$3;
  if (!ws.pluginManager.plugins.any((p) => p.id == pluginId)) {
    ws.register(_blueprint(pluginId));
  }
  final focused = c.focus.current;
  if (focused == null) return;
  final occupant = ws.pluginForSlot(focused);
  if (occupant != null) {
    if (occupant.id == pluginId) return; // already shown in the focused pane
    // Swap: vacate the focused pane but keep it in the layout.
    await ws.disable(occupant.id, keepPane: true);
  }
  await ws.enable(pluginId, into: focused);
  c.updateLayout(ws.layout);
}

Future<void> _spawnClock(SlotWorkspace ws, TilingController c) async {
  await ws.spawn((slotId) => ClockPlugin(id: 'clock-$slotId', slot: slotId));
  c.updateLayout(ws.layout);
}

/// Swaps the focused pane's plugin for a new implementation of the same
/// contract (clock v1 → clock v2), live, without touching the pane.
Future<void> _replaceFocusedPlugin(SlotWorkspace ws, TilingController c) async {
  final focused = c.focus.current;
  if (focused == null) return;
  final plugin = ws.pluginForSlot(focused);
  if (plugin is! ClockPlugin) return;
  final next = ClockPlugin(
    id: plugin.id,
    slot: plugin.slot,
    generation: plugin.generation + 1,
  );
  await ws.replace(plugin.id, next);
  c.updateLayout(ws.layout);
}

SlotPlugin _blueprint(String id) {
  switch (id) {
    case 'clock':
      return ClockPlugin(id: 'clock', slot: 'clock');
    case 'events':
      return EventLogPlugin();
    case 'sys':
      return SystemGraphPlugin();
    default:
      throw StateError('Unknown blueprint: $id');
  }
}

/// One sample of system metrics (pure data; the kernel never sees doubles in
/// lists — the service owns typed-data ring buffers).
typedef SystemSample = ({double cpu, double mem, double net});

/// Deterministic stand-in for a real /proc reader; smooth waves make the demo
/// testable and the panes visually alive.
int _tickCount = 0;
SystemSample _waveSampler() {
  final t = _tickCount++;
  final cpu = 0.5 + 0.4 * _sin(t);
  final mem = 0.6 + 0.2 * _sin(t * 2);
  final net = 0.3 + 0.3 * _sin(t * 3);
  return (cpu: cpu, mem: mem, net: net);
}

double _sin(int step) => _sinTable[step % _sinTable.length];
const _sinTable = [0.0, 0.6, 0.95, 0.6, 0.0, -0.6, -0.95, -0.6];

/// Ring-buffer backed metrics store; one service, three time series, zero
/// per-tick allocations beyond the sample itself.
class SystemMetricsService extends ChangeNotifier {
  final Float32RingBuffer cpu = Float32RingBuffer(60);
  final Float32RingBuffer mem = Float32RingBuffer(60);
  final Float32RingBuffer net = Float32RingBuffer(60);

  void sample(SystemSample sample) {
    cpu.write(sample.cpu);
    mem.write(sample.mem);
    net.write(sample.net);
    notifyListeners();
  }
}

/// Live system graph pane: gauges + braille sparklines rendered from ring
/// buffers. Proves the data-kernel path end to end (a plugin-shaped consumer).
class SystemGraphPlugin extends SlotPlugin {
  SystemGraphPlugin(
      {this.id = 'sys', this.slot = 'sys', SystemSample Function()? sampler})
      : _sampler = sampler ?? _waveSampler;

  final String id;
  final String slot;

  final SystemSample Function() _sampler;
  final Float32List _scratch = Float32List(60);

  @override
  String get name => 'System graph';

  @override
  String get version => '1.0.0';

  @override
  String get slotId => slot;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    final metrics = SystemMetricsService();
    container.registerSingleton<SystemMetricsService>(metrics);
    scope.own(metrics, (m) => m.dispose());
    scope.every(const Duration(milliseconds: 500), (_) {
      metrics.sample(_sampler());
    });
  }

  @override
  Component build(SlotContext context) {
    final metrics = context.services.resolve<SystemMetricsService>();
    return _pane(
      ListenableBuilder(
        listenable: metrics,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('cpu ${barGauge(metrics.cpu.last ?? 0, 20)}',
                style: TextStyle(color: Colors.green)),
            Text('mem ${barGauge(metrics.mem.last ?? 0, 20)}',
                style: TextStyle(color: Colors.yellow)),
            Text('net ${barGauge(metrics.net.last ?? 0, 20)}',
                style: TextStyle(color: Colors.cyan)),
            const Text(''),
            Text(sparkline(metrics.cpu, width: 20, scratch: _scratch),
                style: TextStyle(color: Colors.green)),
            Text(sparkline(metrics.mem, width: 20, scratch: _scratch),
                style: TextStyle(color: Colors.yellow)),
            Text(sparkline(metrics.net, width: 20, scratch: _scratch),
                style: TextStyle(color: Colors.cyan)),
          ],
        ),
      ),
      background: const Color.fromRGB(12, 16, 12),
      border: BoxBorder.all(color: Colors.green),
    );
  }
}

/// Wires palette hotkeys to the tiling widget.
bool _handleDemoKey(SlotWorkspace ws, TilingController c, KeyboardEvent event) {
  final name = event.logicalKey.debugName;
  final index = _paletteEntries.indexWhere((entry) => entry.$1 == name);
  if (index >= 0) {
    _attachFromPalette(ws, c, index);
    return true;
  }
  switch (name) {
    case 'keyN':
      _spawnClock(ws, c);
      return true;
    case 'keyU':
      // Sync the controller after the queued undo has been applied.
      ws.undo().then((_) => c.updateLayout(ws.layout));
      return true;
    case 'keyY':
      ws.redo().then((_) => c.updateLayout(ws.layout));
      return true;
    case 'keyR':
      _replaceFocusedPlugin(ws, c);
      return true;
    case 'keyC':
      ws.checkpoint();
      return true;
    case 'keyQ':
      // Restore before shutdownApp(): it exits the isolate, so the `finally`
      // in main() never runs.
      _restoreTerminalSync();
      shutdownApp();
      return true;
    default:
      return false;
  }
}

String _statusText(SlotWorkspace ws, TilingController c) {
  final palette = _paletteEntries.map((entry) {
    final active = ws.pluginForSlot(c.focus.current ?? '')?.id == entry.$3;
    return '${entry.$2}${active ? '*' : ''}';
  }).join(' ');
  final history = ws.canUndo ? 'u undo' : 'u —';
  final redo = ws.canRedo ? 'y redo' : 'y —';
  final zoom = LayoutEngine.computeRects(c.layout, 1, 1)
          .keys
          .any((s) => (c.layout is SplitNode) && _isZoomedNode(c.layout, s))
      ? 'z unzoom'
      : 'z zoom';
  return ' focused: ${c.focus.current ?? '-'} | '
      'panes: ${LayoutEngine.computeRects(c.layout, 1, 1).keys.length} | '
      'palette: $palette | $history · $redo · R swap · $zoom · n=+clock q=quit ';
}

/// The full demo application: tiling area plus a status bar.
Component buildDemoApp(SlotWorkspace workspace, TilingController controller) {
  return Container(
    color: Colors.black,
    child: Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => NoctermTilingWidget(
              controller: controller,
              slotBuilder: (slotId) =>
                  _slotBuilder(workspace, controller, slotId),
              slotTitle: (slotId) => _paneTitle(workspace, slotId),
              cachePanes: true,
              slotVersion: (slotId) => workspace.timeline.length,
              onUnhandledKeyEvent: (event) =>
                  _handleDemoKey(workspace, controller, event),
              // Controller split/close mutates its own tree: keep the
              // workspace registry in sync (plugins whose pane vanished
              // return to the palette).
              onAction: (_) {
                workspace.updateLayoutFrom(controller.layout);
              },
            ),
          ),
        ),
        Container(
          color: const Color.fromRGB(32, 32, 40),
          child: ListenableBuilder(
            listenable: controller.focus,
            builder: (context, _) => Text(
              _statusText(workspace, controller),
              style: TextStyle(color: Colors.cyan),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Pane chrome: plugin name + version, or the slot id for an empty pane.
String _paneTitle(SlotWorkspace workspace, String slotId) {
  final plugin = workspace.pluginForSlot(slotId);
  if (plugin == null) return '$slotId — empty';
  return '${plugin.name} ${plugin.version}';
}

Component _slotBuilder(
    SlotWorkspace workspace, TilingController controller, String slotId) {
  final plugin = workspace.pluginForSlot(slotId);
  if (plugin == null) {
    // An empty pane: fill it from the palette with 1/2.
    return _pane(
      Center(
          child: Text(
              'empty pane\n$slotId\n\n1 clock · 2 events\nn spawn · u/r undo/redo')),
      background: Colors.black,
      border: BoxBorder.all(color: Colors.gray),
    );
  }
  return workspace.buildSlot(slotId,
      isFocused: controller.focus.current == slotId);
}

Future<void> main(List<String> args) async {
  final workspacePath = args.isEmpty ? 'workspace.json' : args.first;

  await _snapshotTerminal();
  // Restore the terminal on abnormal exits too (Ctrl+C, kill).
  final sigint =
      ProcessSignal.sigint.watch().listen((_) => _restoreTerminalSync());
  final sigterm =
      ProcessSignal.sigterm.watch().listen((_) => _restoreTerminalSync());

  final workspace = SlotWorkspace()..register(const HeaderPlugin());
  final controller = TilingController(
    initialLayout: workspace.layout,
    bus: workspace.bus,
    removePluginPanes: false,
  );

  final file = File(workspacePath);
  if (file.existsSync()) {
    try {
      await workspace
          .restore(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } on Object catch (error) {
      // A bad document must not crash startup: fall back to a fresh workspace.
      // ignore: avoid_print
      print(
          'Could not restore $workspacePath ($error) — starting with a fresh workspace.');
      await workspace.enable('header');
    }
  } else {
    await workspace.enable('header');
  }
  controller.updateLayout(workspace.layout);

  try {
    await runApp(buildDemoApp(workspace, controller));
  } finally {
    // nocterm's own restore runs after the stdin subscription is cancelled and
    // silently fails (EBADF), so replay the pre-launch terminal state.
    await _restoreTerminal();
    await sigint.cancel();
    await sigterm.cancel();
  }

  // Persist the plugin set (and hence the plugin-driven layout) on exit.
  file.writeAsStringSync(jsonEncode(workspace.toJson()));
}

bool _isZoomedNode(LayoutNode node, String slotId) {
  if (node is SlotNode) return node.slotId == slotId && node.zoomed;
  if (node is SplitNode) {
    return node.children.any((child) => _isZoomedNode(child, slotId));
  }
  return false;
}
