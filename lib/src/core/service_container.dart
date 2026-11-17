/// A lightweight inversion-of-control container supporting singleton and
/// factory registrations keyed by type and optional name qualifier.
class ServiceContainer {
  final Map<_Key, _Entry> _entries = {};

  /// Reverse index: dependency key -> dependent keys.
  final Map<_Key, Set<_Key>> _dependents = {};

  /// Forward index: dependent key -> dependency keys.
  final Map<_Key, Set<_Key>> _dependencies = {};

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
      {String? name,
      void Function(T instance)? dispose,
      Iterable<Type> dependsOn = const <Type>[]}) {
    _flushPendingDispose();
    final key = _Key(T, name);
    final previous = _entries[key];
    if (previous != null && (_dependents[key]?.isNotEmpty ?? false)) {
      throw StateError('Service has dependents: $key');
    }
    _entries[key] = _Entry.singleton(instance, dispose: dispose);
    if (previous != null) _pendingDispose.add(previous);
    _setDependencies(key, dependsOn);
  }

  /// Registers a factory. Factory-produced instances are caller-owned: the
  /// container does not track or dispose them.
  void registerFactory<T>(T Function() factory,
      {String? name, Iterable<Type> dependsOn = const <Type>[]}) {
    _flushPendingDispose();
    final key = _Key(T, name);
    final previous = _entries[key];
    if (previous != null && (_dependents[key]?.isNotEmpty ?? false)) {
      throw StateError('Service has dependents: $key');
    }
    _entries[key] = _Entry.factory(factory);
    if (previous != null) _pendingDispose.add(previous);
    _setDependencies(key, dependsOn);
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

  void unregister<T>({String? name, bool force = false}) {
    _flushPendingDispose();
    final key = _Key(T, name);
    final dependents = _dependents[key];
    if ((dependents?.isNotEmpty ?? false) && !force) {
      throw StateError('Service has dependents: ${dependents!.join(', ')}');
    }
    if (force && dependents != null) {
      for (final dependent in List<_Key>.from(dependents)) {
        _dependencies[dependent]?.remove(key);
        if (_dependencies[dependent]?.isEmpty ?? false) {
          _dependencies.remove(dependent);
        }
      }
    }
    final entry = _entries.remove(key);
    entry?.disposeResolved();
    _clearDependencies(key);
    _dependents.remove(key);
  }

  ServiceContainerSnapshot capture() => ServiceContainerSnapshot(
        Map<_Key, _Entry>.from(_entries),
        dependents: {
          for (final entry in _dependents.entries)
            entry.key: Set<_Key>.from(entry.value),
        },
        dependencies: {
          for (final entry in _dependencies.entries)
            entry.key: Set<_Key>.from(entry.value),
        },
      );

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
    _dependents
      ..clear()
      ..addAll({
        for (final entry in snapshot.dependents.entries)
          entry.key: Set<_Key>.from(entry.value),
      });
    _dependencies
      ..clear()
      ..addAll({
        for (final entry in snapshot.dependencies.entries)
          entry.key: Set<_Key>.from(entry.value),
      });
  }

  void _setDependencies(_Key dependent, Iterable<Type> dependsOn) {
    // Remove stale edges from a previous registration of the same key.
    _clearDependencies(dependent);
    if (dependsOn.isEmpty) return;
    final deps = _dependencies[dependent] ??= <_Key>{};
    for (final type in dependsOn) {
      final dependency = _Key(type, null);
      deps.add(dependency);
      (_dependents[dependency] ??= <_Key>{}).add(dependent);
    }
  }

  void _clearDependencies(_Key dependent) {
    final deps = _dependencies.remove(dependent);
    if (deps == null) return;
    for (final dependency in deps) {
      _dependents[dependency]?.remove(dependent);
      if (_dependents[dependency]?.isEmpty ?? false) {
        _dependents.remove(dependency);
      }
    }
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

  @override
  String toString() => name == null ? '$type' : '$type:$name';
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
  const ServiceContainerSnapshot(
    this.entries, {
    this.dependents = const <_Key, Set<_Key>>{},
    this.dependencies = const <_Key, Set<_Key>>{},
  });
  final Map<_Key, _Entry> entries;
  final Map<_Key, Set<_Key>> dependents;
  final Map<_Key, Set<_Key>> dependencies;
}
