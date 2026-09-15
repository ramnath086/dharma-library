"""Script conversion utilities for Sanskrit text.

* Devanagari -> IAST (deterministic, lossless for standard Sanskrit)
* Devanagari -> other Brahmic scripts (Malayalam, Kannada, Telugu, Bengali,
  Gujarati, Gurmukhi, Odia, Tamil*) by Unicode block offset with per-script
  exception tables.

*Tamil lacks distinct letters for many Sanskrit consonants; we use Grantha
 letters present in the Tamil block where they exist (ஜ ஶ ஷ ஸ ஹ க்ஷ) and
 fall back to the nearest Tamil letter otherwise. Tamil output is therefore
 flagged `lossy`.

A Dart port of the same tables lives in app/lib/core/translit/.
"""
from __future__ import annotations

DEVA_BASE = 0x0900
BLOCKS = {
    "Mlym": 0x0D00, "Knda": 0x0C80, "Telu": 0x0C00, "Beng": 0x0980,
    "Gujr": 0x0A80, "Guru": 0x0A00, "Orya": 0x0B00, "Taml": 0x0B80,
}

# Devanagari code points that map 1:1 by offset in all target blocks
# (vowels, consonants, matras, virama, anusvara, visarga, candrabindu, digits).
OFFSET_RANGES = [(0x0901, 0x0939), (0x093C, 0x094D), (0x0950, 0x0950), (0x0958, 0x0963), (0x0966, 0x096F)]
# Danda (। ॥ U+0964/5) are shared punctuation and are kept as-is.

# Per-script exceptions: Devanagari char -> replacement string (None = drop).
EXCEPTIONS: dict[str, dict[str, str | None]] = {
    "Mlym": {
        "ॐ": "ഓം", "ऽ": "ഽ", "।": "।", "॥": "॥",
        "ॠ": "ൠ", "ॡ": "ൡ", "ऱ": "റ", "ळ": "ള",
        "\u0929": "ന",           # ऩ
        "क़": "ക", "ख़": "ഖ", "ग़": "ഗ", "ज़": "ജ", "ड़": "ഡ", "ढ़": "ഢ", "फ़": "ഫ", "य़": "യ",
        "\u0945": "െ", "\u0949": "ൊ",  # candra e/o (rare) → short e/o
        "ऍ": "എ", "ऑ": "ഒ",
    },
    "Knda": {"ॐ": "ಓಂ", "ऽ": "ಽ", "ऱ": "ಱ", "ळ": "ಳ", "ॠ": "ೠ", "ॡ": "ೡ", "\u0945": "ೆ", "\u0949": "ೊ", "ऍ": "ಎ", "ऑ": "ಒ",
             "क़": "ಕ", "ख़": "ಖ", "ग़": "ಗ", "ज़": "ಜ", "ड़": "ಡ", "ढ़": "ಢ", "फ़": "ಫ", "य़": "ಯ", "\u0929": "ನ"},
    "Telu": {"ॐ": "ఓం", "ऽ": "ఽ", "ऱ": "ఱ", "ळ": "ళ", "ॠ": "ౠ", "ॡ": "ౡ", "\u0945": "ె", "\u0949": "ొ", "ऍ": "ఎ", "ऑ": "ఒ",
             "क़": "క", "ख़": "ఖ", "ग़": "గ", "ज़": "జ", "ड़": "డ", "ढ़": "ఢ", "फ़": "ఫ", "य़": "య", "\u0929": "న"},
    "Beng": {"ॐ": "ওঁ", "ऽ": "ঽ", "व": "ব", "ळ": "ল", "ऱ": "র", "ॠ": "ৠ", "ॡ": "ৡ",
             # Bengali has no short e/o
             "ऎ": "এ", "ऒ": "ও", "\u0946": "ে", "\u094A": "ো", "\u0945": "ে", "\u0949": "ো", "ऍ": "এ", "ऑ": "ও",
             "ङ": "ঙ", "ञ": "ঞ", "ड़": "ড়", "ढ़": "ঢ়", "य़": "য়", "क़": "ক", "ख़": "খ", "ग़": "গ", "ज़": "জ", "फ़": "ফ", "\u0929": "ন"},
    "Gujr": {"ॐ": "ૐ", "ऽ": "ઽ", "ळ": "ળ", "ऱ": "ર", "ॠ": "ૠ", "ॡ": "ૡ", "ऎ": "એ", "ऒ": "ઓ", "\u0946": "ે", "\u094A": "ો",
             "क़": "ક", "ख़": "ખ", "ग़": "ગ", "ज़": "જ", "ड़": "ડ", "ढ़": "ઢ", "फ़": "ફ", "य़": "ય", "\u0929": "ન"},
    "Guru": {"ॐ": "ੴ", "ऽ": "", "ऋ": "ਰਿ", "ॠ": "ਰੀ", "ऌ": "ਲਿ", "ॡ": "ਲੀ", "\u0943": "੍ਰਿ", "\u0944": "੍ਰੀ", "\u0962": "੍ਲਿ", "\u0963": "੍ਲੀ",
             "ऐ": "ਐ", "औ": "ਔ", "ळ": "ਲ਼", "ऱ": "ਰ", "ऎ": "ਏ", "ऒ": "ਓ", "\u0946": "ੇ", "\u094A": "ੋ", "\u0945": "ੇ", "\u0949": "ੋ",
             "ष": "ਸ਼", "ज्ञ": "ਗਿਆ", "क़": "ਕ਼", "ख़": "ਖ਼", "ग़": "ਗ਼", "ज़": "ਜ਼", "ड़": "ੜ", "ढ़": "ਢ", "फ़": "ਫ਼", "य़": "ਯ", "\u0929": "ਨ",
             "\u0901": "ਁ", "\u0902": "ੰ", "\u0903": "ਃ"},
    "Orya": {"ॐ": "ଓଁ", "ऽ": "ଽ", "व": "ବ", "ळ": "ଳ", "ऱ": "ର", "ॠ": "ୠ", "ॡ": "ୡ", "ऎ": "ଏ", "ऒ": "ଓ", "\u0946": "େ", "\u094A": "ୋ",
             "\u0945": "େ", "\u0949": "ୋ", "क़": "କ", "ख़": "ଖ", "ग़": "ଗ", "ज़": "ଜ", "ड़": "ଡ଼", "ढ़": "ଢ଼", "फ़": "ଫ", "य़": "ୟ", "\u0929": "ନ"},
}

