import 'package:nocterm/nocterm.dart';

import '../core/plugin.dart';
import '../core/service_container.dart';
import '../core/event_bus.dart';

/// Context passed to a [SlotPlugin] while rendering its slot.
class SlotContext {
  const SlotContext({
    required this.slotId,
    required this.isFocused,
    required this.services,
    required this.events,
  });

  final String slotId;
  final bool isFocused;
  final ServiceContainer services;
  final EventBus events;
}

/// A plugin that can render itself into a tiling slot.
abstract class SlotPlugin extends Plugin {
  const SlotPlugin();

  /// Id of the slot this plugin renders into.
  String get slotId;

  Component build(SlotContext context);
}
