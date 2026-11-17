/// A lightweight inversion-of-control container supporting singleton and
/// factory registrations keyed by type and optional name qualifier.
class ServiceContainer {
  final Map<_Key, _Entry> _entries = {};

  /// Entries displaced by an overwrite, awaiting disposal. Disposal is deferred
  /// so that a snapshot rollback ([restore]) can reinstate a displaced entry
  /// without it having been disposed first.
  final List<_Entry> _pendingDispose = [];

  void _flushPendingDispose() {
    if (_pendingDispose.isEmpty) return;
    final pending = List<_Entry>.from(_pendingDispose);
    _pendingDispose.clear();
    for (final entry in pending) {
      entry.disposeResolved();
    }
  }

  void registerSingleton<T>(T instance,
      {String? name, void Function(T instance)? dispose}) {
    _flushPendingDispose();
    final key = _Key(T, name);
    final previous = _entries[key];
    _entries[key] = _Entry.singleton(instance, dispose: dispose);
    if (previous != null) _pendingDispose.add(previous);
  }

  void registerFactory<T>(T Function() factory, {String? name}) {
    _flushPendingDispose();
    final key = _Key(T, name);
    final previous = _entries[key];
    _entries[key] = _Entry.factory(factory);
    if (previous != null) _pendingDispose.add(previous);
  }

  T resolve<T>({String? name}) {
    final entry = _entries[_Key(T, name)];
    if (entry == null) {
      throw StateError(
          'No service registered for $T${name == null ? '' : ' ($name)'}');
    }
    return entry.resolve<T>();
  }

  bool contains<T>({String? name}) => _entries.containsKey(_Key(T, name));

  void unregister<T>({String? name}) {
    _flushPendingDispose();
    final key = _Key(T, name);
    final entry = _entries.remove(key);
    entry?.disposeResolved();
  }

  ServiceContainerSnapshot capture() =>
      ServiceContainerSnapshot(Map<_Key, _Entry>.from(_entries));

  void restore(ServiceContainerSnapshot snapshot) {
    final restored = snapshot.entries;
    for (final key in _entries.keys.toList()) {
      final liveEntry = _entries[key];
      final restoredEntry = restored[key];
      // Live entries absent from the snapshot, or replaced while the snapshot
      // was pending, never belong to the restored state: dispose them once.
      if (restoredEntry == null || !identical(restoredEntry, liveEntry)) {
        liveEntry?.disposeResolved();
      }
    }
    // Entries brought back by the snapshot are no longer displaced.
    _pendingDispose.removeWhere((entry) => restored.containsValue(entry));
    _entries
      ..clear()
      ..addAll(restored);
  }

  void dispose() {
    _flushPendingDispose();
    for (final entry in _entries.values) {
      entry.disposeResolved();
    }
    _entries.clear();
  }
}

class _Key {
  const _Key(this.type, this.name);
  final Type type;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is _Key && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(type, name);
}

class _Entry {
  _Entry.singleton(this._instance, {this.dispose}) : _factory = null;
  _Entry.factory(this._factory)
      : _instance = null,
        dispose = null;

  final Object? _instance;
  final Function? _factory;
  final Function? dispose;
  bool _disposed = false;

  T resolve<T>() {
    if (_factory != null) {
      return (_factory as T Function())();
    }
    return _instance as T;
  }

  /// Runs the dispose hook at most once per entry, so snapshot rollback plus
  /// a later container dispose cannot double-dispose the same registration.
  /// Note: idempotency is per registration key, not per instance — the same
  /// object registered under two keys runs its hook once per key.
  void disposeResolved() {
    if (_disposed || dispose == null || _instance == null) return;
    _disposed = true;
    (dispose as Function)(_instance);
  }
}

/// Snapshot of a [ServiceContainer] state.
class ServiceContainerSnapshot {
  const ServiceContainerSnapshot(this.entries);
  final Map<_Key, _Entry> entries;
}
