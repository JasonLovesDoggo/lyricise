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


def load_resources(app, spotify_app):
    root = pathlib.Path(__file__).resolve().parent.parent
    # Resolve and validate bundle resources before changing local or Spotify settings.
    source_path = app / 'Contents/Resources/lyricise.js' if app else root / 'companion/lyricise.js'
    try:
        source = source_path.read_text()
    except (OSError, UnicodeError) as error:
        raise SystemExit(f'Cannot read the companion template: {error}. No Spotify changes were made.')
    if source.count('__LYRICISE_TOKEN__') != 1:
        raise SystemExit('Companion template is invalid; no Spotify changes were made.')
    launcher_source = (app if app else root / 'build/Lyricise.app') / 'Contents/MacOS/LyriciseLauncher'
    if not launcher_source.exists() and not app:
        launcher_source = pathlib.Path.home() / 'Applications/Lyricise.app/Contents/MacOS/LyriciseLauncher'
    if not launcher_source.is_file() or not os.access(launcher_source, os.R_OK | os.X_OK):
        raise SystemExit('The launch helper is missing or not executable. Build or reinstall Lyricise first; no Spotify changes were made.')
    if spotify_app and not (spotify_app / 'Contents/Resources').is_dir():
        raise SystemExit('Spotify.app is missing Contents/Resources; no Spotify changes were made.')
    return source, launcher_source


def bridge_token(config):
    token_file = config / 'bridge-token'
    if not token_file.exists():
        fd = os.open(str(token_file), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write(secrets.token_hex(32))
    token_file.chmod(0o600)
    token = token_file.read_text().strip()
    if not re.fullmatch('[a-fA-F0-9]{64}', token):
        raise SystemExit('The Lyricise bridge token is invalid; no Spotify changes were made.')
    return token


def configure_spotify(cli, config_path, spotify_app):
    if spotify_app:
        existing = configparser.ConfigParser(interpolation=None, strict=False)
        existing.read(config_path)
        spotify_path = existing.get('Setting', 'spotify_path', fallback='').strip()
        if not spotify_path or not pathlib.Path(spotify_path).expanduser().is_dir():
            subprocess.run([cli, 'config', 'spotify_path', str(spotify_app / 'Contents/Resources')], check=True)


def install_files(config, config_path, source, launcher_source):
    spice = config_path.parent
    backup = pathlib.Path(tempfile.mkdtemp(prefix='spicetify-backup-' + datetime.datetime.now().strftime('%Y%m%d-'), dir=config))
    shutil.copy2(config_path, backup / 'config-xpui.ini')
    extension = spice / 'Extensions/lyricise.js'
    if extension.exists():
        shutil.copy2(extension, backup / 'lyricise.js')
    extension.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=extension.parent, prefix='.lyricise-')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(source)
        os.replace(temporary, extension)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    launcher = config / 'LyriciseLauncher'
    if launcher.exists():
        shutil.copy2(launcher, backup / 'LyriciseLauncher')
    shutil.copy2(launcher_source, launcher)
    launcher.chmod(0o700)
    return launcher, backup


def activate_launcher(launcher, backup):
    label = 'cam.jsn.lyricise.launcher'
    plist = pathlib.Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    plist.parent.mkdir(parents=True, exist_ok=True)
    if plist.exists():
        shutil.copy2(plist, backup / plist.name)
    subprocess.run(
        ['/bin/launchctl', 'bootout', 'gui/' + str(os.getuid()) + '/' + label],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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


def apply_spotify(cli, no_restart, backup):
    subprocess.run([cli, 'config', 'extensions', 'lyricise.js'], check=True)
    command = [cli, *(['--no-restart'] if no_restart else [])]
    result = subprocess.run(command + ['apply'], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end='')
    if result.returncode and 'Please run \"spicetify backup apply\"' in result.stdout:
        # Spotify updated itself; let Spicetify create a matching stock backup.
        subprocess.run(command + ['backup', 'apply'], check=True)
    elif result.returncode:
        raise SystemExit('Spicetify apply failed. Configuration backup: ' + str(backup))
    print('Lyricise companion installed. Original configuration saved at ' + str(backup))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-restart', action='store_true', help='Apply without restarting Spotify')
    parser.add_argument('--app', type=pathlib.Path, help='Use a prebuilt Lyricise.app bundle')
    parser.add_argument('--spotify-app', type=pathlib.Path, help='Spotify.app location for first-time setup')
    args = parser.parse_args()
    source, launcher_source = load_resources(args.app, args.spotify_app)
    cli = shutil.which('spicetify') or next(
        (p for p in ['/opt/homebrew/bin/spicetify', '/usr/local/bin/spicetify'] if os.path.isfile(p)), None)
    if not cli:
        raise SystemExit('Install Spicetify first: brew install spicetify-cli')
    config = pathlib.Path.home() / '.config/lyricise'
    config.mkdir(parents=True, exist_ok=True)
    token = bridge_token(config)
    config_path = pathlib.Path(subprocess.check_output([cli, '-c'], text=True).strip())
    # -c prints the intended path without creating a first-run configuration.
    if not config_path.exists():
        subprocess.run([cli, 'config'], check=True, stdout=subprocess.DEVNULL)
        if not config_path.is_file():
            raise SystemExit(f'Spicetify did not create its configuration at {config_path}. Run spicetify once, then retry.')
    launcher, backup = install_files(
        config, config_path, source.replace('__LYRICISE_TOKEN__', token), launcher_source)
    configure_spotify(cli, config_path, args.spotify_app)
    activate_launcher(launcher, backup)
    apply_spotify(cli, args.no_restart, backup)


if __name__ == '__main__':
    main()
