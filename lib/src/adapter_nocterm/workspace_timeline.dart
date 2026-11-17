import '../core/plugin.dart';

/// One recorded workspace mutation: the full workspace document before and
/// after the operation, plus metadata for timelines and undo/redo.
///
/// [implementations] / [afterImplementations] map plugin id → the instance
/// registered at that point, so undo/redo restore *which* implementation was
/// active (a document only records that a plugin id is enabled).
class WorkspaceEventEntry {
  const WorkspaceEventEntry({
    required this.seq,
    required this.type,
    required this.label,
    required this.before,
    required this.after,
    this.implementations = const {},
    this.afterImplementations = const {},
  });

  final int seq;
  final String type;
  final String label;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final Map<String, Plugin> implementations;
  final Map<String, Plugin> afterImplementations;
}

/// A named snapshot of the workspace document.
class WorkspaceCheckpoint {
  const WorkspaceCheckpoint({
    required this.id,
    required this.name,
    required this.document,
    this.implementations = const {},
  });

  final int id;
  final String name;
  final Map<String, dynamic> document;
  final Map<String, Plugin> implementations;
}

/// Append-only workspace history with undo/redo.
///
/// The timeline owns entries, the cursor, named checkpoints, and serialization
/// of operations; applying an entry's documents is the workspace's job (it
/// needs the plugin registry), reached through [stepBack]/[stepForward].
class WorkspaceTimeline {
  WorkspaceTimeline({int maxEntries = 200}) : _maxEntries = maxEntries;

  final int _maxEntries;
  final List<WorkspaceEventEntry> _log = [];
  final List<WorkspaceCheckpoint> _checkpoints = [];
  int _cursor = 0;
  int _seq = 0;
  int _checkpointCounter = 0;

  /// Serializes history operations so overlapping undo/redo (e.g. two quick
  /// keypresses) cannot desynchronize the cursor from the applied state.
  Future<void> _queue = Future<void>.value();

  List<WorkspaceEventEntry> get timeline => List.unmodifiable(_log);

  List<WorkspaceCheckpoint> get checkpoints => List.unmodifiable(_checkpoints);

  bool get canUndo => _cursor > 0;

  bool get canRedo => _cursor < _log.length;

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Appends an entry and advances the cursor, invalidating any redo branch.
  WorkspaceEventEntry append({
    required String type,
    required String label,
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
    Map<String, Plugin> implementations = const {},
    Map<String, Plugin> afterImplementations = const {},
  }) {
    final entry = WorkspaceEventEntry(
      seq: ++_seq,
      type: type,
      label: label,
      before: before,
      after: after,
      implementations: implementations,
      afterImplementations: afterImplementations,
    );
    if (_cursor < _log.length) {
      _log.removeRange(_cursor, _log.length);
    }
    _log.add(entry);
    _cursor = _log.length;
    while (_log.length > _maxEntries) {
      _log.removeAt(0);
      _cursor--;
    }
    return entry;
  }

  WorkspaceCheckpoint addCheckpoint({
    String? name,
    required Map<String, dynamic> document,
    Map<String, Plugin> implementations = const {},
  }) {
    final checkpoint = WorkspaceCheckpoint(
      id: ++_checkpointCounter,
      name: name ?? 'checkpoint-$_checkpointCounter',
      document: document,
      implementations: implementations,
    );
    _checkpoints.add(checkpoint);
    return checkpoint;
  }

  /// Moves the cursor back and returns the entry that was current, or `null`.
  WorkspaceEventEntry? stepBack() {
    if (!canUndo) return null;
    _cursor--;
    return _log[_cursor];
  }

  /// Moves the cursor forward and returns the entry to re-apply, or `null`.
  WorkspaceEventEntry? stepForward() {
    if (!canRedo) return null;
    final entry = _log[_cursor];
    _cursor++;
    return entry;
  }
}
