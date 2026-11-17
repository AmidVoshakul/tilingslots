import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class SimplePlugin extends Plugin {
  @override
  String get id => 'simple';
  @override
  String get name => 'Simple';
  @override
  String get version => '1.0.0';
  @override
  List<Type> get providedServices => [];
  @override
  List<Type> get consumedServices => [];
  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {}
  @override
  Future<void> teardown(
      ServiceContainer container, EventBus bus, PluginScope scope) async {}
}

class MetadataOnlyPlugin extends Plugin {
  const MetadataOnlyPlugin();
  @override
  String get id => 'meta';
  @override
  String get name => 'Meta';
  @override
  String get version => '1.0.0';
}

void main() {
  test('Plugin exposes metadata', () {
    final p = SimplePlugin();
    expect(p.id, 'simple');
    expect(p.providedServices, isEmpty);
  });

  test('Plugin defaults service metadata and lifecycle to no-ops', () async {
    const p = MetadataOnlyPlugin();
    expect(p.providedServices, isEmpty);
    expect(p.consumedServices, isEmpty);
    final container = ServiceContainer();
    final bus = EventBus();
    await p.setup(container, bus, PluginScope());
    await p.teardown(container, bus, PluginScope());
    expect(container.contains<int>(), isFalse);
  });

  test('TilingslotsException carries message and prints it', () {
    const e = TilingslotsException('boom');
    expect(e.message, 'boom');
    expect(e.toString(), 'TilingslotsException: boom');
  });

  test('UnknownSlotPluginError is a TilingslotsException', () {
    const e = UnknownSlotPluginError('no plugin for slot: x');
    expect(e, isA<TilingslotsException>());
    expect(e.message, 'no plugin for slot: x');
    expect(e.toString(), contains('no plugin for slot: x'));
  });
}