# Tamil: explicit consonant table (Grantha where available, else nearest).
TAMIL = {
    "क": "க", "ख": "க", "ग": "க", "घ": "க", "ङ": "ங",
    "च": "ச", "छ": "ச", "ज": "ஜ", "झ": "ஜ", "ञ": "ஞ",
    "ट": "ட", "ठ": "ட", "ड": "ட", "ढ": "ட", "ण": "ண",
    "त": "த", "थ": "த", "द": "த", "ध": "த", "न": "ந",
    "प": "ப", "फ": "ப", "ब": "ப", "भ": "ப", "म": "ம",
    "य": "ய", "र": "ர", "ल": "ல", "व": "வ", "श": "ஶ", "ष": "ஷ", "स": "ஸ", "ह": "ஹ", "ळ": "ள", "ऱ": "ற",
    "अ": "அ", "आ": "ஆ", "इ": "இ", "ई": "ஈ", "उ": "உ", "ऊ": "ஊ", "ऋ": "ரு", "ॠ": "ரூ", "ऌ": "லு", "ॡ": "லூ",
    "ए": "ஏ", "ऐ": "ஐ", "ओ": "ஓ", "औ": "ஔ", "ऎ": "எ", "ऒ": "ஒ",
    "\u093E": "ா", "\u093F": "ி", "\u0940": "ீ", "\u0941": "ு", "\u0942": "ூ", "\u0943": "்ரு", "\u0944": "்ரூ",
    "\u0947": "ே", "\u0948": "ை", "\u094B": "ோ", "\u094C": "ௌ", "\u0946": "ெ", "\u094A": "ொ", "\u094D": "்",
    "\u0902": "ம்", "\u0901": "ம்", "\u0903": "ஃ", "ॐ": "ௐ", "ऽ": "", "।": "।", "॥": "॥",
    "०": "௦", "१": "௧", "२": "௨", "३": "௩", "४": "௪", "५": "௫", "६": "௬", "७": "௭", "८": "௮", "९": "௯",
}

LOSSY = {"Taml", "Guru"}


def deva_to_script(text: str, script: str) -> str:
    if script == "Deva":
        return text
    if script == "Latn":
        return deva_to_iast(text)
    if script == "Taml":
        return "".join(TAMIL.get(ch, ch) for ch in text)
    base = BLOCKS[script]
    exc = EXCEPTIONS.get(script, {})
    out = []
    i = 0
    while i < len(text):
        # two-char exceptions first (nukta forms, ज्ञ for Gurmukhi)
        two = text[i:i + 2]
        if two in exc:
            out.append(exc[two] or "")
            i += 2
            continue
        ch = text[i]
        if ch in exc:
            out.append(exc[ch] or "")
        else:
            cp = ord(ch)
            if any(lo <= cp <= hi for lo, hi in OFFSET_RANGES):
                out.append(chr(cp - DEVA_BASE + base))
            else:
                out.append(ch)
        i += 1
    res = "".join(out)
    if script == "Mlym":
        res = _malayalam_chillu(res)
    return res


