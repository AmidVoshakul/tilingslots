import 'dart:async';

import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

/// A plugin whose background timer throws asynchronously — the classic
/// "zombie" that kills hosts without zone isolation.
class TimerBombPlugin extends Plugin {
  TimerBombPlugin(this.pluginId, {this.explodeOnTick = 2});

  @override
  String get id => pluginId;
  final String pluginId;

  final int explodeOnTick;
  int ticks = 0;
  bool timerStopped = false;

  @override
  String get name => pluginId;

  @override
  String get version => '1.0.0';

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    // The timer is created through the scope, so it lives in the plugin's
    // zone: its uncaught error is contained by the kernel, not the host.
    scope.every(const Duration(milliseconds: 5), (_) {
      ticks++;
      if (ticks >= explodeOnTick) {
        throw StateError('async boom in plugin');
      }
    });
    scope.defer(() => timerStopped = true);
  }
}

class WellBehavedPlugin extends Plugin {
  WellBehavedPlugin(this.pluginId);
  @override
  String get id => pluginId;
  final String pluginId;
  int ticks = 0;

  @override
  String get name => pluginId;
  @override
  String get version => '1.0.0';

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    container.registerSingleton<String>('neighbour-svc');
    scope.every(const Duration(milliseconds: 5), (_) => ticks++);
  }
}

void main() {
  group('plugin zone isolation', () {
    test('an async crash is contained: host lives, plugin fails, scope closes',
        () async {
      final container = ServiceContainer();
      final bus = EventBus();
      final manager = PluginManager(container: container, bus: bus);
      final bomb = TimerBombPlugin('bomb');
      manager.register(bomb);
      final errors = <PluginErrorEvent>[];
      final crashes = <PluginCrashedEvent>[];
      bus.subscribe<PluginErrorEvent>(errors.add);
      bus.subscribe<PluginCrashedEvent>(crashes.add);

      await manager.enable('bomb');
      // Let the timer fire and crash.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // The host survived this line — that is the isolation proof.
      expect(errors, isNotEmpty);
      expect(errors.first.pluginId, 'bomb');
      expect(crashes, isNotEmpty);
      expect(crashes.first.pluginId, 'bomb');

      // The plugin is no longer enabled and is marked failed.
      expect(manager.isEnabled('bomb'), isFalse);
      expect(manager.hasFailed('bomb'), isTrue);
      expect(manager.failedPlugins, contains('bomb'));

      // Its scoped effects were disposed: the tick counter stops growing.
      final ticksAtCrash = bomb.ticks;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bomb.ticks, ticksAtCrash);
      expect(bomb.timerStopped, isTrue);
    });

    test('neighbour plugins survive the crash untouched', () async {
      final container = ServiceContainer();
      final bus = EventBus();
      final manager = PluginManager(container: container, bus: bus);
      final neighbour = WellBehavedPlugin('good');
      final bomb = TimerBombPlugin('bomb', explodeOnTick: 2);
      manager.register(neighbour);
      manager.register(bomb);
      await manager.enable('good');
      await manager.enable('bomb');

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(manager.isEnabled('good'), isTrue);
      expect(manager.hasFailed('good'), isFalse);
      expect(container.resolve<String>(), 'neighbour-svc');
      final neighbourTicks = neighbour.ticks;
      // The neighbour keeps ticking after the crash.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(neighbour.ticks, greaterThan(neighbourTicks));
    });

    test('a crashed plugin can be re-enabled cleanly', () async {
      final container = ServiceContainer();
      final bus = EventBus();
      final manager = PluginManager(container: container, bus: bus);
      final bomb = TimerBombPlugin('bomb', explodeOnTick: 2);
      manager.register(bomb);
      await manager.enable('bomb');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(manager.hasFailed('bomb'), isTrue);

      final again = TimerBombPlugin('bomb', explodeOnTick: 10000);
      await manager.replace('bomb', again);
      expect(manager.isEnabled('bomb'), isFalse); // crashed plugins stay off
      await manager.enable('bomb');
      expect(manager.isEnabled('bomb'), isTrue);
      expect(manager.hasFailed('bomb'), isFalse);
    });

    test('sync setup failures still roll back the container', () async {
      final container = ServiceContainer();
      final bus = EventBus();
      final manager = PluginManager(container: container, bus: bus);
      final before = container.capture();
      manager.register(_SyncFailPlugin());
      await manager.enable('sync-fail');
      await Future<void>.delayed(Duration.zero);
      expect(manager.isEnabled('sync-fail'), isFalse);
      expect(container.capture().entries.length, before.entries.length);
    });
  });
}

class _SyncFailPlugin extends Plugin {
  @override
  String get id => 'sync-fail';
  @override
  String get name => 'sync-fail';
  @override
  String get version => '1.0.0';

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    container.registerSingleton<String>('partial');
    throw StateError('sync boom');
  }
}
