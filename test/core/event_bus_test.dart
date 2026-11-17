import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

class AEvent extends TailEvent {
  AEvent(this.value);
  final int value;
}

class BEvent extends TailEvent {
  BEvent(this.label);
  final String label;
}

void main() {
  group('EventBus', () {
    test('delivers published event to subscriber', () async {
      final bus = EventBus();
      int? received;
      bus.subscribe<AEvent>((e) => received = e.value);
      bus.publish(AEvent(42));
      await Future<void>.delayed(Duration.zero);
      expect(received, 42);
    });

    test('delivers to multiple subscribers', () async {
      final bus = EventBus();
      final received = <int>[];
      bus.subscribe<AEvent>((e) => received.add(e.value));
      bus.subscribe<AEvent>((e) => received.add(e.value * 10));
      bus.publish(AEvent(3));
      await Future<void>.delayed(Duration.zero);
      expect(received, containsAll([3, 30]));
    });

    test('filters by event type', () async {
      final bus = EventBus();
      var aCount = 0;
      var bCount = 0;
      bus.subscribe<AEvent>((_) => aCount++);
      bus.subscribe<BEvent>((_) => bCount++);
      bus.publish(AEvent(1));
      await Future<void>.delayed(Duration.zero);
      expect(aCount, 1);
      expect(bCount, 0);
    });

    test('handler throwing does not break other subscribers', () async {
      final bus = EventBus();
      var secondCalled = false;
      bus.subscribe<AEvent>((_) => throw StateError('boom'));
      bus.subscribe<AEvent>((_) => secondCalled = true);
      bus.publish(AEvent(1));
      await Future<void>.delayed(Duration.zero);
      expect(secondCalled, isTrue);
    });

    test('cancelled subscription stops delivery', () async {
      final bus = EventBus();
      var count = 0;
      final sub = bus.subscribe<AEvent>((_) => count++);
      sub.cancel();
      bus.publish(AEvent(1));
      await Future<void>.delayed(Duration.zero);
      expect(count, 0);
    });
  });
  group('Convergence', () {
    test('onError callback invoked on handler throw', () async {
      Object? logged;
      final bus = EventBus(onError: (e, st) => logged = e);
      bus.subscribe<AEvent>((_) => throw StateError('boom'));
      bus.publish(AEvent(1));
      await Future<void>.delayed(Duration.zero);
      expect(logged, isA<StateError>());
    });
  });
}
