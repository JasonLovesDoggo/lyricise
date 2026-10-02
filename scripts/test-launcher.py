#!/usr/bin/env python3
"""Exercise the real launcher over socketpair without launching the app."""
import pathlib
import socket
import subprocess
import sys
import tempfile

binary = pathlib.Path(__file__).resolve().parent.parent / 'build/Lyricise.app/Contents/MacOS/LyriciseLauncher'
def response(request, command=None, timeout=5):
    """Return the HTTP status only after the launcher exits successfully."""
    client, server = socket.socketpair()
    # A file avoids blocking the child if diagnostic output fills a pipe while
    # this thread reads the socket. All failure paths close sockets and reap it.
    with client, server, tempfile.TemporaryFile() as errors:
        client.settimeout(timeout)
        process = subprocess.Popen(
            command or [str(binary)], stdin=server,
            stdout=subprocess.DEVNULL, stderr=errors,
        )
        server.close()
        try:
            client.sendall(request.encode())
            client.shutdown(socket.SHUT_WR)
            result = bytearray()
            while True:
                data = client.recv(4096)
                if not data:
                    break
                result.extend(data)
            process.wait(timeout=timeout)
            errors.seek(0)
            diagnostics = errors.read().decode(errors='replace')
            if process.returncode != 0:
                raise subprocess.CalledProcessError(
                    process.returncode, process.args,
                    output=bytes(result), stderr=diagnostics,
                )
            return result.decode().split('\r\n')[0]
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()


def check_harness_failures():
    # Even a valid-looking response must not hide an unsuccessful child exit.
    responder = (
        'import socket, sys, time; '
        'peer = socket.socket(fileno=0); peer.recv(4096); '
        'peer.sendall(b"HTTP/1.1 200 OK\\r\\n\\r\\n"); '
        'peer.shutdown(socket.SHUT_WR); '
    )
    try:
        response('request', [sys.executable, '-c', responder + 'sys.exit(7)'])
    except subprocess.CalledProcessError as error:
        assert error.returncode == 7
    else:
        raise AssertionError('Harness accepted a failed launcher')

    try:
        response('request', [sys.executable, '-c', responder + 'time.sleep(5)'], timeout=0.2)
    except (subprocess.TimeoutExpired, socket.timeout):
        pass
    else:
        raise AssertionError('Harness accepted a launcher that never exited')


cases = [
    ('OPTIONS /launch HTTP/1.1\r\nOrigin: https://xpui.app.spotify.com\r\n\r\n', '200 OK'),
    ('OPTIONS /launch HTTP/1.1\r\nOrigin: https://example.com\r\n\r\n', '403 Forbidden'),
    ('POST /launch HTTP/1.1\r\nContent-Length: 0\r\nAuthorization: Bearer wrong\r\n\r\n', '403 Forbidden'),
    ('GET /launch HTTP/1.1\r\n\r\n', '400 Bad Request'),
    ('POST /launch HTTP/1.1\r\nMalformed header\r\n\r\n', '400 Bad Request'),
    ('POST /launch HTTP/1.1\r\nContent-Length: -1\r\n\r\n', '400 Bad Request'),
    ('POST /launch HTTP/1.1\r\nContent-Length: 0\r\ncontent-length: 0\r\n\r\n', '400 Bad Request'),
    ('x' * 8192, '413 Payload Too Large'),
    ('POST /other HTTP/1.1\r\nContent-Length: 0\r\n\r\n', '400 Bad Request'),
    ('POST /launch HTTP/1.1\r\nContent-Length: 1025\r\n\r\n', '400 Bad Request'),
    ('POST /launch HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 1\r\n\r\n', '400 Bad Request'),
    ('POST /launch HTTP/1.1\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n', '400 Bad Request'),
]
check_harness_failures()
for request, expected in cases:
    actual = response(request)
    assert actual == 'HTTP/1.1 ' + expected, (actual, expected)
print(f'Launcher: {len(cases)} HTTP checks and 2 harness failure checks passed.')
