#!/usr/bin/env python3
"""Exercise installer preflight and failed downloads without touching the user's install."""
import os
from pathlib import Path
import subprocess
import tempfile

installer = Path(__file__).resolve().parent / 'bootstrap.sh'

def run(*args, commands=None):
    with tempfile.TemporaryDirectory(prefix='lyricise-installer-test-') as temporary:
        directory = Path(temporary)
        for name, body in (commands or {}).items():
            file = directory / name
            file.write_text('#!/bin/bash\n' + body + '\n')
            file.chmod(0o755)
        env = {**os.environ, 'PATH': f'{directory}:{os.environ["PATH"]}', 'TMPDIR': str(directory)}
        result = subprocess.run(['/bin/bash', str(installer), *args], env=env,
                                text=True, capture_output=True)
        leftovers = list(directory.glob('lyricise-install.*'))
        assert not leftovers, leftovers
        return result

assert run('--help').returncode == 0
assert run('--unknown').returncode != 0
result = run('--check', commands={'uname': 'echo Linux'})
assert result.returncode != 0 and 'requires macOS' in result.stderr
result = run('--check', commands={'uname': 'if [ "$1" = -s ]; then echo Darwin; else echo x86_64; fi'})
assert result.returncode != 0 and 'Apple silicon' in result.stderr
result = run('--check', commands={'sw_vers': 'echo 26.0'})
assert result.returncode != 0 and 'macOS 27' in result.stderr
result = run('--check', commands={'id': 'echo 0'})
assert result.returncode != 0 and 'without sudo' in result.stderr

# The remaining checks run on a supported Mac with Spotify and Homebrew installed.
ready = run('--check')
if ready.returncode:
    print('Platform preflight checks passed; download tests skipped:', ready.stderr.strip())
else:
    assert 'No changes made' in ready.stdout
    result = run('--yes', commands={'curl': 'exit 22'})
    assert result.returncode != 0
    result = run('--yes', commands={'curl': '''while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; output=$1; fi
  shift
done
if [[ "$output" == */checksum ]]; then
  printf '%064d\n' 0 > "$output"
else
  echo corrupt > "$output"
fi'''})
    assert result.returncode != 0 and 'checksum mismatch' in result.stderr, result
    print('Installer help, preflight, download failure, checksum rejection and cleanup checks passed.')
