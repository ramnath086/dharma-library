/// The reader's offline IAST fold. Shared by indexing and querying so a
/// persisted index cannot diverge from the live query normalisation.
String foldSearch(String s) {
  const from = 'āīūṛṝḷḹṃṁḥṅñṭḍṇśṣ\'’';
  const to = 'aiurrllmmhnntdnss';
  var out = s.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], i < to.length ? to[i] : '');
  }
  return out.replaceAll('sh', 's').replaceAll('ri', 'r').replaceAll('ee', 'i');
}
