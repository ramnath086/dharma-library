import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import prepare_offline_assets as assets


class OfflineAssetsTests(unittest.TestCase):
    def test_complete_corpus_is_lossless_and_each_runtime_asset_is_bounded(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            catalog = assets.prepare(output=output)
            counts = {}
            for work in catalog['works']:
                original = json.loads((assets.SOURCE / f"{work['slug']}.json").read_bytes())
                rebuilt = json.loads((output / Path(work['metadata_asset']).name).read_bytes())
                rebuilt['sections'] = [json.loads((output / Path(p).name).read_bytes()) for p in work['sections']]
                # Exact object equality includes every source/provenance/rights,
                # scripture, translation and word-meaning value, not just counts.
                self.assertEqual(rebuilt, original)
                counts[work['slug']] = (work['section_count'], work['verse_count'], work['index_count'])
            self.assertEqual(counts, {
                'bhagavata-purana': (335, 14105, 98765),
                'bhagavad-gita': (18, 700, 6300),
            })
            self.assertTrue(all(p.stat().st_size <= assets.MAX_PART_BYTES for p in output.glob('*.json')))

    def test_generation_is_deterministic_and_removes_obsolete_generated_parts(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            assets.prepare(output=output)
            before = {p.name: p.read_bytes() for p in output.glob('*.json')}
            (output / 'obsolete.json').write_text('{}')
            assets.prepare(output=output)
            self.assertEqual(before, {p.name: p.read_bytes() for p in output.glob('*.json')})

    def test_release_archive_verification_rejects_missing_or_changed_runtime_data(self):
        # Small fixture so archive plumbing does not duplicate the full corpus.
        fixture = assets.ROOT / 'app/test/fixtures/mini_bhagavata_bundle.json'
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'source'
            source.mkdir()
            (source / 'bhagavata-purana.json').write_bytes(fixture.read_bytes())
            expected = dict(assets.derived_assets(source))
            for extension, prefix in [('.apk', 'assets/flutter_assets/'), ('.aab', 'base/assets/flutter_assets/')]:
                archive = Path(temp) / f'app{extension}'
                for corruption in [None, 'missing', 'changed']:
                    with zipfile.ZipFile(archive, 'w') as z:
                        for i, (name, data) in enumerate(expected.items()):
                            if i == 0 and corruption == 'missing':
                                continue
                            if i == 0 and corruption == 'changed':
                                data = b'{}'
                            z.writestr(f'{prefix}assets/offline_parts/{name}', data)
                    if corruption:
                        with self.assertRaises((KeyError, AssertionError)):
                            assets.verify_archive(archive, source)
                    else:
                        assets.verify_archive(archive, source)

    def test_oversized_chapters_fail_generation_instead_of_shipping_oom_risk(self):
        fixture = json.loads((assets.ROOT / 'app/test/fixtures/mini_bhagavata_bundle.json').read_bytes())
        fixture['sections'][0]['test_padding'] = 'x' * assets.MAX_PART_BYTES
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'source'
            source.mkdir()
            (source / 'bhagavata-purana.json').write_bytes(assets.encode(fixture))
            with self.assertRaises(ValueError):
                assets.prepare(source=source, output=Path(temp) / 'output')
