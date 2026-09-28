import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Exercises CachingAssetBundle behavior, not just an overridden loadString.
class RecordingAssets extends CachingAssetBundle {
  RecordingAssets({this.files});
  final Map<String, Uint8List>? files;
  final reads = <String>[];
  final cacheRequests = <bool>[];
  int largestRead = 0;

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    cacheRequests.add(cache);
    return super.loadString(key, cache: cache);
  }

  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    final data = files == null ? await File(key).readAsBytes() : files![key];
    if (data == null) throw StateError('Missing asset: $key');
    if (data.length > largestRead) largestRead = data.length;
    return ByteData.sublistView(data);
  }
}
