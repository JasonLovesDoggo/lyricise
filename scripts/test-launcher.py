#!/usr/bin/env python3
"""Exercise the real launcher over socketpair without launching the app."""
import pathlib
import socket
import subprocess

binary = pathlib.Path(__file__).resolve().parent.parent / 'build/Lyricise.app/Contents/MacOS/LyriciseLauncher'
def response(request):
    client, server = socket.socketpair()
    client.settimeout(5)
    process = subprocess.Popen([str(binary)], stdin=server, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    server.close()
    client.sendall(request.encode())
    client.shutdown(socket.SHUT_WR)
    result = b''
    while True:
        data = client.recv(4096)
        if not data:
            break
        result += data
    client.close()
    process.wait(timeout=5)
    return result.decode().split('\r\n')[0]

cases = [
    ('OPTIONS /launch HTTP/1.1\r\nOrigin: https://xpui.app.spotify.com\r\n\r\n', '200 OK'),
    ('OPTIONS /launch HTTP/1.1\r\nOrigin: https://example.com\r\n\r\n', '403 Forbidden'),
    ('POST /launch HTTP/1.1\r\nContent-Length: 0\r\nAuthorization: Bearer wrong\r\n\r\n', '403 Forbidden'),
    ('GET /launch HTTP/1.1\r\n\r\n', '400 Bad Request'),
    ('POST /other HTTP/1.1\r\nContent-Length: 0\r\n\r\n', '400 Bad Request'),
    ('POST /launch HTTP/1.1\r\nContent-Length: 1025\r\n\r\n', '400 Bad Request'),
    ('POST /launch HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 1\r\n\r\n', '400 Bad Request'),
    ('POST /launch HTTP/1.1\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n', '400 Bad Request'),
]
for request, expected in cases:
    actual = response(request)
    assert actual == 'HTTP/1.1 ' + expected, (actual, expected)
print('Launcher: 8 HTTP authorization, origin, method, and framing checks passed.')
