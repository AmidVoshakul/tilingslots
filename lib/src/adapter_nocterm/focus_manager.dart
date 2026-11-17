/// Focus management for tiling slots.
library;

import 'package:nocterm/nocterm.dart';

/// Focus traversal for slots.
class FocusManager extends ChangeNotifier {
  FocusManager({required List<String> slotOrder})
      : _slotOrder = List<String>.from(slotOrder);

  List<String> _slotOrder;
  int? _index;

  List<String> get traversalOrder => _slotOrder;

  String? get current => _index == null ? null : _slotOrder[_index!];

  void updateSlots(List<String> slots) {
    final currentSlot = _index == null
        ? null
        : (_index! < _slotOrder.length ? _slotOrder[_index!] : null);
    _slotOrder = List<String>.from(slots);
    if (currentSlot != null && _slotOrder.contains(currentSlot)) {
      _index = _slotOrder.indexOf(currentSlot);
    } else if (_slotOrder.isNotEmpty) {
      _index = 0;
    } else {
      _index = null;
    }
    notifyListeners();
  }

  void setFocus(String slotId) {
    final i = _slotOrder.indexOf(slotId);
    if (i < 0) throw StateError('Unknown slot: $slotId');
    _index = i;
    notifyListeners();
  }

  void next() {
    if (_slotOrder.isEmpty) return;
    _index = (_index == null) ? 0 : (_index! + 1) % _slotOrder.length;
    notifyListeners();
  }

  void prev() {
    if (_slotOrder.isEmpty) return;
    _index = (_index == null)
        ? _slotOrder.length - 1
        : (_index! - 1 + _slotOrder.length) % _slotOrder.length;
    notifyListeners();
  }
}
