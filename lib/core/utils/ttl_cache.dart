class TtlCache<K, V> {
  TtlCache({required this.ttl, this.maxEntries = 100});

  final Duration ttl;
  final int maxEntries;
  final _entries = <K, _TtlCacheEntry<V>>{};

  V? get(K key) {
    final entry = _entries[key];
    if (entry == null) return null;

    if (DateTime.now().isAfter(entry.expiresAt)) {
      _entries.remove(key);
      return null;
    }

    return entry.value;
  }

  void put(K key, V value) {
    if (maxEntries <= 0) return;

    if (_entries.length >= maxEntries && !_entries.containsKey(key)) {
      _prune();
    }

    if (_entries.length >= maxEntries && !_entries.containsKey(key)) {
      _entries.remove(_entries.keys.first);
    }

    _entries[key] = _TtlCacheEntry(
      value: value,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  void clear() => _entries.clear();

  void _prune() {
    final now = DateTime.now();
    _entries.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }
}

class _TtlCacheEntry<V> {
  const _TtlCacheEntry({required this.value, required this.expiresAt});

  final V value;
  final DateTime expiresAt;
}
