import 'package:nocterm/nocterm.dart';
import 'package:tilingslots/tilingslots.dart';

/// Minimal SlotPlugin template. Copy, rename, and register with a SlotWorkspace.
class TemplatePlugin extends SlotPlugin {
  const TemplatePlugin({this.id = 'template', this.slot = 'template'});

  @override
  final String id;

  final String slot;

  @override
  String get name => 'Template';

  @override
  String get version => '0.1.0';

  @override
  String get slotId => slot;

  @override
  Future<void> setup(
      ServiceContainer container, EventBus bus, PluginScope scope) async {
    // Register long-lived resources on scope so they are disposed automatically.
  }

  @override
  Component build(SlotContext context) => const Text('template pane');
}