import re as _re
_ML_CONS = "[\u0d15-\u0d3a]"
_CHILLU = {"ന്": "ൻ", "ര്": "ർ", "ല്": "ൽ", "ള്": "ൾ", "ണ്": "ൺ"}


def _malayalam_chillu(s: str) -> str:
    """Use atomic chillu letters where Malayalam orthography expects them:
    r before a consonant (ര്ഗ -> ർഗ) and n/r/l/ḷ/ṇ at word end."""
    s = _re.sub("ര്(?=" + _ML_CONS + ")", "ർ", s)
    for k, v in _CHILLU.items():
        s = _re.sub(k + r"(?=$|[\s\u0964\u0965,;.!?)\]])", v, s)
    return s


# ---------------------------------------------------------------------------
# Devanagari -> IAST
# ---------------------------------------------------------------------------
VOWELS = {"अ": "a", "आ": "ā", "इ": "i", "ई": "ī", "उ": "u", "ऊ": "ū", "ऋ": "ṛ", "ॠ": "ṝ", "ऌ": "ḷ", "ॡ": "ḹ",
          "ए": "e", "ऐ": "ai", "ओ": "o", "औ": "au", "ऎ": "e", "ऒ": "o"}
MATRAS = {"\u093E": "ā", "\u093F": "i", "\u0940": "ī", "\u0941": "u", "\u0942": "ū", "\u0943": "ṛ", "\u0944": "ṝ",
          "\u0962": "ḷ", "\u0963": "ḹ", "\u0947": "e", "\u0948": "ai", "\u094B": "o", "\u094C": "au", "\u0946": "e", "\u094A": "o"}
CONS = {"क": "k", "ख": "kh", "ग": "g", "घ": "gh", "ङ": "ṅ", "च": "c", "छ": "ch", "ज": "j", "झ": "jh", "ञ": "ñ",
        "ट": "ṭ", "ठ": "ṭh", "ड": "ḍ", "ढ": "ḍh", "ण": "ṇ", "त": "t", "थ": "th", "द": "d", "ध": "dh", "न": "n",
        "प": "p", "फ": "ph", "ब": "b", "भ": "bh", "म": "m", "य": "y", "र": "r", "ल": "l", "व": "v",
        "श": "ś", "ष": "ṣ", "स": "s", "ह": "h", "ळ": "ḻ", "ऱ": "ṟ", "ऩ": "ṉ",
        "क़": "q", "ख़": "x", "ग़": "ġ", "ज़": "z", "ड़": "ṛ", "ढ़": "ṛh", "फ़": "f", "य़": "ẏ"}
OTHER = {"\u0902": "ṁ", "\u0901": "m̐", "\u0903": "ḥ", "ॐ": "oṁ", "ऽ": "'", "।": "|", "॥": "||",
         "०": "0", "१": "1", "२": "2", "३": "3", "४": "4", "५": "5", "६": "6", "७": "7", "८": "8", "९": "9"}
VIRAMA = "\u094D"
NUKTA = "\u093C"


def deva_to_iast(text: str) -> str:
    out = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch in CONS or (i + 1 < n and text[i + 1] == NUKTA and ch + NUKTA in CONS):
            if i + 1 < n and text[i + 1] == NUKTA:
                key, i = ch + NUKTA, i + 1
            else:
                key = ch
            out.append(CONS[key])
            nxt = text[i + 1] if i + 1 < n else ""
            if nxt == VIRAMA:
                i += 2
                continue
            if nxt in MATRAS:
                out.append(MATRAS[nxt])
                i += 2
                continue
            # inherent vowel unless followed by end/another explicit marker
            out.append("a")
            i += 1
            continue
        if ch in VOWELS:
            out.append(VOWELS[ch])
        elif ch in OTHER:
            out.append(OTHER[ch])
        elif ch in MATRAS:  # stray matra
            out.append(MATRAS[ch])
        elif ch == VIRAMA:
            pass
        else:
            out.append(ch)
        i += 1
    return "".join(out)


if __name__ == "__main__":
    import sys
    s = sys.argv[1] if len(sys.argv) > 1 else "जन्माद्यस्य यतोऽन्वयादितरतश्चार्थेष्वभिज्ञः स्वराट् ॥ १ ॥"
    print("IAST:", deva_to_iast(s))
    for sc in BLOCKS:
        print(sc + ":", deva_to_script(s, sc))
