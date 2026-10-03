#!/usr/bin/env python3
"""Verify bundled installs with temporary files and mocked system commands."""
import contextlib
import io
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
