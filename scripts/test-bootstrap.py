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

if ready.returncode == 0:
    # All operations stop before touching ~/Applications. Unexpected progress is
    # rejected by the mkdir guard, rather than touching the real installation.
    fake_download = '''while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; output=$1; fi
  shift
done
if [[ "$output" == */checksum ]]; then
  shasum -a 256 "${output%/*}/Lyricise-macos-arm64.zip" > "$output"
else
  echo fixture > "$output"
fi'''
    fake_extract = '''/bin/mkdir -p "$4/Lyricise.app/Contents/MacOS" "$4/Lyricise.app/Contents/Resources"
/usr/bin/touch "$4/install-companion.py" "$4/Lyricise.app/Contents/Resources/lyricise.js"
printf '#!/bin/bash\\n' > "$4/Lyricise.app/Contents/MacOS/Lyricise"
/bin/cp "$4/Lyricise.app/Contents/MacOS/Lyricise" "$4/Lyricise.app/Contents/MacOS/LyriciseLauncher"
/bin/chmod +x "$4/Lyricise.app/Contents/MacOS/"*'''
    safe_commands = {
        'curl': fake_download,
        'ditto': fake_extract,
        'codesign': 'exit 0',
        'mkdir': 'echo "UNEXPECTED INSTALLATION" >&2; exit 99',
        'brew': 'echo "UNEXPECTED BREW" >&2; exit 98',
    }
    cases = [
        ({'ditto': 'exit 23'}, 23),
        ({'codesign': 'exit 24'}, 24),
        ({'ditto': 'exit 0'}, 1),  # Missing bundle resources.
        ({'brew': 'if [ "$1" = list ]; then exit 1; fi; exit 25'}, 25),
        ({'brew': 'if [ "$1" = list ]; then exit 0; fi; exit 26'}, 26),
        ({'brew': '''if [ "$1" = list ]; then exit 0; fi
if [ "$#" = 2 ]; then echo /fake/python; exit 0; fi
exit 27'''}, 27),  # Failed prefix lookup must not be hidden by export.
    ]
    for commands, expected_status in cases:
        result = run('--yes', commands={**safe_commands, **commands})
        assert result.returncode == expected_status, result
        assert 'UNEXPECTED' not in result.stderr, result
        assert 'Installed.' not in result.stdout, result
    result = run('--yes', commands={**safe_commands, 'curl': 'kill -TERM "$PPID"; exit 0'})
    assert result.returncode == 143, result
    print('Extraction, incomplete bundle, signature, dependency, prefix and interruption failures stop safely.')

# The README must not execute a partial download, even if curl already wrote data.
readme = installer.parent.parent / 'README.md'
install_command = readme.read_text().split('```sh\n', 1)[1].split('```', 1)[0]
with tempfile.TemporaryDirectory(prefix='lyricise-readme-test-') as temporary:
    directory = Path(temporary)
    curl = directory / 'curl'
    curl.write_text('''#!/bin/bash
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; output=$1; fi
  shift
done
printf 'echo PARTIAL_SCRIPT_EXECUTED\\n' > "$output"
exit 22
''')
    curl.chmod(0o755)
    result = subprocess.run(['/bin/bash', '-c', install_command], text=True,
                            capture_output=True, env={**os.environ,
                            'PATH': f'{directory}:{os.environ["PATH"]}', 'TMPDIR': str(directory)})
    assert result.returncode == 22, result
    assert 'PARTIAL_SCRIPT_EXECUTED' not in result.stdout, result
    assert list(directory.iterdir()) == [curl], list(directory.iterdir())
print('README download failure preserves exit status, never executes partial data, and cleans up.')
