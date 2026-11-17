import 'package:nocterm/nocterm.dart';

/// Actions supported by the tiling adapter.
/// Supported tiling actions.
enum TilingAction {
  nextFocus,
  prevFocus,
  resizeGrow,
  resizeShrink,
  splitHorizontal,
  splitVertical,
  close,
  zoom,
}

/// Configurable keymap.
class Keymap {
  Keymap([Map<LogicalKey, TilingAction>? bindings])
      : bindings =
            bindings == null ? Map.unmodifiable(defaultBindings) : bindings;

  final Map<LogicalKey, TilingAction> bindings;

  static final Map<LogicalKey, TilingAction> defaultBindings =
      Map.unmodifiable({
    LogicalKey.tab: TilingAction.nextFocus,
    LogicalKey.arrowLeft: TilingAction.prevFocus,
    LogicalKey.arrowRight: TilingAction.nextFocus,
    LogicalKey.arrowUp: TilingAction.resizeGrow,
    LogicalKey.arrowDown: TilingAction.resizeShrink,
    LogicalKey.keyS: TilingAction.splitHorizontal,
    LogicalKey.keyV: TilingAction.splitVertical,
    LogicalKey.keyX: TilingAction.close,
    LogicalKey.keyZ: TilingAction.zoom,
  });
}

/// Keyboard shortcut handler.
class KeyboardBindings {
  KeyboardBindings({Keymap? keymap}) : _keymap = keymap ?? Keymap();

  final Keymap _keymap;

  TilingAction? resolve(KeyboardEvent event) =>
      _keymap.bindings[event.logicalKey];

  bool handle(KeyboardEvent event,
      {required void Function(TilingAction) onAction}) {
    final action = resolve(event);
    if (action == null) return false;
    onAction(action);
    return true;
  }
}
