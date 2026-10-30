import 'package:sqflite/sqflite.dart';

/// Bounds BOTH the Dart operation list and the Android platform-channel payload.
/// Flushing a batch inside a transaction does not commit the outer transaction:
/// SQLite journals/spills pages to disk while readiness stays atomic.
class BoundedBatch {
  BoundedBatch(this.executor);

  static const maxOperations = 128;
  static const maxBytes = 2 * 1024 * 1024;
  final DatabaseExecutor executor;
  Batch? _batch;
  int _operations = 0;
  int _bytes = 0;

  Future<void> insert(String table, Map<String, Object?> values) async {
    // A conservative UTF-8/platform encoding budget (3 bytes per UTF-16 code
    // unit, plus map/SQL overhead), without making another encoded body copy.
    var bytes = 1024;
    for (final entry in values.entries) {
      bytes += entry.key.length * 3 + 32;
      final value = entry.value;
      bytes += value is String ? value.length * 3 : 16;
    }
    if (bytes > maxBytes) throw StateError('Offline record exceeds batch budget');
    if (_operations >= maxOperations || _bytes + bytes > maxBytes) await flush();
    (_batch ??= executor.batch()).insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);
    _operations++;
    _bytes += bytes;
  }

  Future<void> flush() async {
    final batch = _batch;
    _batch = null;
    _operations = 0;
    _bytes = 0;
    if (batch != null) await batch.commit(noResult: true);
  }
}
