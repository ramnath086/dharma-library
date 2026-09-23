import sys, pathlib, unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import translit as T


class TranslitTests(unittest.TestCase):
    def test_iast(self):
        self.assertEqual(T.deva_to_iast('कृष्णः'), 'kṛṣṇaḥ')
        self.assertEqual(T.deva_to_iast('ॐ नमो भगवते वासुदेवाय ॥ १ ॥'), 'oṁ namo bhagavate vāsudevāya || 1 ||')
        self.assertEqual(T.deva_to_iast('ऋषय ऊचुः'), 'ṛṣaya ūcuḥ')

    def test_malayalam(self):
        self.assertEqual(T.deva_to_script('निरस्तकुहकं सत्यं परं', 'Mlym'), 'നിരസ്തകുഹകം സത്യം പരം')
        self.assertEqual(T.deva_to_script('त्रिसर्गोऽमृषा', 'Mlym'), 'ത്രിസർഗോഽമൃഷാ')

    def test_other_scripts_no_devanagari_left(self):
        src = 'धाम्ना स्वेन सदा निरस्तकुहकं सत्यं परं धीमहि ॥ १ ॥'
        for sc in T.BLOCKS:
            out = T.deva_to_script(src, sc)
            self.assertFalse(any('\u0900' <= ch <= '\u0963' or '\u0966' <= ch <= '\u097f' for ch in out), (sc, out))

    def test_dart_tables_in_sync(self):
        import subprocess
        root = pathlib.Path(__file__).resolve().parent.parent.parent
        before = (root / 'app/lib/core/translit/tables.g.dart').read_text(encoding='utf-8')
        subprocess.run([sys.executable, str(root / 'scripts/gen_dart_translit.py')], check=True, capture_output=True)
        after = (root / 'app/lib/core/translit/tables.g.dart').read_text(encoding='utf-8')
        self.assertEqual(before, after, 'run scripts/gen_dart_translit.py and commit')


class IngestTests(unittest.TestCase):
    def test_pilot_content_shape(self):
        import json
        root = pathlib.Path(__file__).resolve().parent.parent.parent
        d = json.loads((root / 'content/bhagavata-purana/1/1/verses.json').read_text(encoding='utf-8'))
        refs = [v['ref'] for v in d['verses']]
        self.assertGreaterEqual(len(refs), 10)
        self.assertEqual(refs[:10], [f'1.1.{i}' for i in range(1, 11)])
        for v in d['verses'][:10]:
            for k in ('deva', 'iast', 'en', 'ml', 'word_meanings'):
                self.assertTrue(v.get(k), f"{v['ref']} missing {k}")
        w = json.loads((root / 'content/bhagavata-purana/work.json').read_text(encoding='utf-8'))
        keys = {r['key'] for r in w['rights']}
        for e in w['editions']:
            self.assertIn(e['rights'], keys, f"edition {e['slug']} has no rights")
            self.assertTrue(e.get('source'), f"edition {e['slug']} has no source")


if __name__ == '__main__':
    unittest.main()
