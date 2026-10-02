// Lyricise companion: only normalized playback and lyrics are sent to localhost.
(async function lyricise() {
  while (!globalThis.Spicetify?.Player?.data) {
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  const token = '__LYRICISE_TOKEN__';
  const session = crypto.randomUUID();
  let sequence = 0, generation = 0, current = '', lines = [], status = 'idle';
  let busy = false, retryAt = Infinity, attempts = 0;
  const cache = new Map();
  let toggleButton, toggleBusy = false;
  function installToggleButton() {
    if (toggleButton || !Spicetify.Topbar?.Button) return;
    const icon = '<svg width="16" height="16" viewBox="0 0 32 32" aria-hidden="true"><g fill="none" stroke="#cdd6f4" stroke-width="3" stroke-linecap="round"><path d="M10 8h12M10 24h12" opacity=".45"/><path d="M5 16h22" stroke="#b4befe"/></g></svg>';
    toggleButton = new Spicetify.Topbar.Button('Toggle Lyricise', icon, async () => {
      if (toggleBusy) return;
      toggleBusy = true; toggleButton.disabled = true;
      try {
        const response = await fetch('http://127.0.0.1:17389/toggle', {
          method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: '{}', signal: AbortSignal.timeout(2000)
        });
        if (!response.ok) Spicetify.showNotification?.('Lyricise could not accept the toggle. Reinstall the companion to reconnect.', true);
      } catch {
        // Only an explicit button click can contact the socket-activated launcher.
        try {
          const response = await fetch('http://127.0.0.1:17390/launch', {
            method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: '{}', signal: AbortSignal.timeout(4000)
          });
          if (!response.ok) throw new Error('Launcher unavailable');
        } catch {
          Spicetify.showNotification?.('Could not open Lyricise. Reinstall the companion to reconnect.', true);
        }
      } finally { toggleBusy = false; toggleButton.disabled = false; }
    }, false, false);
  }
  installToggleButton();
  const milliseconds = value => Number.isFinite(value) ? Math.max(0, Math.min(86_399_999, value)) : 0;
  function artworkURL(item) {
    const candidates = [
      ...(Array.isArray(item?.images) ? item.images.map(image => image?.url) : []),
      ...(Array.isArray(item?.album?.images) ? item.album.images.map(image => image?.url) : []),
      item?.metadata?.image_url, item?.metadata?.image_small_url, item?.metadata?.image_large_url
    ];
    for (const candidate of candidates) {
      if (typeof candidate !== 'string') continue;
      const imageID = /^spotify:image:([a-fA-F0-9]{40})$/.exec(candidate)?.[1];
      if (imageID) return `https://i.scdn.co/image/${imageID}`;
      try {
        const url = new URL(candidate);
        if (url.protocol === 'https:' && !url.username && !url.password && !url.port &&
            ['i.scdn.co', 'image-cdn-ak.spotifycdn.com', 'image-cdn-fa.spotifycdn.com'].includes(url.hostname) &&
            /^\/image\/[a-zA-Z0-9]+$/.test(url.pathname)) {
          // Cover images are public. Never forward query strings or credentials.
          return url.origin + url.pathname;
        }
      } catch { /* Skip unavailable or non-public artwork. */ }
    }
  }
  async function load(uri, retry = false) {
    const ticket = ++generation;
    current = uri; lines = []; retryAt = Infinity;
    if (!retry) attempts = 0;
    status = /^spotify:track:[A-Za-z0-9]+$/.test(uri) ? 'loading' : 'unsupported';
    if (status !== 'loading') return;
    if (cache.has(uri)) {
      ({ lines, status } = cache.get(uri));
      return;
    }
    try {
      const id = uri.split(':')[2];
      // Spotify 1.3+ uses RequestBuilder; it owns authentication and refresh.
      let body;
      if (Spicetify.Platform?.RequestBuilder) {
        const response = await Spicetify.Platform.RequestBuilder.build()
          .withHost('https://spclient.wg.spotify.com/color-lyrics/v2')
          .withPath(`/track/${id}`)
          .withQueryParameters({ format: 'json', vocalRemoval: false })
          .withEndpointIdentifier('/track/{trackId}').send();
        body = response?.body;
      } else {
        body = await Spicetify.CosmosAsync.get(`https://spclient.wg.spotify.com/color-lyrics/v2/track/${id}?format=json&vocalRemoval=false&market=from_token`);
      }
      if (ticket !== generation) return;
      const lyrics = body?.lyrics;
      const raw = Array.isArray(lyrics?.lines) ? lyrics.lines : [];
      const timed = ['LINE_SYNCED', 'SYLLABLE_SYNCED'].includes(lyrics?.syncType) && raw.every((line, index) => Number.isFinite(Number(line.startTimeMs)) && Number(line.startTimeMs) >= 0 && Number(line.startTimeMs) < 86400000 && (index === 0 || Number(line.startTimeMs) >= Number(raw[index - 1].startTimeMs)));
      lines = (Array.isArray(lyrics?.lines) ? lyrics.lines : []).slice(0, 5000).map((line, id) => ({
        id, time: timed ? milliseconds(Number(line.startTimeMs)) : null,
        text: String(line.words ?? '').slice(0, 10000)
      }));
      status = lines.length ? 'ready' : 'unavailable';
      cache.set(uri, { lines, status });
      if (cache.size > 20) cache.delete(cache.keys().next().value);
    } catch (error) {
      if (ticket !== generation) return;
      const code = Number(error?.status ?? error?.response?.status ?? error?.code);
      status = code === 401 || code === 403 ? 'auth_required' : code === 429 ? 'rate_limited' : code === 404 ? 'unavailable' : 'error';
      if (status === 'error' || status === 'rate_limited') {
        retryAt = Date.now() + Math.min(300000, (status === 'rate_limited' ? 60000 : 10000) * 2 ** attempts++);
      }
    }
    // Deliver lyrics immediately after the response, without waiting for a heartbeat.
    void send();
  }
  async function send() {
    installToggleButton();
    const item = Spicetify.Player.data?.item;
    const uri = item?.uri ?? '';
    if (uri !== current) void load(uri);
    else if (Date.now() >= retryAt) void load(uri, true);
    if (busy) return;
    busy = true;
    try {
      const response = await fetch('http://127.0.0.1:17389/snapshot', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          artworkURL: artworkURL(item), trackID: uri.slice(0, 200), title: String(item?.name ?? '').slice(0, 2000),
          artist: (item?.artists ?? []).map(a => a.name).join(', ').slice(0, 2000),
          position: milliseconds(Spicetify.Player.getProgress()), duration: milliseconds(Spicetify.Player.getDuration()),
          playing: Boolean(Spicetify.Player.isPlaying()), status: uri ? status : 'idle', lines,
          provider: 'Spotify', sequence: ++sequence, session
        }),
        signal: AbortSignal.timeout(2000)
      });
      if (!response.ok) console.warn('Lyricise bridge rejected snapshot:', response.status);
    } catch { /* The app may be closed. The next heartbeat retries. */ }
    finally { busy = false; }
  }
  let commandBusy = false, commandRetryAt = 0;
  const handledCommands = new Set();
  async function pollCommand() {
    if (commandBusy || Date.now() < commandRetryAt) return;
    commandBusy = true;
    try {
      const response = await fetch('http://127.0.0.1:17389/command', {
        headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(2000)
      });
      if (!response.ok) throw new Error('Bridge unavailable');
      const command = await response.json();
      if (!command || typeof command.id !== 'string' || !command.id || command.id.length > 100 || handledCommands.has(command.id)) return;
      handledCommands.add(command.id);
      if (handledCommands.size > 100) handledCommands.delete(handledCommands.values().next().value);
      // Recheck after awaiting HTTP: a delayed command must never seek a new song.
      const uri = Spicetify.Player.data?.item?.uri;
      const duration = Spicetify.Player.getDuration();
      if (command.trackID !== uri || !/^spotify:track:[A-Za-z0-9]+$/.test(uri ?? '') ||
          !Number.isFinite(command.position) || command.position < 0 || command.position >= 86_400_000 ||
          !Number.isFinite(duration) || duration <= 0 || command.position > duration) return;
      // Player.seek interprets fractional values below one as a percentage.
      Spicetify.Player.seek(Math.round(command.position));
      void send();
    } catch { commandRetryAt = Date.now() + 1000; }
    finally { commandBusy = false; }
  }
  setInterval(pollCommand, 250);
  void pollCommand();
  Spicetify.Player.addEventListener('songchange', send);
  Spicetify.Player.addEventListener('onplaypause', send);
  setInterval(send, 1000);
  void send();
})();
