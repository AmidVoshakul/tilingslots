import 'dart:typed_data';

/// A fixed-capacity ring buffer of doubles on a single `Float32List`.
///
/// The hardware analogy: a cache-line-sized scratchpad for a time series. Reads
/// and writes stay in one pre-allocated block of memory, so a steady-state
/// render loop performs zero allocations (no GC jitter per frame), unlike a
/// `List<double>` which reallocates and collects as it grows.
class Float32RingBuffer {
  Float32RingBuffer(int capacity)
      : assert(capacity > 0, 'capacity must be positive'),
        _buffer = Float32List(capacity);

  final Float32List _buffer;
  int _head = 0;
  int _size = 0;

  int get capacity => _buffer.length;

  int get length => _size;

  bool get isFull => _size == _buffer.length;

  /// The most recently written value, or `null` when empty.
  double? get last => _size == 0
      ? null
      : _buffer[(_head - 1 + _buffer.length) % _buffer.length];

  /// Appends [value], overwriting the oldest sample when full.
  void write(double value) {
    _buffer[_head] = value;
    _head = (_head + 1) % _buffer.length;
    if (_size < _buffer.length) _size++;
  }

  /// Copies the window (oldest first) into [destination] at [offset]. The
  /// destination must have room for the copied values after [offset].
  ///
  /// [limit] copies only the newest `limit` values instead of the whole
  /// window, so callers can read a frame-sized tail out of a long history.
  void copyTo(Float32List destination, {required int offset, int? limit}) {
    final take = limit == null ? _size : (limit < _size ? limit : _size);
    assert(
      destination.length - offset >= take,
      'destination has no room for $take values at offset $offset',
    );
    final capacity = _buffer.length;
    final start = (_size < capacity ? 0 : _head) + (_size - take);
    for (var i = 0; i < take; i++) {
      destination[offset + i] = _buffer[(start + i) % capacity];
    }
  }

  /// Empties the buffer and zeroes its memory.
  void clear() {
    _head = 0;
    _size = 0;
    _buffer.fillRange(0, _buffer.length, 0.0);
  }
}

// Braille dot bitmasks: each character is a 2x4 dot matrix.
// Left column bits (rows 0..3), right column bits (rows 0..3).
const List<int> _kBrailleLeftBits = [0x01, 0x02, 0x04, 0x40];
const List<int> _kBrailleRightBits = [0x08, 0x10, 0x20, 0x80];

/// Renders [ring] as a braille sparkline of [width] characters.
///
/// Two samples per character give the full 2x4 dot resolution. Pass a reusable
/// [scratch] buffer to keep the frame allocation-free. Values are normalized to
/// the observed min/max unless [min]/[max] are given; a wider range maps to
/// lower bars.
String sparkline(
  Float32RingBuffer ring, {
  required int width,
  int height = 1,
  double? min,
  double? max,
  Float32List? scratch,
}) {
  final samples = width * 2;
  final buffer = scratch ?? Float32List(samples);
  assert(
    buffer.length >= samples,
    'scratch must hold at least $samples values',
  );
  final available = ring.length;
  if (available == 0 || width <= 0) {
    return ' ' * (width <= 0 ? 0 : width);
  }
  final count = samples < available ? samples : available;
  // Copy the newest `count` samples to the end of the scratch window.
  final offset = samples - count;
  final work = Float32List.sublistView(buffer, 0, samples);
  work.fillRange(0, samples, 0.0);
  ring.copyTo(work, offset: offset, limit: count);

  var lo = min ?? double.infinity;
  var hi = max ?? double.negativeInfinity;
  if (min == null) {
    for (var i = 0; i < count; i++) {
      final v = work[offset + i];
      if (v < lo) lo = v;
    }
  }
  if (max == null) {
    for (var i = 0; i < count; i++) {
      final v = work[offset + i];
      if (v > hi) hi = v;
    }
  }
  final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
  final totalRows = height * 4;

  // Global filled-dot count per sample (0..totalRows).
  final filledPerSample = List<int>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    final normalized = ((work[offset + i] - lo) / span).clamp(0.0, 1.0);
    filledPerSample[i] = (normalized * totalRows).floor().clamp(0, totalRows);
  }

  final lines = <String>[];
  for (var row = 0; row < height; row++) {
    final buffer2 = StringBuffer();
    final globalRowStart = (height - 1 - row) * 4; // bottom-up character rows
    for (var col = 0; col < width; col++) {
      var mask = 0;
      final base = col * 2;
      for (var half = 0; half < 2; half++) {
        final sampleIndex = base + half;
        final idx = sampleIndex - offset;
        final sampleFilled =
            (idx >= 0 && idx < count) ? filledPerSample[idx] : 0;
        final dotsInThisChar = (sampleFilled - globalRowStart).clamp(0, 4);
        final bits = half == 0 ? _kBrailleLeftBits : _kBrailleRightBits;
        for (var d = 0; d < dotsInThisChar; d++) {
          mask |= bits[d];
        }
      }
      buffer2.writeCharCode(0x2800 + mask);
    }
    lines.add(buffer2.toString());
  }
  return lines.join('\n');
}

/// Renders a horizontal bar gauge of [width] cells using block characters with
/// fractional eighths. [ratio] is clamped to 0..1.
String barGauge(double ratio, int width) {
  if (width <= 0) return '';
  const full = '█';
  const empty = '░';
  final clamped = ratio.clamp(0.0, 1.0);
  final result = StringBuffer();
  final exact = clamped * width;
  final fullCells = exact.floor();
  final remainder = exact - fullCells;
  for (var i = 0; i < width; i++) {
    if (i < fullCells) {
      result.write(full);
    } else if (i == fullCells && remainder > 0) {
      // Fractional cell: pick the nearest eighth block.
      final eighths = remainder * 8;
      final index = (eighths.round()).clamp(1, 8);
      result.writeCharCode(0x2590 - index); // ▏..▉
    } else {
      result.write(empty);
    }
  }
  return result.toString();
}
