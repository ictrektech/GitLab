#!/usr/bin/env python3
"""Prevent unsafe PGV parameter changes without contacting a real Docker daemon."""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('check_pgv', Path(__file__).parents[1] / 'scripts/check_pgv.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CapacityTests(unittest.TestCase):
    def setUp(self):
        build = Path.home() / 'dev/build/gitlab/config-check-tests'
        build.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=build)
        self.addCleanup(self.temporary.cleanup)
        self.current = {'max_connections': '100', 'shared_buffers': '128MB',
                        'shared_buffers_bytes': 134217728, 'max_locks_per_transaction': '64'}
        self.statements = []
        self.restarts = []

    def docker_output(self, command, **kwargs):
        if command[1] == 'ps':
            return 'vos-app-com-ictrek-pgv-fixture-ictrek-pgv-amd-1\n'
        if command[1] == 'inspect':
            return json.dumps([{'Config': {'Env': ['POSTGRES_PASSWORD=fixture-only', 'POSTGRES_USER=postgres']}}])
        sql = kwargs['input']
        if sql.startswith('SELECT json_build_object'):
            return json.dumps(self.current)
        if sql.startswith('ALTER SYSTEM'):
            self.statements.append(sql)
            return ''
        return '1'

    def invoke(self, *arguments):
        with patch.object(module.subprocess, 'check_output', side_effect=self.docker_output), \
                patch.object(module.subprocess, 'run', side_effect=lambda *args, **kwargs: self.restarts.append(args)), \
                patch.object(module.Path, 'home', return_value=Path(self.temporary.name)), \
                patch.object(module.sys, 'argv', ['check_pgv.py', *arguments]), \
                contextlib.redirect_stdout(io.StringIO()):
            return module.main()

    def test_check_is_read_only(self):
        self.assertEqual(self.invoke(), 2)
        self.assertEqual(self.statements, [])
        self.assertEqual(self.restarts, [])

    def test_apply_uses_explicit_memory_units_and_preserves_original_settings(self):
        self.assertEqual(self.invoke('--apply-and-restart'), 0)
        self.assertIn("ALTER SYSTEM SET shared_buffers = '2GB';", self.statements)
        self.assertIn("ALTER SYSTEM SET max_connections = '400';", self.statements)
        backup = Path(self.temporary.name) / 'dev/build/gitlab/pgv-config-backup.json'
        self.assertEqual(json.loads(backup.read_text()), self.current)
        self.assertEqual(len(self.restarts), 1)

    def test_apply_never_lowers_existing_capacity(self):
        self.current.update(max_connections='800', shared_buffers='4GB', shared_buffers_bytes=4 * 1024**3)
        self.invoke('--apply-and-restart')
        self.assertIn("ALTER SYSTEM SET max_connections = '800';", self.statements)
        self.assertIn("ALTER SYSTEM SET shared_buffers = '4GB';", self.statements)

    def test_restore_uses_the_saved_parameters(self):
        self.invoke('--apply-and-restart')
        self.statements.clear()
        self.invoke('--restore-and-restart')
        self.assertIn("ALTER SYSTEM SET max_connections = '100';", self.statements)
        self.assertIn("ALTER SYSTEM SET shared_buffers = '128MB';", self.statements)


if __name__ == '__main__':
    unittest.main(verbosity=2)
