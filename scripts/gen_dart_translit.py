#!/usr/bin/env python3
"""Regenerate app/lib/core/translit/tables.g.dart from scripts/translit.py (single source of truth)."""
import sys, json, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
import translit as T  # noqa: E402


def dmap(d):
    items = []
    for k, v in d.items():
        ks = json.dumps(k, ensure_ascii=False)
        vs = 'null' if v is None else json.dumps(v, ensure_ascii=False)
        items.append(f"  {ks}: {vs},")
    return "{\n" + "\n".join(items) + "\n}"


nl = chr(10)
out = f'''// GENERATED from scripts/translit.py — do not edit by hand.
// Regenerate with: python3 scripts/gen_dart_translit.py
// ignore_for_file: prefer_single_quotes, lines_longer_than_80_chars

const int kDevaBase = 0x{T.DEVA_BASE:04X};

const Map<String, int> kBlocks = {{
{nl.join(f'  "{k}": 0x{v:04X},' for k, v in T.BLOCKS.items())}
}};

const List<List<int>> kOffsetRanges = [
{nl.join(f'  [0x{a:04X}, 0x{b:04X}],' for a, b in T.OFFSET_RANGES)}
];

const Map<String, Map<String, String?>> kExceptions = {{
{nl.join(f'  "{k}": {dmap(v)},' for k, v in T.EXCEPTIONS.items())}
}};

const Map<String, String> kTamil = {dmap(T.TAMIL)};

const Set<String> kLossyScripts = {{{", ".join(json.dumps(s) for s in sorted(T.LOSSY))}}};

const Map<String, String> kVowels = {dmap(T.VOWELS)};
const Map<String, String> kMatras = {dmap(T.MATRAS)};
const Map<String, String> kConsonants = {dmap(T.CONS)};
const Map<String, String> kOther = {dmap(T.OTHER)};
'''
(ROOT / 'app/lib/core/translit/tables.g.dart').write_text(out)
print('wrote app/lib/core/translit/tables.g.dart')
