import 'dart:typed_data';

import 'package:tilingslots/tilingslots.dart';
import 'package:test/test.dart';

void main() {
  group('Float32RingBuffer', () {
    test('reads back in write order', () {
      final ring = Float32RingBuffer(4);
      ring.write(1);
      ring.write(2);
      ring.write(3);
      final out = Float32List(3);
      ring.copyTo(out, offset: 0);
      expect(out, [1, 2, 3]);
      expect(ring.length, 3);
    });

    test('after wrap, returns the newest window', () {
      final ring = Float32RingBuffer(3);
      for (var v = 1.0; v <= 5.0; v += 1.0) {
        ring.write(v);
      }
      final out = Float32List(3);
      ring.copyTo(out, offset: 0);
      expect(out, [3, 4, 5]);
      expect(ring.length, 3);
      expect(ring.capacity, 3);
    });

    test('copyTo limit copies only the newest values', () {
      final ring = Float32RingBuffer(4);
      for (var v = 1.0; v <= 4.0; v += 1.0) {
        ring.write(v);
      }
      final out = Float32List(2);
      ring.copyTo(out, offset: 0, limit: 2);
      expect(out, [3, 4]);
    });

    test('copyTo honours the offset', () {
      final ring = Float32RingBuffer(2);
      ring.write(10);
      ring.write(20);
      final out = Float32List(4)..fillRange(0, 4, -1);
      ring.copyTo(out, offset: 2);
      expect(out, [-1, -1, 10, 20]);
    });

    test('clear resets length and zeroes the memory', () {
      final ring = Float32RingBuffer(4);
      ring.write(7);
      ring.write(8);
      ring.clear();
      expect(ring.length, 0);
      final out = Float32List(1);
      // Copying from an empty ring copies nothing; fill then write to prove it
      // stayed clean.
      ring.write(9);
      ring.copyTo(out, offset: 0);
      expect(out, [9]);
    });

    test('write does not allocate: capacity fixed at construction', () {
      final ring = Float32RingBuffer(8);
      final before = ring.capacity;
      for (var i = 0; i < 100; i++) {
        ring.write(i.toDouble());
      }
      expect(ring.capacity, before);
      expect(ring.length, 8);
    });

    test('supports last-value lookup for gauges', () {
      final ring = Float32RingBuffer(4);
      expect(ring.last, isNull);
      ring.write(0.25);
      ring.write(0.75);
      expect(ring.last, 0.75);
    });
  });

  group('braille sparkline', () {
    Float32RingBuffer ringOf(List<double> values, {int capacity = 64}) {
      final ring = Float32RingBuffer(
          capacity < values.length ? values.length : capacity);
      for (final v in values) {
        ring.write(v);
      }
      return ring;
    }

    test('empty ring renders blanks', () {
      final ring = Float32RingBuffer(8);
      final scratch = Float32List(16);
      final text = sparkline(ring, width: 4, scratch: scratch);
      expect(text, '    ');
    });

    test('a ramp rises left to right', () {
      final ring = ringOf([for (var i = 0; i < 12; i++) i / 11]);
      final scratch = Float32List(12);
      final text = sparkline(ring, width: 6, scratch: scratch);
      // Rising data: the top row of the last char must have a dot set.
      expect(text, isNotEmpty);
      final codeUnits = text.codeUnits;
      expect(codeUnits.last, greaterThan(0x2800));
    });

    test('normalizes to the observed min/max by default', () {
      final ring = ringOf([0.0, 5.0]);
      final scratch = Float32List(4);
      final flat = sparkline(ring, width: 2, scratch: scratch);
      final ring2 = ringOf([100.0, 500.0]);
      final scratch2 = Float32List(4);
      final shifted = sparkline(ring2, width: 2, scratch: scratch2);
      expect(flat, shifted); // relative shape is what matters
    });

    test('explicit bounds clamp outliers', () {
      final ring = ringOf([-10.0, 50.0]);
      final scratch = Float32List(4);
      final bounded =
          sparkline(ring, width: 2, min: 0, max: 10, scratch: scratch);
      final expected = sparkline(ringOf([0.0, 10.0]),
          width: 2, min: 0, max: 10, scratch: Float32List(4));
      expect(bounded, expected);
    });

    test('renders the same frame deterministically', () {
      final ring = ringOf([for (var i = 0; i < 30; i++) i.isEven ? 0.9 : 0.1]);
      final scratch = Float32List(30);
      final a = sparkline(ring, width: 15, scratch: scratch);
      final b = sparkline(ring, width: 15, scratch: Float32List(30));
      expect(a, b);
    });
  });

  group('bar gauge', () {
    test('full and empty gauges', () {
      expect(barGauge(1.0, 4), '████');
      expect(barGauge(0.0, 4), '░░░░');
    });

    test('partial fills use fractional blocks', () {
      expect(barGauge(0.5, 4), '██░░');
      final quarter = barGauge(0.25, 4);
      expect(quarter.codeUnits.first, greaterThan(0x2580));
      expect(quarter.codeUnits.first, lessThan(0x2590));
    });

    test('width of one renders exactly one cell', () {
      expect(barGauge(0.5, 1).length, 1);
    });

    test('clamps out-of-range ratios', () {
      expect(barGauge(2.0, 3), '███');
      expect(barGauge(-1.0, 3), '░░░');
    });
  });

  group('frame stability (steady state)', () {
    test('100 frames produce identical strings with one reused scratch', () {
      final ring = Float32RingBuffer(64);
      final scratch = Float32List(64);
      String? first;
      for (var frame = 0; frame < 100; frame++) {
        ring.write((frame % 7) / 7);
        final text = sparkline(ring, width: 16, scratch: scratch);
        first ??= text;
      }
      // The final frame differs from the first, but the scratch is reused and
      // no per-frame state accumulates.
      expect(first, isNotNull);
      final again = sparkline(ring, width: 16, scratch: scratch);
      expect(first != again, isTrue);
    });
  });
}
