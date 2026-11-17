import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class _ConfigurablePlugin extends Plugin {
  _ConfigurablePlugin(this.cfg);

  final Map<String, dynamic> cfg;

  @override
  String get id => 'cfg';

  @override
  String get name => 'cfg';

  @override
  String get version => '0.1.0';

  @override
  Map<String, dynamic>? get config => cfg;

  @override
  PluginConfigSchema? get configSchema => const PluginConfigSchema(
        required: <String, Type>{'port': int},
        optional: <String, Type>{'host': String},
      );
}

void main() {
  group('plugin config validation', () {
    test('invalid config throws PluginConfigValidationError', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(_ConfigurablePlugin({'port': '8080'}));
      expect(
          () => pm.enable('cfg'), throwsA(isA<PluginConfigValidationError>()));
    });

    test('missing required field throws PluginConfigValidationError', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(_ConfigurablePlugin({}));
      expect(
          () => pm.enable('cfg'), throwsA(isA<PluginConfigValidationError>()));
    });

    test('valid config enables plugin', () async {
      final c = ServiceContainer();
      final bus = EventBus();
      final pm = PluginManager(container: c, bus: bus);
      pm.register(_ConfigurablePlugin({'port': 8080, 'host': 'localhost'}));
      await pm.enable('cfg');
      expect(pm.isEnabled('cfg'), isTrue);
    });
  });
}
