/// A map whose insertion order is its recency: the newest entry last, the
/// oldest first to go.
extension RecencyMap<K, V> on Map<K, V> {
  /// Sets [key] as the newest entry, dropping the oldest past [capacity].
  void putNewest(K key, V value, {required int capacity}) {
    remove(key);
    this[key] = value;
    while (length > capacity) {
      remove(keys.first);
    }
  }
}
