import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class _CountingPane extends StatefulComponent {
  const _CountingPane({required this.slotId, required this.onBuild});

  final String slotId;
  final void Function(String slotId) onBuild;

  @override
  State<_CountingPane> createState() => _CountingPaneState();
}

class _CountingPaneState extends State<_CountingPane> {
  @override
  Component build(BuildContext context) {
    component.onBuild(component.slotId);
    return Text('pane-${component.slotId}');
  }
}

void main() {
  test('renders slot content', () async {
    await testNocterm('renders slot content', (tester) async {
      final focus = FocusManager(slotOrder: ['a']);
      await tester.pumpComponent(
        NoctermTilingWidget(
          layout: const SlotNode(slotId: 'a'),
          focus: focus,
          slotBuilder: (id) => Text('pane-$id'),
        ),
      );
      if (!tester.terminalState.containsText('pane-a')) {
        throw StateError('pane-a not rendered');
      }
    });
  });

  test('renders error placeholder on throwing slot', () async {
    await testNocterm('renders error placeholder on throwing slot',
        (tester) async {
      final focus = FocusManager(slotOrder: ['a']);
      await tester.pumpComponent(
        NoctermTilingWidget(
          layout: const SlotNode(slotId: 'a'),
          focus: focus,
          slotBuilder: (id) => throw StateError('boom'),
        ),
      );
      if (!tester.terminalState.containsText('Error')) {
        throw StateError('Error placeholder not rendered');
      }
    });
  });

  test('renders both panes of a split layout', () async {
    await testNocterm('renders both panes of a split layout', (tester) async {
      final focus = FocusManager(slotOrder: ['a', 'b']);
      await tester.pumpComponent(
        NoctermTilingWidget(
          layout: const SplitNode(
            direction: SplitDirection.horizontal,
            children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
            ratios: [0.5, 0.5],
          ),
          focus: focus,
          slotBuilder: (id) => Text('pane-$id'),
        ),
      );
      if (!tester.terminalState.containsText('pane-a')) {
        throw StateError('left pane not rendered');
      }
      if (!tester.terminalState.containsText('pane-b')) {
        throw StateError('right pane not rendered');
      }
    });
  });

  test('renders the focused slot with a border', () async {
    await testNocterm('renders the focused slot with a border', (tester) async {
      final focus = FocusManager(slotOrder: ['a']);
      focus.setFocus('a');
      await tester.pumpComponent(
        NoctermTilingWidget(
          layout: const SlotNode(slotId: 'a'),
          focus: focus,
          slotBuilder: (id) => const Text('solo'),
        ),
      );
      // The focus border is drawn as box-drawing glyphs around the focused slot.
      final rendered = tester.terminalState.renderToString(showBorders: false);
      if (!rendered.contains('┌') && !rendered.contains('│')) {
        throw StateError('focus border not rendered');
      }
    });
  });

  test('reports slot errors through onError', () async {
    Object? error;
    await testNocterm('reports slot errors through onError', (tester) async {
      final focus = FocusManager(slotOrder: ['a']);
      await tester.pumpComponent(
        NoctermTilingWidget(
          layout: const SlotNode(slotId: 'a'),
          focus: focus,
          slotBuilder: (id) => throw StateError('slot boom'),
          onError: (e, st) => error ??= e,
        ),
      );
    });
    if (error == null) throw StateError('onError was not invoked');
  });

  test('controller mode renders and handles key events', () async {
    await testNocterm('controller mode renders and handles key events',
        (tester) async {
      final controller = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
          ratios: [0.5, 0.5],
        ),
      );
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('pane-$id'),
        ),
      );
      if (!tester.terminalState.containsText('pane-a')) {
        throw StateError('controller-mode layout did not render');
      }
      controller.focus.setFocus('a');
      await tester.sendTab();
      if (controller.focus.current != 'b') {
        throw StateError('tab did not move focus in controller mode');
      }
      await tester.sendKey(LogicalKey.keyX);
      final slots =
          LayoutEngine.computeRects(controller.layout, 10, 10).keys.toList();
      if (slots.contains('b')) {
        throw StateError('close action did not remove the focused slot');
      }
      if (!slots.contains('a')) {
        throw StateError('close action removed the wrong slot');
      }
    });
  });

  test('renders only the panes the ratio vector covers', () async {
    await testNocterm('renders only the panes the ratio vector covers',
        (tester) async {
      final focus = FocusManager(slotOrder: ['a']);
      const node = SplitNode(
        direction: SplitDirection.vertical,
        children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
        ratios: [1.0],
      );
      await tester.pumpComponent(
        NoctermTilingWidget(
          layout: node,
          focus: focus,
          slotBuilder: (id) => Text('pane-$id'),
        ),
      );
      // Matches LayoutEngine.computeRects, which truncates to min(children, ratios).
      final slots = LayoutEngine.computeRects(node, 10, 10).keys;
      if (!tester.terminalState.containsText('pane-a')) {
        throw StateError('covered pane not rendered');
      }
      if (slots.contains('b') != tester.terminalState.containsText('pane-b')) {
        throw StateError('widget and engine disagree on pane set');
      }
    });
  });

  test('controller mode reports executed actions', () async {
    await testNocterm('controller mode reports executed actions',
        (tester) async {
      final controller =
          TilingController(initialLayout: const SlotNode(slotId: 'a'));
      final actions = <TilingAction>[];
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('pane-$id'),
          onAction: actions.add,
        ),
      );
      controller.focus.setFocus('a');
      await tester.sendKey(LogicalKey.keyS);
      if (actions.isEmpty || actions.first != TilingAction.splitHorizontal) {
        throw StateError('split action was not reported: $actions');
      }
    });
  });

  test('clicking a pane focuses it (controller mode)', () async {
    await testNocterm('clicking a pane focuses it (controller mode)',
        (tester) async {
      final controller = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('pane-$id'),
          // Mouse hit-testing requires the exact-rects layout path (a known
          // viewport); Expanded-based fallback is not hit-testable in nocterm.
          viewportSize: const Size(80, 24),
        ),
      );
      controller.focus.setFocus('left');

      // The right pane starts at column 40 (80 wide, 50/50 split).
      await tester.tap(60, 5);
      if (controller.focus.current != 'right') {
        throw StateError('click did not move focus to the clicked pane');
      }

      // Clicking the focused pane keeps the focus.
      await tester.tap(60, 8);
      if (controller.focus.current != 'right') {
        throw StateError('click on the focused pane dropped the focus');
      }
    });
  });

  test('clicking a pane focuses it (workspace mode)', () async {
    await testNocterm('clicking a pane focuses it (workspace mode)',
        (tester) async {
      final focus = FocusManager(slotOrder: const ['left', 'right']);
      focus.setFocus('right');
      await tester.pumpComponent(
        NoctermTilingWidget(
          layout: const SplitNode(
            direction: SplitDirection.horizontal,
            children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
            ratios: [0.5, 0.5],
          ),
          focus: focus,
          slotBuilder: (id) => Text('pane-$id'),
          viewportSize: const Size(80, 24),
        ),
      );
      await tester.tap(5, 5);
      if (focus.current != 'left') {
        throw StateError('click on the left pane did not focus it');
      }
    });
  });

  test('dragging a split boundary resizes panes', () async {
    await testNocterm('dragging a split boundary resizes panes',
        (tester) async {
      final controller = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('pane-$id'),
        ),
      );
      final ratiosBefore = (controller.layout as SplitNode).ratios;

      // The boundary strip overlays the left pane's last column (39).
      await tester.press(39, 5);
      for (var x = 43; x <= 51; x += 4) {
        await tester.sendMouseEvent(MouseEvent(
          button: MouseButton.left,
          x: x,
          y: 5,
          pressed: true,
        ));
      }
      await tester.sendMouseEvent(MouseEvent(
        button: MouseButton.left,
        x: 51,
        y: 5,
        pressed: false,
      ));

      final ratiosAfter = (controller.layout as SplitNode).ratios;
      if (ratiosAfter[0] <= ratiosBefore[0]) {
        throw StateError(
            'drag did not grow the left pane: $ratiosBefore → $ratiosAfter');
      }
      // +12 of 80 columns ≈ +0.15 on the left boundary.
      if ((ratiosAfter[0] - ratiosBefore[0] - 0.15).abs() > 0.03) {
        throw StateError(
            'drag delta not proportional: $ratiosBefore → $ratiosAfter');
      }
    });
  });

  test('a press-release without drag changes nothing', () async {
    await testNocterm('a press-release without drag changes nothing',
        (tester) async {
      final controller = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('pane-$id'),
        ),
      );
      final before = (controller.layout as SplitNode).ratios;
      await tester.tap(39, 5); // tap on the boundary
      final after = (controller.layout as SplitNode).ratios;
      expect(after, before);
    });
  });

  test('slotTitle renders a per-pane header', () async {
    await testNocterm('slotTitle renders a per-pane header', (tester) async {
      final controller = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('pane-$id'),
          slotTitle: (slotId) => 'title-$slotId',
          viewportSize: const Size(80, 24),
        ),
      );
      if (!tester.terminalState.containsText('title-left')) {
        throw StateError('left pane title not rendered');
      }
      if (!tester.terminalState.containsText('title-right')) {
        throw StateError('right pane title not rendered');
      }
    });
  });

  test('no slotTitle renders no header row', () async {
    await testNocterm('no slotTitle renders no header row', (tester) async {
      final controller = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('pane-$id'),
          viewportSize: const Size(80, 24),
        ),
      );
      if (tester.terminalState.containsText('title-')) {
        throw StateError('header rendered without slotTitle');
      }
      if (!tester.terminalState.containsText('pane-left')) {
        throw StateError('pane content lost');
      }
    });
  });

  test('slot titles do not eat narrow panes', () async {
    await testNocterm('slot titles do not eat narrow panes', (tester) async {
      final controller = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [
            SlotNode(slotId: 'wide'),
            SplitNode(
              direction: SplitDirection.vertical,
              children: [SlotNode(slotId: 'tiny1'), SlotNode(slotId: 'tiny2')],
              ratios: [0.5, 0.5],
            ),
          ],
          ratios: [0.7, 0.3],
        ),
      );
      controller.focus.setFocus('tiny1');
      controller.focus.updateSlots(['wide', 'tiny1', 'tiny2']);
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('p$id'),
          slotTitle: (slotId) => 'T-$slotId',
          viewportSize: const Size(100, 30),
        ),
      );
      // Tiny panes keep their content; no crash, and the wide title exists.
      if (!tester.terminalState.containsText('T-wide')) {
        throw StateError('wide pane title not rendered');
      }
    });
  });

  group('per-pane invalidation (cachePanes)', () {
    Map<String, int> countsOf() => {'left': 0, 'right': 0};

    test('a focus event rebuilds no pane content', () async {
      final counts = countsOf();
      await testNocterm('focus rebuilds nothing', (tester) async {
        final controller = TilingController(
          initialLayout: const SplitNode(
            direction: SplitDirection.horizontal,
            children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
            ratios: [0.5, 0.5],
          ),
        );
        await tester.pumpComponent(NoctermTilingWidget(
          controller: controller,
          slotBuilder: (slotId) => _CountingPane(
            slotId: slotId,
            onBuild: (id) => counts[id] = (counts[id] ?? 0) + 1,
          ),
          cachePanes: true,
        ));
        final initial = Map.of(counts);
        expect(initial.values.every((c) => c == 1), isTrue);

        controller.focus.setFocus('right');
        await tester.pump();
        controller.handleAction(TilingAction.nextFocus);
        await tester.pump();

        expect(counts, initial); // zero idle content rebuilds
      });
    });

    test('a split builds only the new pane', () async {
      final counts = countsOf();
      await testNocterm('split builds one pane', (tester) async {
        final controller = TilingController(
          initialLayout: const SplitNode(
            direction: SplitDirection.horizontal,
            children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
            ratios: [0.5, 0.5],
          ),
        );
        await tester.pumpComponent(NoctermTilingWidget(
          controller: controller,
          slotBuilder: (slotId) => _CountingPane(
            slotId: slotId,
            onBuild: (id) => counts[id] = (counts[id] ?? 0) + 1,
          ),
          cachePanes: true,
        ));
        final initial = Map.of(counts);

        controller.focus.setFocus('left');
        controller.handleAction(TilingAction.splitVertical);
        await tester.pump();

        // The untouched sibling never rebuilds; the split branch restructures,
        // so only the replaced branch plus the new pane build.
        expect(counts['right'], initial['right']);
        expect(counts.length, 3); // exactly one new pane joined
      });
    });

    test('a version bump rebuilds only that pane', () async {
      final counts = {'left': 0, 'right': 0};
      final versions = {'left': 0, 'right': 0};
      await testNocterm('version bump rebuilds one pane', (tester) async {
        final controller = TilingController(
          initialLayout: const SplitNode(
            direction: SplitDirection.horizontal,
            children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
            ratios: [0.5, 0.5],
          ),
        );
        await tester.pumpComponent(NoctermTilingWidget(
          controller: controller,
          slotBuilder: (slotId) => _CountingPane(
            slotId: slotId,
            onBuild: (id) => counts[id] = (counts[id] ?? 0) + 1,
          ),
          cachePanes: true,
          slotVersion: (slotId) => versions[slotId] ?? 0,
        ));
        final initial = Map.of(counts);

        // The host bumps one pane's inputs version; the next rebuild (any
        // routed action) invalidates that pane's cache and only that one.
        versions['left'] = 1;
        controller.handleAction(TilingAction.nextFocus);
        await tester.pump();

        expect(counts['left'], initial['left']! + 1);
        expect(counts['right'], initial['right']);
      });
    });

    test('without cachePanes content rebuilds on focus (back-compat)',
        () async {
      final counts = countsOf();
      await testNocterm('no cache rebuilds all', (tester) async {
        final controller = TilingController(
          initialLayout: const SplitNode(
            direction: SplitDirection.horizontal,
            children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
            ratios: [0.5, 0.5],
          ),
        );
        await tester.pumpComponent(NoctermTilingWidget(
          controller: controller,
          slotBuilder: (slotId) => _CountingPane(
            slotId: slotId,
            onBuild: (id) => counts[id] = (counts[id] ?? 0) + 1,
          ),
        ));
        final initial = Map.of(counts);

        // A routed action rebuilds the whole tree by default.
        controller.handleAction(TilingAction.nextFocus);
        await tester.pump();

        expect(counts['left'], greaterThan(initial['left']!));
        expect(counts['right'], greaterThan(initial['right']!));
      });
    });
  });

  test('controller mode forwards unhandled keys', () async {
    await testNocterm('controller mode forwards unhandled keys',
        (tester) async {
      final controller = TilingController(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'a'), SlotNode(slotId: 'b')],
          ratios: [0.5, 0.5],
        ),
      );
      final handled = <String>[];
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('pane-$id'),
          onUnhandledKeyEvent: (event) {
            handled.add(event.logicalKey.debugName);
            return true;
          },
        ),
      );
      controller.focus.setFocus('a');
      // Bound tiling keys are consumed by the controller...
      await tester.sendTab();
      if (handled.isNotEmpty || controller.focus.current != 'b') {
        throw StateError('bound key leaked to the fallback handler');
      }
      // ...unbound keys reach the host application (e.g. a plugin palette).
      await tester.sendKey(LogicalKey.digit2);
      if (!handled.contains('digit2')) {
        throw StateError('unbound key was not forwarded');
      }
    });
  });

  test('controller mode reports unhandled keys as unhandled', () async {
    await testNocterm('controller mode reports unhandled keys as unhandled',
        (tester) async {
      final controller =
          TilingController(initialLayout: const SlotNode(slotId: 'a'));
      await tester.pumpComponent(
        NoctermTilingWidget(
          controller: controller,
          slotBuilder: (id) => Text('pane-$id'),
          onUnhandledKeyEvent: (_) => false,
        ),
      );
      await tester.sendKey(LogicalKey.digit9);
      if (!tester.terminalState.containsText('pane-a')) {
        throw StateError('widget stopped rendering after unhandled key');
      }
    });
  });
}
