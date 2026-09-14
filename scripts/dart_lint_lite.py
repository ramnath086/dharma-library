#!/usr/bin/env python3
"""Very small static sanity pass for the Flutter app when the Dart SDK is not
available locally: balanced brackets per file, imports resolve to existing
files (relative imports), and l10n keys used via `l.<key>` exist in app_en.arb
and app_ml.arb. CI runs the real `flutter analyze`; this only catches gross
mistakes early."""
import json, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / 'app'
errs = []

en = json.loads((APP / 'l10n/app_en.arb').read_text())
ml = json.loads((APP / 'l10n/app_ml.arb').read_text())
en_keys = {k for k in en if not k.startswith('@')}
ml_keys = {k for k in ml if not k.startswith('@')}
for k in en_keys - ml_keys: errs.append(f'l10n: key {k} missing in app_ml.arb')
for k in ml_keys - en_keys: errs.append(f'l10n: key {k} missing in app_en.arb')
# placeholders match
for k in en_keys & ml_keys:
    pe = set(re.findall(r'\{(\w+)', en[k])); pm = set(re.findall(r'\{(\w+)', ml[k]))
    if pe != pm: errs.append(f'l10n: placeholders differ for {k}: en={pe} ml={pm}')

def strip_strings(src):
    src = re.sub(r"'''.*?'''", "''", src, flags=re.S)
    src = re.sub(r'"""(.*?)"""', '""', src, flags=re.S)
    src = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r'//.*', '', src)
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    return src

for f in sorted(APP.rglob('*.dart')):
    if 'generated' in f.parts: continue
    src = f.read_text()
    code = strip_strings(src)
    for o, c in (('(', ')'), ('{', '}'), ('[', ']')):
        if code.count(o) != code.count(c):
            errs.append(f'{f.relative_to(ROOT)}: unbalanced {o}{c} ({code.count(o)} vs {code.count(c)})')
    for m in re.finditer(r"import '((?:\.\./|\./)[^']+)'", src):
        target = (f.parent / m.group(1)).resolve()
        if not target.exists() and 'generated' not in m.group(1):
            errs.append(f'{f.relative_to(ROOT)}: import not found {m.group(1)}')
    for m in re.finditer(r'\bl\.(\w+)', src):
        k = m.group(1)
        if k not in en_keys: errs.append(f'{f.relative_to(ROOT)}: unknown l10n key l.{k}')

if errs:
    print('\n'.join(errs)); sys.exit(1)
print('dart-lint-lite: ok')
