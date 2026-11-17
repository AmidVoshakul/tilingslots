/// Base class for all events flowing through the [EventBus].
abstract class TailEvent {
  TailEvent({DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();

  final DateTime timestamp;
}
