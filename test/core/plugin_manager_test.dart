import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class FakePlugin extends Plugin {
  FakePlugin(this.id,
      {this.throwOnSetup = false, this.throwOnTeardown = false});

  @override
  final String id;
  @override
  String get name => id;
  @override
  String get version => '1.0.0';
  @override
  List<Type> get providedServices => [int];
  @override
  List<Type> get consumedServices => [];

  int setupCalls = 0;
  int teardownCalls = 0;
  bool enabled = false;
  PluginScope? seenSetupScope;
  PluginScope? seenTeardownScope;

  final bool throwOnSetup;
  final bool throwOnTeardown;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    if (throwOnSetup) throw StateError('setup boom');
    seenSetupScope = scope;
    setupCalls++;
    container.registerSingleton<int>(42);
    scope.defer(() => enabled = false);
    enabled = true;
  }

  @override
  Future<void> teardown(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    if (throwOnTeardown) throw StateError('teardown boom');
    seenTeardownScope = scope;
    teardownCalls++;
    if (container.contains<int>()) container.unregister<int>();
    enabled = false;
  }
}

void main() {
  group('PluginManager', () {
    test('registers plugin and exposes it', () {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('p1');
      pm.register(p);
      expect(pm.plugins.map((e) => e.id), contains('p1'));
    });

    test('enable calls setup and registers services', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('p1');
      pm.register(p);
      await pm.enable('p1');
      expect(p.setupCalls, 1);
      expect(c.resolve<int>(), 42);
    });

    test('disable calls teardown and unregisters services', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('p1');
      pm.register(p);
      await pm.enable('p1');
      await pm.disable('p1');
      expect(p.teardownCalls, 1);
      expect(c.contains<int>(), isFalse);
    });

    test('unregister removes plugin', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('p1');
      pm.register(p);
      await pm.enable('p1');
      await pm.unregister('p1');
      expect(pm.plugins.map((e) => e.id), isNot(contains('p1')));
    });

    test('setup failure is isolated and emits PluginErrorEvent', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('bad', throwOnSetup: true);
      pm.register(p);
      PluginErrorEvent? err;
      bus.subscribe<PluginErrorEvent>((e) => err = e);
      await pm.enable('bad');
      await Future<void>.delayed(Duration.zero);
      expect(p.setupCalls, 0);
      expect(err, isNotNull);
      expect(err!.pluginId, 'bad');
    });
  });
  group('Convergence coverage', () {
    test('lifecycle stream emits enabled', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('p2');
      pm.register(p);
      final events = <PluginLifecycleEvent>[];
      pm.lifecycle.listen(events.add);
      await pm.enable('p2');
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e.type), contains('enabled'));
    });

    test('registering twice throws', () {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(FakePlugin('dup'));
      expect(() => pm.register(FakePlugin('dup')), throwsStateError);
    });

    test('enable unknown plugin throws', () {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      expect(() => pm.enable('ghost'), throwsStateError);
    });

    test('disable unknown plugin throws', () {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      expect(() => pm.disable('ghost'), throwsStateError);
    });

    test('enable is idempotent when already enabled', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('p3');
      pm.register(p);
      await pm.enable('p3');
      await pm.enable('p3');
      expect(p.setupCalls, 1);
    });

    test('disable is idempotent when already disabled', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('p4');
      pm.register(p);
      await pm.enable('p4');
      await pm.disable('p4');
      await pm.disable('p4');
      expect(p.teardownCalls, 1);
      expect(pm.isEnabled('p4'), isFalse);
    });

    test('unregister without enable emits lifecycle events', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(FakePlugin('p5'));
      final events = <PluginLifecycleEvent>[];
      pm.lifecycle.listen(events.add);
      await pm.unregister('p5');
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e.type), contains('unregistered'));
    });

    test('teardown failure isolates error but still disables', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('p6', throwOnTeardown: true);
      pm.register(p);
      await pm.enable('p6');
      await pm.disable('p6');
      expect(pm.isEnabled('p6'), isFalse);
      expect(c.contains<int>(), isTrue);
    });

    test('setup failure rolls back partial registrations', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(FakePlugin('good'));
      await pm.enable('good');
      final before = c.capture();
      final bad = _PartialPlugin('bad');
      pm.register(bad);
      await pm.enable('bad');
      await Future<void>.delayed(Duration.zero);
      expect(pm.isEnabled('bad'), isFalse);
      expect(c.contains<String>(), isFalse);
      expect(before.entries.length, greaterThan(0));
    });

    test('enable on a disposed manager throws and mutates nothing', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(FakePlugin('closed'));
      pm.dispose();
      expect(() => pm.enable('closed'), throwsStateError);
      expect(pm.isEnabled('closed'), isFalse);
      expect(c.contains<int>(), isFalse);
      expect(() => pm.disable('closed'), throwsStateError);
    });

    test('register and unregister on a disposed manager throw', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.dispose();
      expect(() => pm.register(FakePlugin('late')), throwsStateError);
      expect(pm.plugins, isEmpty);
      expect(() => pm.unregister('late'), throwsStateError);
    });

    test('dispose tears down still-enabled plugins', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      final p = FakePlugin('live');
      pm.register(p);
      await pm.enable('live');
      await pm.dispose();
      expect(p.teardownCalls, 1);
      expect(pm.isEnabled('live'), isFalse);
      expect(c.contains<int>(), isFalse);
    });

    test('enabled state survives a throwing event listener', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(FakePlugin('boom-listener'));
      bus.subscribe<PluginEnabledEvent>(
          (_) => throw StateError('listener boom'));
      await pm.enable('boom-listener');
      await Future<void>.delayed(Duration.zero);
      expect(pm.isEnabled('boom-listener'), isTrue);
      expect(c.resolve<int>(), 42);
    });
    test('a failing container rollback is still surfaced as an event',
        () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(_BrokenRollbackPlugin());
      final errors = <PluginErrorEvent>[];
      bus.subscribe<PluginErrorEvent>(errors.add);
      await pm.enable('broken-rollback');
      await Future<void>.delayed(Duration.zero);
      // The setup failure plus the rollback failure are both reported.
      if (errors.length < 2) {
        throw StateError(
            'rollback failure was not reported (got ${errors.length})');
      }
      expect(pm.isEnabled('broken-rollback'), isFalse);
    });
  });
}

/// Registers a service whose dispose hook throws, then fails setup: the
/// snapshot rollback must dispose it and therefore fails too.
class _BrokenRollbackPlugin extends Plugin {
  @override
  String get id => 'broken-rollback';

  @override
  String get name => 'broken-rollback';

  @override
  String get version => '1.0.0';

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    container.registerSingleton<String>('ok',
        dispose: (_) => throw StateError('dispose boom'));
    // Fail after registering so the snapshot rollback must run.
    throw StateError('setup boom');
  }
}

class _PartialPlugin extends Plugin {
  _PartialPlugin(this.id);

  @override
  final String id;

  @override
  String get name => id;

  @override
  String get version => '1.0.0';

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    container.registerSingleton<String>('partial');
    throw StateError('late boom');
  }
}
