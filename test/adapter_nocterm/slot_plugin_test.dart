import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class P extends SlotPlugin {
  P(this.idName);
  final String idName;
  @override
  String get id => idName;
  @override
  String get name => idName;
  @override
  String get version => '1.0.0';
  @override
  String get slotId => idName;
  @override
  List<Type> get providedServices => [];
  @override
  List<Type> get consumedServices => [];
  @override
  Future<void> setup(ServiceContainer c, EventBus b, PluginScope s) async {}
  @override
  Future<void> teardown(ServiceContainer c, EventBus b, PluginScope s) async {}
  @override
  Component build(SlotContext context) => Text('pane-$idName');
}

class Minimal extends SlotPlugin {
  const Minimal();
  @override
  String get id => 'minimal';
  @override
  String get name => 'Minimal';
  @override
  String get version => '1.0.0';
  @override
  String get slotId => 'minimal';
  @override
  Component build(SlotContext context) => const Text('minimal');
}

void main() {
  test('SlotPlugin builds', () {
    final p = P('a');
    final ctx = SlotContext(
        slotId: 'a',
        isFocused: true,
        services: ServiceContainer(),
        events: EventBus());
    expect(p.build(ctx), isA<Text>());
  });

  test('SlotPlugin provides default no-op lifecycle', () async {
    const p = Minimal();
    final container = ServiceContainer();
    final bus = EventBus();
    await p.setup(container, bus, PluginScope());
    await p.teardown(container, bus, PluginScope());
    final ctx = SlotContext(
        slotId: 'minimal', isFocused: false, services: container, events: bus);
    expect(p.build(ctx), isA<Text>());
  });
}
