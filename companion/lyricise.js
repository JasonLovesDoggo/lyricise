// Lyricise companion: only normalized playback and lyrics are sent to localhost.
(async function lyricise() {
  const BRIDGE_URL = 'http://127.0.0.1:17389';
  const LAUNCHER_URL = 'http://127.0.0.1:17390';
  const LYRICS_URL = 'https://spclient.wg.spotify.com/color-lyrics/v2';
  const TRACK_URI = /^spotify:track:[A-Za-z0-9]+$/;
  const STARTUP_POLL_MS = 500;
  const HEARTBEAT_MS = 1_000;
  const COMMAND_POLL_MS = 250;
  const COMMAND_RETRY_MS = 1_000;
  const BRIDGE_TIMEOUT_MS = 2_000;
  const LAUNCH_TIMEOUT_MS = 4_000;
  const LYRICS_TIMEOUT_MS = 10_000;
  const ERROR_RETRY_MS = 10_000;
  const RATE_LIMIT_RETRY_MS = 60_000;
  const MAX_RETRY_MS = 300_000;
  const MAX_CACHED_TRACKS = 20;
  const MAX_REMEMBERED_COMMANDS = 100;

  // Keep payload bounds aligned with LyriciseCore's snapshot validation.
  const MAX_POSITION_MS = 86_400_000; // One day, exclusive.
  const MAX_LYRIC_LINES = 5_000;
  const MAX_LINE_LENGTH = 10_000;
  const MAX_TRACK_ID_LENGTH = 200;
  const MAX_METADATA_LENGTH = 2_000;
  const MAX_COMMAND_ID_LENGTH = 100;

  while (!globalThis.Spicetify?.Player?.data) {
    await new Promise((resolve) => setTimeout(resolve, STARTUP_POLL_MS));
  }
  const token = '__LYRICISE_TOKEN__';
  const session = crypto.randomUUID();
  let sequence = 0;
  let generation = 0;
  let currentTrackURI = '';
  let lines = [];
  let status = 'idle';
  let snapshotBusy = false;
  let lyricsRetryAt = Infinity;
  let retryAttempts = 0;
  const cache = new Map();
  let toggleButton;
  let toggleBusy = false;
  function installToggleButton() {
    if (toggleButton || !Spicetify.Topbar?.Button) return;
    const icon =
      '<svg width="16" height="16" viewBox="0 0 32 32" aria-hidden="true"><g fill="none" stroke="#cdd6f4" stroke-width="3" stroke-linecap="round"><path d="M10 8h12M10 24h12" opacity=".45"/><path d="M5 16h22" stroke="#b4befe"/></g></svg>';
    toggleButton = new Spicetify.Topbar.Button('Toggle Lyricise', icon, toggleWindow, false, false);
  }

  async function launchWindow() {
    // Only an explicit button click can contact the socket-activated launcher.
    try {
      const response = await fetch(`${LAUNCHER_URL}/launch`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: '{}',
        signal: AbortSignal.timeout(LAUNCH_TIMEOUT_MS),
      });
      if (!response.ok) throw new Error('Launcher unavailable');
    } catch {
      Spicetify.showNotification?.(
        'Could not open Lyricise. Reinstall the companion to reconnect.',
        true,
      );
    }
  }

  async function toggleWindow() {
    if (toggleBusy) return;
    toggleBusy = true;
    toggleButton.disabled = true;
    try {
      const response = await fetch(`${BRIDGE_URL}/toggle`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: '{}',
        signal: AbortSignal.timeout(BRIDGE_TIMEOUT_MS),
      });
      if (!response.ok) {
        Spicetify.showNotification?.(
          'Lyricise could not accept the toggle. Reinstall the companion to reconnect.',
          true,
        );
      }
    } catch {
      await launchWindow();
    } finally {
      toggleBusy = false;
      toggleButton.disabled = false;
    }
  }
  installToggleButton();
  function milliseconds(value) {
    if (!Number.isFinite(value)) return 0;
    return Math.max(0, Math.min(MAX_POSITION_MS - 1, value));
  }
  function artworkURL(item) {
    const candidates = [
      ...(Array.isArray(item?.images) ? item.images.map((image) => image?.url) : []),
      ...(Array.isArray(item?.album?.images) ? item.album.images.map((image) => image?.url) : []),
      item?.metadata?.image_url,
      item?.metadata?.image_small_url,
      item?.metadata?.image_large_url,
    ];
    for (const candidate of candidates) {
      if (typeof candidate !== 'string') continue;
      const imageID = /^spotify:image:([a-fA-F0-9]{40})$/.exec(candidate)?.[1];
      if (imageID) return `https://i.scdn.co/image/${imageID}`;
      try {
        const url = new URL(candidate);
        if (
          url.protocol === 'https:' &&
          !url.username &&
          !url.password &&
          !url.port &&
          ['i.scdn.co', 'image-cdn-ak.spotifycdn.com', 'image-cdn-fa.spotifycdn.com'].includes(
            url.hostname,
          ) &&
          /^\/image\/[a-zA-Z0-9]+$/.test(url.pathname)
        ) {
          // Cover images are public. Never forward query strings or credentials.
          return url.origin + url.pathname;
        }
      } catch {
        /* Skip unavailable or non-public artwork. */
      }
    }
  }
  async function fetchLyrics(trackID) {
    let timeout;
    const deadline = new Promise((resolve, reject) => {
      timeout = setTimeout(
        () => reject(new Error('Spotify lyrics request timed out')),
        LYRICS_TIMEOUT_MS,
      );
    });
    try {
      // Neither provider API exposes a shared cancellation contract. Racing leaves
      // late results observed but unable to change lyrics or the retry state.
      return await Promise.race([requestLyrics(trackID), deadline]);
    } finally {
      clearTimeout(timeout);
    }
  }

  async function requestLyrics(trackID) {
    // Spotify 1.3+ uses RequestBuilder; it owns authentication and refresh.
    if (Spicetify.Platform?.RequestBuilder) {
      const response = await Spicetify.Platform.RequestBuilder.build()
        .withHost(LYRICS_URL)
        .withPath(`/track/${trackID}`)
        .withQueryParameters({ format: 'json', vocalRemoval: false })
        .withEndpointIdentifier('/track/{trackId}')
        .send();
      return response?.body?.lyrics;
    }
    const response = await Spicetify.CosmosAsync.get(
      `${LYRICS_URL}/track/${trackID}?format=json&vocalRemoval=false&market=from_token`,
    );
    return response?.lyrics;
  }

  function normalizeLyrics(lyrics) {
    const rawLines = Array.isArray(lyrics?.lines) ? lyrics.lines : [];
    const synced = ['LINE_SYNCED', 'SYLLABLE_SYNCED'].includes(lyrics?.syncType);
    const timed =
      synced &&
      rawLines.every((line, index) => {
        const time = Number(line.startTimeMs);
        const previousTime = index === 0 ? 0 : Number(rawLines[index - 1].startTimeMs);
        return Number.isFinite(time) && time >= 0 && time < MAX_POSITION_MS && time >= previousTime;
      });
    return rawLines.slice(0, MAX_LYRIC_LINES).map((line, id) => ({
      id,
      time: timed ? milliseconds(Number(line.startTimeMs)) : null,
      text: String(line.words ?? '').slice(0, MAX_LINE_LENGTH),
    }));
  }

  function failureStatus(error) {
    const httpStatus = Number(error?.status ?? error?.response?.status ?? error?.code);
    switch (httpStatus) {
      case 401:
      case 403:
        return 'auth_required';
      case 429:
        return 'rate_limited';
      case 404:
        return 'unavailable';
      default:
        return 'error';
    }
  }

  async function loadLyrics(uri, retry = false) {
    const ticket = ++generation;
    currentTrackURI = uri;
    lines = [];
    lyricsRetryAt = Infinity;
    if (!retry) retryAttempts = 0;
    status = TRACK_URI.test(uri) ? 'loading' : 'unsupported';
    if (status !== 'loading') return;
    if (cache.has(uri)) {
      ({ lines, status } = cache.get(uri));
      return;
    }
    try {
      const trackID = uri.split(':')[2];
      const lyrics = await fetchLyrics(trackID);
      if (ticket !== generation) return;
      lines = normalizeLyrics(lyrics);
      status = lines.length ? 'ready' : 'unavailable';
      cache.set(uri, { lines, status });
      if (cache.size > MAX_CACHED_TRACKS) cache.delete(cache.keys().next().value);
    } catch (error) {
      if (ticket !== generation) return;
      status = failureStatus(error);
      if (status === 'error' || status === 'rate_limited') {
        const initialDelay = status === 'rate_limited' ? RATE_LIMIT_RETRY_MS : ERROR_RETRY_MS;
        const delay = Math.min(MAX_RETRY_MS, initialDelay * 2 ** retryAttempts);
        retryAttempts += 1;
        lyricsRetryAt = Date.now() + delay;
      }
    }
    // Deliver lyrics immediately after the response, without waiting for a heartbeat.
    void sendSnapshot();
  }

  function playbackSnapshot(item, uri) {
    return {
      artworkURL: artworkURL(item),
      trackID: uri.slice(0, MAX_TRACK_ID_LENGTH),
      title: String(item?.name ?? '').slice(0, MAX_METADATA_LENGTH),
      artist: (item?.artists ?? [])
        .map((artist) => artist.name)
        .join(', ')
        .slice(0, MAX_METADATA_LENGTH),
      position: milliseconds(Spicetify.Player.getProgress()),
      duration: milliseconds(Spicetify.Player.getDuration()),
      playing: Boolean(Spicetify.Player.isPlaying()),
      status: uri ? status : 'idle',
      lines,
      provider: 'Spotify',
      sequence: ++sequence,
      session,
    };
  }

  async function sendSnapshot() {
    installToggleButton();
    const item = Spicetify.Player.data?.item;
    const uri = item?.uri ?? '';
    if (uri !== currentTrackURI) void loadLyrics(uri);
    else if (Date.now() >= lyricsRetryAt) void loadLyrics(uri, true);
    if (snapshotBusy) return;
    snapshotBusy = true;
    try {
      const response = await fetch(`${BRIDGE_URL}/snapshot`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify(playbackSnapshot(item, uri)),
        signal: AbortSignal.timeout(BRIDGE_TIMEOUT_MS),
      });
      if (!response.ok) console.warn('Lyricise bridge rejected snapshot:', response.status);
    } catch {
      /* The app may be closed. The next heartbeat retries. */
    } finally {
      snapshotBusy = false;
    }
  }
  let commandBusy = false;
  let commandRetryAt = 0;
  const handledCommands = new Set();
  async function pollCommand() {
    if (commandBusy || Date.now() < commandRetryAt) return;
    commandBusy = true;
    try {
      const response = await fetch(`${BRIDGE_URL}/command`, {
        headers: { Authorization: `Bearer ${token}` },
        signal: AbortSignal.timeout(BRIDGE_TIMEOUT_MS),
      });
      if (!response.ok) throw new Error('Bridge unavailable');
      const command = await response.json();
      if (
        !command ||
        typeof command.id !== 'string' ||
        !command.id ||
        command.id.length > MAX_COMMAND_ID_LENGTH ||
        handledCommands.has(command.id)
      )
        return;
      handledCommands.add(command.id);
      if (handledCommands.size > MAX_REMEMBERED_COMMANDS)
        handledCommands.delete(handledCommands.values().next().value);
      // Recheck after awaiting HTTP: a delayed command must never seek a new song.
      const uri = Spicetify.Player.data?.item?.uri;
      const duration = Spicetify.Player.getDuration();
      if (
        command.trackID !== uri ||
        !TRACK_URI.test(uri ?? '') ||
        !Number.isFinite(command.position) ||
        command.position < 0 ||
        command.position >= MAX_POSITION_MS ||
        !Number.isFinite(duration) ||
        duration <= 0 ||
        command.position > duration
      )
        return;
      // Player.seek interprets fractional values below one as a percentage.
      Spicetify.Player.seek(Math.round(command.position));
      void sendSnapshot();
    } catch {
      commandRetryAt = Date.now() + COMMAND_RETRY_MS;
    } finally {
      commandBusy = false;
    }
  }
  setInterval(pollCommand, COMMAND_POLL_MS);
  void pollCommand();
  Spicetify.Player.addEventListener('songchange', sendSnapshot);
  Spicetify.Player.addEventListener('onplaypause', sendSnapshot);
  setInterval(sendSnapshot, HEARTBEAT_MS);
  void sendSnapshot();
})();
