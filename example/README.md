# tilingslots examples

## Interactive tiling workspace

`example/tiling_workspace_example.dart` is the constructor demo — it shows the
full runtime-assembly loop:

- `S`/`V` split the focused pane (creating empty panes),
- `1`/`2` attach the palette plugins (clock, event log) into the focused pane —
  an occupied pane is swapped,
- `n` spawns another clock instance (multi-instance plugins),
- `↑`/`↓` resize the boundary, `X` closes the focused pane (its plugin returns
  to the palette), `q` quits and saves the workspace;
- a status bar shows the focused slot, pane count and palette state;
- the event-log pane renders kernel traffic live (plugin enable/disable,
  layout split/remove) through the event bus.

Persistence: the workspace document is saved on exit and restored on start.
A corrupt document falls back to a fresh workspace instead of crashing.

Run it in a real terminal (resizing reflows panes proportionally):

```sh
dart run example/tiling_workspace_example.dart [workspace.json]
```

The demo's rendering, keyboard interaction, palette assembly, and spawn
behavior are asserted in `test/adapter_nocterm/demo_smoke_test.dart`;
re-layout at 40x16/120x40 is covered in `render_guards_test.dart`.

## Plugin template

`example/plugin_template.dart` is the smallest possible `SlotPlugin` — copy it as a starting point.
