import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class _Crasher extends SlotPlugin {
  @override
  String get id => 'crasher';
  @override
  String get name => 'crasher';
  @override
  String get version => '0.1.0';
  @override
  String get slotId => 'crasher';

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    scope.every(const Duration(milliseconds: 5), (_) {
      throw StateError('crash');
    });
  }

  @override
  Component build(SlotContext context) => const Text('crasher');
}

class _Good extends SlotPlugin {
  int ticks = 0;
  @override
  String get id => 'good';
  @override
  String get name => 'good';
  @override
  String get version => '0.1.0';
  @override
  String get slotId => 'good';

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    scope.every(const Duration(milliseconds: 5), (_) => ticks++);
  }

  @override
  Component build(SlotContext context) => const Text('good');
}

void main() {
  group('crash isolation', () {
    test('a crashing plugin removes its active pane after attach', () async {
      final ws = SlotWorkspace(
        initialLayout: const SplitNode(
          direction: SplitDirection.horizontal,
          children: [SlotNode(slotId: 'left'), SlotNode(slotId: 'right')],
          ratios: [0.5, 0.5],
        ),
      );
      ws.register(_Crasher());
      await ws.enable('crasher', into: 'right');

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(ws.isEnabled('crasher'), isFalse);
      expect(ws.pluginForSlot('right'), isNull);
      final slots = LayoutEngine.computeRects(ws.layout, 30, 10).keys.toList();
      expect(slots, isNot(contains('right')));
      expect(slots, contains('left'));
      expect(ws.available.map((p) => p.id), contains('crasher'));
    });

    test('neighbour plugin survives a crash', () async {
      final ws = SlotWorkspace();
      ws.register(_Good());
      ws.register(_Crasher());
      await ws.enable('good');
      await ws.enable('crasher');

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(ws.isEnabled('good'), isTrue);
      expect(ws.isEnabled('crasher'), isFalse);
    });
  });
}
