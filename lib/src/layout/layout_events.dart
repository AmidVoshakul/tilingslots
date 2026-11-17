import '../core/tail_event.dart';

/// Emitted when a layout mutation occurs.
class LayoutChangedEvent extends TailEvent {
  LayoutChangedEvent({required this.operation, this.slotId}) : super();

  final String operation;
  final String? slotId;
}
