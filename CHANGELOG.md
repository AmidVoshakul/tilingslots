# Changelog

## 0.1.0

First full MVP release. The kernel, layout engine, and nocterm adapter are
feature-complete; the API is small enough to keep stable and will only gain
additive changes until 1.0.

### Added

- **Core (nocterm-free)**
  - `Plugin` contract with `setup`/`teardown` (default no-ops), `slotId` hook,
    and `providedServices`/`consumedServices` metadata.
  - `PluginScope`: cordis-style effect scope. Plugins register subscriptions
    (`scope.on`), timers (`scope.every`), resources (`scope.own`/`defer`) in
    `setup`; all are disposed in reverse order on disable — `teardown` only
    handles what cannot be expressed as an effect.
  - `PluginManager`: register, enable, disable, unregister, lifecycle event
    stream, and automatic rollback of container registrations when a plugin's
    `setup` throws. Rejects operations after `dispose()` instead of corrupting
    plugin state.
  - `ServiceContainer`: singleton registrations keyed by type with optional
    name, disposal hooks, snapshot/restore, and disposal of overwritten or
    snapshot-dropped entries.
  - `EventBus`: typed publish/subscribe with subscriber error isolation.
  - `TailEvent` base class and plugin lifecycle/error events.
- **Layout (nocterm-free)**
  - `SplitNode`/`SlotNode` immutable slot tree.
  - `LayoutEngine`: split, remove, resize, exact pane-rect computation with
    largest-remainder distribution, ratio normalization, depth guards, and path
    validation.
  - `LayoutSerializer`: versioned (v1) JSON documents, strict validation mode,
    unknown-slot checks.
- **Nocterm adapter**
  - `NoctermTilingWidget`, `TilingController` (focus cycling, split, resize,
    close via a configurable keymap) with unique auto-generated slot ids.
  - `SlotWorkspace`: plugin registry, workspace layout composition,
    `buildSlot` with per-slot error isolation, `pluginForSlot` lookup, and JSON
    save/restore including dispose of workspace-owned services.
  - **Runtime assembly** (the LEGO layer):
    - `enable(pluginId, {into})` — activate a plugin into an existing empty
      pane instead of always appending a new one.
    - `attach(pluginId, slotId)` — move an enabled plugin to another pane.
    - `disable(pluginId, {keepPane})` — vacate a pane while keeping it in the
      layout for immediate reuse.
    - `spawn(factory, {into})` — multi-instance plugins: register and enable a
      fresh instance of a blueprint with a generated id.
    - `available` — the palette: registered slot plugins that are disabled.
    - `updateLayoutFrom(node)` — adopt a controller-mutated layout; plugins
      whose pane vanished return to the palette.
  - **Time machine**: every mutation is recorded as a workspace document
    snapshot (`timeline`), with `undo()`, `redo()`, named `checkpoint()` /
    `restoreCheckpoint()`, and a bounded log (`maxLogEntries`);
    `WorkspaceEventEntry` and `WorkspaceCheckpoint` describe recorded entries
    and checkpoints.
  - **Hot-swap**: `SlotWorkspace.replace(id, newPlugin)` swaps an implementation
    in place — same pane, same enabled state, timeline entry, and a
    `PluginReplacedEvent` (not a disable). Failed replacements restore the
    previous implementation and the container snapshot.
  - `TilingController({removePluginPanes})` — opt out of automatic pane removal
    when a workspace owns pane lifecycle.
  - `NoctermTilingWidget({onUnhandledKeyEvent, onAction})` — forward
    unbound keys (e.g. a plugin palette) and observe executed tiling actions.
  - `SlotPlugin`/`SlotContext`, `FocusManager`, `KeyboardBindings`/`Keymap`.
- **Examples**
  - `example/tiling_workspace_example.dart`: interactive workspace — three slot
    plugins (header with keymap help, clock, live event log), keyboard-driven
    splitting/resizing/closing with a status bar, opaque pane backgrounds, and
    workspace persistence. Hotkeys: `u` undo, `y` redo, `c` checkpoint, `R` swap
    the focused plugin implementation live. Covered by
    `test/adapter_nocterm/demo_smoke_test.dart` (rendering, keyboard
    interaction, and re-layout at 40x16 and 120x40 terminal sizes).
  - `doc/PLUGIN_AUTHORING.md`.
