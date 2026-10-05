#!/usr/bin/env python3
"""Verify bundled installs with temporary files and mocked system commands."""
import contextlib
import io
import os
import unittest
import pathlib
import runpy
import subprocess
import sys
import tempfile
from unittest.mock import patch

script = pathlib.Path(__file__).resolve().parent / 'install-companion.py'
for valid_path, fresh_install in ((False, False), (True, False), (False, True)):
    with tempfile.TemporaryDirectory(prefix='lyricise-companion-test-') as temporary:
        root = pathlib.Path(temporary)
        app = root / 'Lyricise.app'
        resources = app / 'Contents/Resources'
        resources.mkdir(parents=True)
        (resources / 'lyricise.js').write_text("const token = '__LYRICISE_TOKEN__';")
        binary = app / 'Contents/MacOS/LyriciseLauncher'
        binary.parent.mkdir()
        binary.write_text('test launcher')
        binary.chmod(0o700)
        (root / 'Spotify.app/Contents/Resources').mkdir(parents=True)
        spice = root / 'spicetify'
        spice.mkdir()
        ini = spice / 'config-xpui.ini'
        configured_path = str(root) if valid_path else ''
        original = f'[Setting]\nspotify_path = {configured_path}\n[AdditionalOptions]\nextensions = existing.js\n'
        if not fresh_install:
            ini.write_text(original)
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            if command == ['/fake/spicetify', 'config']:
                assert fresh_install and not ini.exists()
                ini.write_text(original)
            if command[-1:] == ['apply'] and 'backup' not in command:
                return subprocess.CompletedProcess(command, 1, 'Please run "spicetify backup apply"')
            return subprocess.CompletedProcess(command, 0, '')
        with patch.object(pathlib.Path, 'home', return_value=root), \
             patch('shutil.which', return_value='/fake/spicetify'), \
             patch('subprocess.check_output', return_value=str(ini)), \
             patch('subprocess.run', side_effect=run), \
             patch.object(sys, 'argv', [str(script), '--app', str(app), '--spotify-app', str(root / 'Spotify.app')]), \
             contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(script), run_name='__main__')
        assert (['/fake/spicetify', 'config'] in calls) == fresh_install
        config = root / '.config/lyricise'
        token = (config / 'bridge-token').read_text()
        assert len(token) == 64
        assert (config / 'bridge-token').stat().st_mode & 0o777 == 0o600
        assert token in (spice / 'Extensions/lyricise.js').read_text()
        assert (config / 'LyriciseLauncher').read_text() == 'test launcher'
        assert next(config.glob('spicetify-backup-*/config-xpui.ini')).read_text() == original
        path_updates = [call for call in calls if call[1:3] == ['config', 'spotify_path']]
        assert bool(path_updates) != valid_path
        assert ['/fake/spicetify', 'config', 'extensions', 'lyricise.js'] in calls
        assert ['/fake/spicetify', 'backup', 'apply'] in calls
print('Bundled companion: token, app resources, backups, Spotify path and first-backup recovery checks passed.')


class PreflightTests(unittest.TestCase):
    def test_invalid_resources_leave_existing_state_untouched(self):
        cases = ('missing-template', 'invalid-template', 'invalid-encoding',
                 'missing-launcher', 'directory-launcher', 'nonexecutable-launcher', 'invalid-spotify')
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                home = pathlib.Path(directory)
                app = home / 'Lyricise.app'
                source = app / 'Contents/Resources/lyricise.js'
                source.parent.mkdir(parents=True)
                source.write_text('token = "__LYRICISE_TOKEN__";')
                launcher = app / 'Contents/MacOS/LyriciseLauncher'
                launcher.parent.mkdir()
                launcher.write_text('#!/bin/sh\nexit 0\n')
                launcher.chmod(0o700)
                config = home / '.config/spicetify/config-xpui.ini'
                config.parent.mkdir(parents=True)
                config.write_text('[Setting]\nspotify_path = old\n[AdditionalOptions]\nextensions = existing.js\n')
                extension = config.parent / 'Extensions/lyricise.js'
                extension.parent.mkdir()
                extension.write_text('existing extension')
                token = home / '.config/lyricise/bridge-token'
                token.parent.mkdir()
                token.write_text('a' * 64)
                token.chmod(0o644)
                bin_path = home / 'bin'
                bin_path.mkdir()
                cli = bin_path / 'spicetify'
                cli.write_text('#!/bin/sh\nprintf invoked >> "$HOME/cli-calls"\n')
                cli.chmod(0o700)
                extra = []
                if case == 'missing-template':
                    source.unlink()
                elif case == 'invalid-template':
                    source.write_text('no placeholder')
                elif case == 'invalid-encoding':
                    source.write_bytes(b'\xff')
                elif case == 'missing-launcher':
                    launcher.unlink()
                elif case == 'directory-launcher':
                    launcher.unlink()
                    launcher.mkdir()
                elif case == 'nonexecutable-launcher':
                    launcher.chmod(0o600)
                elif case == 'invalid-spotify':
                    extra = ['--spotify-app', str(home / 'missing-Spotify.app')]
                before = {p: (p.read_bytes(), p.stat().st_mode) for p in (config, extension, token)}
                result = subprocess.run(
                    [sys.executable, str(script), '--app', str(app), '--no-restart', *extra],
                    env={**os.environ, 'HOME': str(home), 'PATH': str(bin_path) + os.pathsep + os.environ['PATH']},
                    capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('no spotify changes were made', result.stderr.lower())
                self.assertEqual(before, {p: (p.read_bytes(), p.stat().st_mode) for p in before})
                self.assertFalse((home / 'cli-calls').exists())
                self.assertEqual(list(token.parent.iterdir()), [token])
                self.assertFalse((home / 'Library').exists())


if __name__ == '__main__':
    unittest.main()
