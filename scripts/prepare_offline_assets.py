#!/usr/bin/env python3
"""Derive bounded runtime assets without changing the canonical bundles.

Run before Flutter test/run/build. Output is ignored, deterministic, and must
never be edited as content. --verify-archive checks the actual APK/AAB parts
against the canonical JSON, including every rendering and provenance field.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'app/assets/bundles'
OUTPUT = ROOT / 'app/assets/offline_parts'
MAX_PART_BYTES = 1024 * 1024


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')


def derived_assets(source=SOURCE):
    works = []
    for path in sorted(source.glob('*.json')):
        if path.stem in ('manifest', 'catalog'):
            continue
        original = path.read_bytes()
        bundle = json.loads(original)
        if not isinstance(bundle.get('toc', {}).get('work'), dict):
            raise ValueError(f'Bundle has no published work: {path}')
        slug = bundle['toc']['work']['slug']
        if slug != path.stem:
            raise ValueError(f'Bundle slug does not match filename: {path}')
        sections = bundle.pop('sections')
        paths = []
        verses = index_rows = 0
        for i, section in enumerate(sections):
            name = f'{slug}-{i:04d}.json'
            paths.append(f'assets/offline_parts/{name}')
            verses += len(section['verses'])
            index_rows += sum(len(v.get('renderings', [])) for v in section['verses'])
            yield name, encode(section)
        metadata = f'{slug}-metadata.json'
        yield metadata, encode(bundle)
        works.append({
            'slug': slug, 'generated_at': bundle['generated_at'],
            'source_sha256': hashlib.sha256(original).hexdigest(),
            'metadata_asset': f'assets/offline_parts/{metadata}',
            'sections': paths, 'section_count': len(sections),
            'verse_count': verses, 'index_count': index_rows,
        })
    if not works:
        raise ValueError('No offline bundles found')
    yield 'catalog.json', encode({'format_version': 1, 'works': works})


def prepare(source=SOURCE, output=OUTPUT):
    output.mkdir(parents=True, exist_ok=True)
    written = set()
    for name, data in derived_assets(source):
        if len(data) > MAX_PART_BYTES:
            raise ValueError(f'{name}: {len(data)} bytes exceeds bounded asset limit')
        (output / name).write_bytes(data)
        written.add(name)
    # Remove obsolete generated files only, never canonical content.
    for path in output.glob('*.json'):
        if path.name not in written:
            path.unlink()
    return json.loads((output / 'catalog.json').read_bytes())


def verify_archive(archive, source=SOURCE):
    with zipfile.ZipFile(archive) as z:
        prefix = ('base/assets/flutter_assets/' if str(archive).endswith('.aab')
                  else 'assets/flutter_assets/')
        for name, data in derived_assets(source):
            assert len(data) <= MAX_PART_BYTES, f'Oversized part: {name}'
            actual = z.read(f'{prefix}assets/offline_parts/{name}')
            assert actual == data, f'Missing/stale/changed runtime content: {name}'
        catalog = json.loads(z.read(f'{prefix}assets/offline_parts/catalog.json'))
    return catalog


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-archive', type=Path)
    args = parser.parse_args()
    catalog = verify_archive(args.verify_archive) if args.verify_archive else prepare()
    for work in catalog['works']:
        print(f"{work['slug']}: {work['section_count']} chapters / "
              f"{work['verse_count']} verses / {work['index_count']} indexed renderings verified")


if __name__ == '__main__':
    main()
