#!/usr/bin/env python3
"""Parse sacred-texts markdown files to build Swarupananda mapping.

Reads /tmp/sacred_texts/sbg*_c*.md (or content/bhagavad-gita/sacred_cache/*.md)
and extracts verses using the shruti VERSE_PATTERN.

Outputs /tmp/swarupananda_mapping.json and also scripts/swarupananda_mapping.json
for the generator to use.
"""
import re, json, pathlib, glob, collections

# Pattern from shruti fetch_translation.py: r"^(\d+)(?:-(\d+))?\.\s+(.*)"
VERSE_PATTERN = re.compile(r"^(\d+)(?:-(\d+))?\.\s+(.*)")

# Map sbg file to chapter: sbg06 -> ch1, so ch = sbg -5
def sbg_to_ch(sbg_num):
    return sbg_num - 5

# Find markdown files
patterns = ["/tmp/sacred_texts/*.md", "content/bhagavad-gita/sacred_cache/*.md", "/tmp/sacred_*.md"]
files = []
for pat in patterns:
    files.extend(glob.glob(pat))

if not files:
    print("No markdown files found, checked", patterns)
    # also try /tmp/sacred_texts/sbg*.md
    print("listing /tmp/sacred_texts", list(pathlib.Path("/tmp/sacred_texts").glob("*")) if pathlib.Path("/tmp/sacred_texts").exists() else "no dir")

mapping = collections.defaultdict(dict)  # ch -> vnum -> text
for f in sorted(files):
    text = pathlib.Path(f).read_text(encoding="utf-8")
    # Try to infer sbg number from filename
    # e.g., sbg06_c0.md -> 6, sbg08.md -> 8
    m = re.search(r"sbg(\d+)", pathlib.Path(f).name)
    if not m:
        print(f"Skipping {f}, cannot infer sbg")
        continue
    sbg = int(m.group(1))
    ch = sbg_to_ch(sbg)
    if not (1 <= ch <= 18):
        print(f"Skipping {f}, ch {ch} out of range")
        continue
    # Parse lines
    # The markdown has lines like "1\. Tell me..." or "4-6. \"Here..."
    # Need to clean the escaped dot: fetch_page markdown escapes dot as "\."
    # So pattern should handle both "\." and "."
    # We'll normalize: replace "\." with "."
    normalized = text.replace("\\.", ".")
    lines = normalized.splitlines()
    # Also need to handle ftfy? For now simple
    for line in lines:
        line=line.strip()
        # Skip empty, headers, etc.
        if not line:
            continue
        # Match verse pattern at start of line
        # The markdown may have "1. Tell me..." at start
        # Use VERSE_PATTERN on the line
        mm = VERSE_PATTERN.match(line)
        if mm:
            start = int(mm.group(1))
            end = int(mm.group(2)) if mm.group(2) else start
            verse_text = mm.group(3).strip()
            # Clean: remove footnote markers like " [1]" etc. but keep main text
            # Remove trailing footnote links like " [1](url)" – keep text before
            # The verse_text may contain " [1](https...)" at end; remove it
            verse_text = re.sub(r"\s*\[\d+\]\(https://sacred-texts\.com[^\)]+\)", "", verse_text)
            # Also remove trailing " [4]" etc.
            # For range verses, the same text applies to each verse in range
            for vnum in range(start, end+1):
                # Only set if not already set (first occurrence wins)
                if vnum not in mapping[ch]:
                    mapping[ch][vnum] = verse_text
                    # print(f"ch{ch} v{vnum} -> {verse_text[:60]}")
                else:
                    # If already exists, keep first (chunk0) as it is likely the main
                    pass
    print(f"Parsed {f} -> ch{ch}, now has {len(mapping[ch])} verses")

# Also try to parse combined content from previous fetch_page logs if available?
# For now, output
out = {str(ch): {str(v): txt for v, txt in sorted(vmap.items())} for ch, vmap in mapping.items()}
# Ensure all 18 ch present
for ch in range(1,19):
    if str(ch) not in out:
        out[str(ch)] = {}
    print(f"ch{ch}: {len(out[str(ch)])} verses")

# Write to /tmp
import json as js
pathlib.Path("/tmp/swarupananda_mapping.json").write_text(js.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
pathlib.Path("scripts/swarupananda_mapping.json").write_text(js.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
print("Wrote /tmp/swarupananda_mapping.json and scripts/swarupananda_mapping.json")
# Print sample
for ch in [1,2,3]:
    print(f"Sample ch{ch}:", list(out[str(ch)].items())[:3])
