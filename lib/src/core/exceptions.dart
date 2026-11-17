/// Base exception for all tilingslots errors.
class TilingslotsException implements Exception {
  const TilingslotsException(this.message);
  final String message;

  @override
  String toString() => 'TilingslotsException: $message';
}

/// Thrown when a slot references an unregistered plugin.
class UnknownSlotPluginError extends TilingslotsException {
  const UnknownSlotPluginError(super.message);
}
