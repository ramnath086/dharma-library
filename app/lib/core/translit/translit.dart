import 'tables.g.dart';

/// Sanskrit script conversion (Dart port of scripts/translit.py).
///
/// * [devaToIast] — Devanagari → IAST.
/// * [devaToScript] — Devanagari → Malayalam / Kannada / Telugu / Bengali /
///   Gujarati / Gurmukhi / Odia / Tamil (Tamil & Gurmukhi are lossy).
///
/// Used by the reader so that switching the "Script" setting works instantly
/// and offline, even for editions the server has not pre-rendered.
class Translit {
  Translit._();

  static const supportedScripts = ['Deva', 'Latn', 'Mlym', 'Knda', 'Telu', 'Beng', 'Gujr', 'Guru', 'Orya', 'Taml'];

  static bool isLossy(String script) => kLossyScripts.contains(script);

  static String devaToScript(String text, String script) {
    if (script == 'Deva') return text;
    if (script == 'Latn') return devaToIast(text);
    if (script == 'Taml') {
      final sb = StringBuffer();
      for (final ch in text.runes) {
        final s = String.fromCharCode(ch);
        sb.write(kTamil[s] ?? s);
      }
      return sb.toString();
    }
    final base = kBlocks[script];
    if (base == null) return text;
    final exc = kExceptions[script] ?? const {};
    final runes = text.runes.toList();
    final sb = StringBuffer();
    var i = 0;
    while (i < runes.length) {
      if (i + 1 < runes.length) {
        final two = String.fromCharCodes([runes[i], runes[i + 1]]);
        if (exc.containsKey(two)) {
          sb.write(exc[two] ?? '');
          i += 2;
          continue;
        }
      }
      final ch = String.fromCharCode(runes[i]);
      if (exc.containsKey(ch)) {
        sb.write(exc[ch] ?? '');
      } else {
        final cp = runes[i];
        final inRange = kOffsetRanges.any((r) => cp >= r[0] && cp <= r[1]);
        sb.write(inRange ? String.fromCharCode(cp - kDevaBase + base) : ch);
      }
      i++;
    }
    var res = sb.toString();
    if (script == 'Mlym') res = _malayalamChillu(res);
    return res;
  }

  static final _mlCons = RegExp('ര്(?=[\u0d15-\u0d3a])');
  static const _chillu = {'ന്': 'ൻ', 'ര്': 'ർ', 'ല്': 'ൽ', 'ള്': 'ൾ', 'ണ്': 'ൺ'};

  static String _malayalamChillu(String s) {
    s = s.replaceAll(_mlCons, 'ർ');
    for (final e in _chillu.entries) {
      s = s.replaceAll(RegExp('${e.key}(?=\$|[\\s\u0964\u0965,;.!?)\\]])'), e.value);
    }
    return s;
  }

  static const _virama = '\u094D';
  static const _nukta = '\u093C';

  static String devaToIast(String text) {
    final r = text.runes.map(String.fromCharCode).toList();
    final sb = StringBuffer();
    var i = 0;
    while (i < r.length) {
      final ch = r[i];
      final hasNukta = i + 1 < r.length && r[i + 1] == _nukta && kConsonants.containsKey(ch + _nukta);
      if (kConsonants.containsKey(ch) || hasNukta) {
        String key;
        if (hasNukta) {
          key = ch + _nukta;
          i += 1;
        } else {
          key = ch;
        }
        sb.write(kConsonants[key]);
        final nxt = i + 1 < r.length ? r[i + 1] : '';
        if (nxt == _virama) {
          i += 2;
          continue;
        }
        if (kMatras.containsKey(nxt)) {
          sb.write(kMatras[nxt]);
          i += 2;
          continue;
        }
        sb.write('a');
        i++;
        continue;
      }
      if (kVowels.containsKey(ch)) {
        sb.write(kVowels[ch]);
      } else if (kOther.containsKey(ch)) {
        sb.write(kOther[ch]);
      } else if (kMatras.containsKey(ch)) {
        sb.write(kMatras[ch]);
      } else if (ch == _virama) {
        // dangling virama — drop
      } else {
        sb.write(ch);
      }
      i++;
    }
    return sb.toString();
  }
}
