#!/usr/bin/env python3
"""Install the local bridge, preserving existing Spicetify customizations."""
import argparse
import configparser
import datetime
import os
import pathlib
import plistlib
import re
import secrets
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--no-restart', action='store_true', help='Apply without restarting Spotify')
parser.add_argument('--app', type=pathlib.Path, help='Use a prebuilt Lyricise.app bundle')
parser.add_argument('--spotify-app', type=pathlib.Path, help='Spotify.app location for first-time setup')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
config = pathlib.Path.home() / '.config/lyricise'
config.mkdir(parents=True, exist_ok=True)
token_file = config / 'bridge-token'
if not token_file.exists():
    fd = os.open(str(token_file), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w') as f:
        f.write(secrets.token_hex(32))
token_file.chmod(0o600)
token = token_file.read_text().strip()
if not re.fullmatch('[a-fA-F0-9]{64}', token):
    raise SystemExit('The Lyricise bridge token is invalid; no Spotify changes were made.')
cli = shutil.which('spicetify') or next((p for p in ['/opt/homebrew/bin/spicetify', '/usr/local/bin/spicetify'] if os.path.isfile(p)), None)
if not cli:
    raise SystemExit('Install Spicetify first: brew install spicetify-cli')
config_path = pathlib.Path(subprocess.check_output([cli, '-c'], text=True).strip())
spice = config_path.parent
backup = pathlib.Path(tempfile.mkdtemp(prefix='spicetify-backup-' + datetime.datetime.now().strftime('%Y%m%d-'), dir=config))
shutil.copy2(config_path, backup / 'config-xpui.ini')
if args.spotify_app:
    existing = configparser.ConfigParser(interpolation=None, strict=False)
    existing.read(config_path)
    spotify_path = existing.get('Setting', 'spotify_path', fallback='').strip()
    if not spotify_path or not pathlib.Path(spotify_path).expanduser().is_dir():
        subprocess.run([cli, 'config', 'spotify_path', str(args.spotify_app / 'Contents/Resources')], check=True)
extension = spice / 'Extensions/lyricise.js'
if extension.exists():
    shutil.copy2(extension, backup / 'lyricise.js')
extension.parent.mkdir(parents=True, exist_ok=True)
source_path = args.app / 'Contents/Resources/lyricise.js' if args.app else root / 'companion/lyricise.js'
source = source_path.read_text()
if source.count('__LYRICISE_TOKEN__') != 1:
    raise SystemExit('Companion template is invalid; no Spotify changes were made.')
fd, temporary = tempfile.mkstemp(dir=extension.parent, prefix='.lyricise-')
try:
    with os.fdopen(fd, 'w') as f:
        f.write(source.replace('__LYRICISE_TOKEN__', token))
    os.replace(temporary, extension)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
# launchd keeps only a loopback socket open; the helper has no idle process.
launcher_source = (args.app if args.app else root / 'build/Lyricise.app') / 'Contents/MacOS/LyriciseLauncher'
if not launcher_source.exists():
    launcher_source = pathlib.Path.home() / 'Applications/Lyricise.app/Contents/MacOS/LyriciseLauncher'
if not launcher_source.exists():
    raise SystemExit('Build Lyricise first (scripts/build.sh) to install the launch helper.')
launcher = config / 'LyriciseLauncher'
if launcher.exists():
    shutil.copy2(launcher, backup / 'LyriciseLauncher')
shutil.copy2(launcher_source, launcher)
launcher.chmod(0o700)
label = 'cam.jsn.lyricise.launcher'
plist = pathlib.Path.home() / 'Library/LaunchAgents' / (label + '.plist')
plist.parent.mkdir(parents=True, exist_ok=True)
if plist.exists():
    shutil.copy2(plist, backup / plist.name)
subprocess.run(['/bin/launchctl', 'bootout', 'gui/' + str(os.getuid()) + '/' + label], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
settings = {
    'Label': label, 'ProgramArguments': [str(launcher)],
    'InetdCompatibility': {'Wait': False}, 'ThrottleInterval': 0,
    'Sockets': {'Listener': {'SockType': 'stream', 'SockFamily': 'IPv4', 'SockNodeName': '127.0.0.1', 'SockServiceName': '17390'}},
    'ProcessType': 'Background', 'ExitTimeOut': 5,
}
with plist.open('wb') as f:
    plistlib.dump(settings, f)
plist.chmod(0o600)
subprocess.run(['/bin/launchctl', 'bootstrap', 'gui/' + str(os.getuid()), str(plist)], check=True)
subprocess.run([cli, 'config', 'extensions', 'lyricise.js'], check=True)
command = [cli, *(['--no-restart'] if args.no_restart else [])]
result = subprocess.run(command + ['apply'], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
print(result.stdout, end='')
if result.returncode and 'Please run \"spicetify backup apply\"' in result.stdout:
    # Spotify updated itself; let Spicetify create a matching stock backup.
    subprocess.run(command + ['backup', 'apply'], check=True)
elif result.returncode:
    raise SystemExit('Spicetify apply failed. Configuration backup: ' + str(backup))
print('Lyricise companion installed. Original configuration saved at ' + str(backup))
