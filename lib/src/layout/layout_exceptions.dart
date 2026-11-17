import '../core/exceptions.dart';

class LayoutSerializationException extends TilingslotsException {
  const LayoutSerializationException(super.message);
}

class LayoutValidationException extends TilingslotsException {
  const LayoutValidationException(super.message);
}
