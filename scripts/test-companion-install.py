#!/usr/bin/env python3
"""Exercise installer preflight without touching Spotify or launchd."""
import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('install-companion.py')


class PreflightTests(unittest.TestCase):
    def test_invalid_resources_leave_existing_state_untouched(self):
        cases = ('missing-template', 'invalid-template', 'unreadable-template',
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
                elif case == 'unreadable-template':
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
                    ['python3', str(SCRIPT), '--app', str(app), '--no-restart', *extra],
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
