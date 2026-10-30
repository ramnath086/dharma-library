import contextlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent.parent


class ExportBundleTests(unittest.TestCase):
    def test_set_role_command_tag_is_not_exported_as_a_work(self):
        """Model psql's real quiet-mode contract without a local DB dependency."""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            script = root / 'scripts/export_bundle.py'
            script.parent.mkdir()
            script.write_bytes((ROOT / 'scripts/export_bundle.py').read_bytes())
            bundle = json.loads((ROOT / 'app/test/fixtures/mini_bhagavata_bundle.json').read_bytes())
            calls = []

            def psql(command, **kwargs):
                calls.append(command)
                quiet = '-qAt' in command
                sql = command[-1]
                prefix = '' if quiet else 'SET\n'
                if 'select slug' in sql:
                    output = 'bhagavata-purana\n'
                elif "get_work_bundle('SET')" in sql:
                    output = json.dumps({'toc': {'work': None}})
                else:
                    output = json.dumps(bundle)
                return subprocess.CompletedProcess(command, 0, stdout=prefix + output, stderr='')

            with patch.object(sys, 'argv', [str(script), '--db', 'postgresql://fixture']), \
                    patch('subprocess.run', side_effect=psql), contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(script), run_name='__main__')
            output = root / 'app/assets/bundles'
            self.assertEqual([p.name for p in output.glob('*.json')], ['bhagavata-purana.json'])
            self.assertEqual(json.loads((output / 'bhagavata-purana.json').read_bytes()), bundle)
            self.assertEqual(len(calls), 2)
            self.assertTrue(all('-qAt' in c for c in calls))