- **Packaging**
  - `tilingslots_core.dart` entrypoint with zero nocterm imports.
  - 290 passing tests; `dart analyze` and `dart doc` clean; CI enforces the
    coverage gate (core+layout >= 80%).

### Added (continued)

- Layout presets: `WorkspacePresets` (`twoColumns`, `threeColumns`,
  `mainAndSidebar`, `grid2x2`) and `SlotWorkspace.applyPreset`.
- Plugin manifests: `PluginManifest` + `PluginManifestLoader`.
- Command palette: `CommandPalette` with filtering and execution.
- Layout migration: `LayoutSerializer.migrate` for legacy/v1 documents.
- Crash-isolation tests for active slots after `attach`/`into`.

### Changed

- `Plugin.setup`/`Plugin.teardown` now receive a `PluginScope`:
  `setup(container, bus, scope)`. Existing no-op defaults remain, so simple
  plugins keep compiling.
- `ServiceContainer.registerFactory` no longer accepts a `dispose` callback:
  the container does not own factory-produced instances, so the callback could
  never fire. Singleton dispose hooks remain.
- `LayoutEngine.split` clamps and normalizes the new ratio instead of storing
  raw values, and validates the path up front (`LayoutValidationException`).
- `LayoutEngine.resize` rejects malformed ratio vectors instead of raising a
  `RangeError`.
- `PluginManager.enable` publishes lifecycle events before marking the plugin
  enabled, so a failed event delivery cannot leave a "ghost" enabled plugin.
- `NoctermTilingWidget` renders exactly `min(children, ratios)` panes, matching
  `LayoutEngine.computeRects`, and uses exact pane rects (from
  `LayoutEngine.computeRects`) with a `SizedBox` per pane when the terminal
  size is known — panes below 3 cells are skipped instead of crashing layout.
- **Graphics kernels (pure Dart):** `Float32RingBuffer` — fixed-capacity ring
  buffer on a single `Float32List` (zero steady-state allocations), `sparkline`
  (braille, two samples per cell) and `barGauge` (block glyphs with eighth
  fractions); all accept a reusable scratch buffer. Used by the demo's system
  graph pane.
- **Per-plugin zone isolation:** each plugin runs its setup, teardown and scoped
  effects inside a forked zone; uncaught async errors are contained, the
  plugin is disabled, its scope disposed, and a `PluginCrashedEvent` is
  published. The workspace releases the pane and the plugin returns to the
  palette. Host and neighbours keep running.
- **Per-pane invalidation:** `NoctermTilingWidget(cachePanes: true,
  slotVersion: ...)` caches pane content and rebuilds it only when that pane's
  inputs change — focus, focus-cycling and boundary drags repaint borders
  without rebuilding any pane content, and each pane's focus border is driven
  by its own listener. Panes whose slot disappears (or whose version changes)
  invalidate incrementally; the default behaviour is unchanged.
- `SlotWorkspace.enable` gives a pane appended to a split root equal weight
  with its siblings instead of half the workspace.
- `SlotNode` gained a `zoomed` flag: a zoomed pane takes 95% of the area and its
  siblings collapse out of view; zoom is part of the layout document (so it is
  saved, restored, and undone with everything else) and exposed as
  `TilingAction.zoom` / `z`.
- Mouse support in `NoctermTilingWidget`: clicking a pane focuses it, dragging a
  pane edge that faces a sibling resizes that boundary (`resizeBoundary`), and
  panes are sized from the real layout constraints (`LayoutBuilder`) instead of
  the terminal size, so they never overlap sibling UI. `slotTitle` renders a
  per-pane header for hosts that provide one.
- `PluginManager.dispose()` is now async and runs `teardown` for still-enabled
  plugins before closing the lifecycle stream; `SlotWorkspace.dispose()`
  delegates to it and additionally exposes `disposeAsync()`.
- ServiceContainer dependents tracking and overwrite protection.
- EventBus modes: `serial`/`bail`/`waterfall` + `prepend`.
- Plugin config schema validation (`PluginConfigSchema`).
- Major fixes: timeline cursor restore, dispose safety, re-entrancy guard.
