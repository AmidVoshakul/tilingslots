/// A command that can be invoked from a command palette.
class PaletteCommand {
  const PaletteCommand({
    required this.id,
    required this.label,
    required this.run,
  });

  final String id;
  final String label;
  final void Function() run;
}

/// A simple in-memory command palette with case-insensitive filtering.
class CommandPalette {
  CommandPalette([List<PaletteCommand> commands = const <PaletteCommand>[]])
      : _commands = List<PaletteCommand>.from(commands);

  final List<PaletteCommand> _commands;
  String query = '';

  List<PaletteCommand> get filtered {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<PaletteCommand>.unmodifiable(_commands);
    return _commands
        .where((command) =>
            command.label.toLowerCase().contains(q) ||
            command.id.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void register(PaletteCommand command) => _commands.add(command);

  bool execute(String id) {
    for (final command in _commands) {
      if (command.id == id) {
        command.run();
        return true;
      }
    }
    return false;
  }
}
