const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(__dirname + '/lyricise.js', 'utf8');
const settle = () => new Promise((resolve) => setImmediate(resolve));
function harness(modern = false) {
  const pending = [],
    sent = [],
    events = {},
    commands = [],
    seeks = [],
    timers = {},
    buttons = [],
    toggles = [];
  let commandResponse, toggleResponse, snapshotResponse;
  const launches = [];
  let now = 0;
  const Player = {
    data: { item: { uri: 'spotify:track:A', name: 'Track A', artists: [{ name: 'Artist' }] } },
    getProgress: () => 2000,
    getDuration: () => 100000,
    isPlaying: () => true,
    seek: (position) => seeks.push(position),
    addEventListener: (name, callback) => (events[name] = callback),
  };
  const Spicetify = {
    Player,
    CosmosAsync: {
      get: (url) => new Promise((resolve, reject) => pending.push({ url, resolve, reject })),
    },
  };
  Spicetify.Topbar = {
    Button: class {
      constructor(...args) {
        this.args = args;
        buttons.push(this);
      }
    },
  };
  if (modern) {
    delete Spicetify.CosmosAsync;
    const builder = {
      withHost(host) {
        this.host = host;
        return this;
      },
      withPath(path) {
        this.path = path;
        return this;
      },
      withQueryParameters() {
        return this;
      },
      withEndpointIdentifier() {
        return this;
      },
      send() {
        return new Promise((resolve, reject) =>
          pending.push({
            url: this.host + this.path,
            resolve: (body) => resolve({ body }),
            reject,
          }),
        );
      },
    };
    Spicetify.Platform = { RequestBuilder: { build: () => builder } };
  }
  vm.runInNewContext(source, {
    Spicetify,
    Date: { now: () => now },
    crypto: { randomUUID: () => 'test-session' },
    AbortSignal,
    URL,
    fetch: async (url, init) => {
      if (url.endsWith('/launch')) {
        launches.push({ url, ...init });
        return { ok: true };
      }
      if (url.endsWith('/toggle')) {
        toggles.push({ url, ...init });
        return toggleResponse ? toggleResponse() : { ok: true };
      }
      if (url.endsWith('/command')) {
        if (commandResponse) return commandResponse();
        return { ok: true, json: async () => commands.shift() ?? {} };
      }
      sent.push(JSON.parse(init.body));
      return snapshotResponse ? snapshotResponse() : { ok: true };
    },
    setTimeout,
    setInterval: (callback, delay) => (timers[delay] = callback),
  });
  return {
    advanceTime: (milliseconds) => (now += milliseconds),
    setSnapshotResponse: (callback) => (snapshotResponse = callback),
    launches,
    setToggleResponse: (callback) => (toggleResponse = callback),
    Player,
    pending,
    sent,
    events,
    commands,
    seeks,
    buttons,
    toggles,
    heartbeat: () => timers[1000](),
    poll: () => timers[250](),
    setCommandResponse: (callback) => (commandResponse = callback),
  };
}
test('late response cannot replace current track lyrics; milliseconds and playback retained', async () => {
  const h = harness();
  await settle();
  h.Player.data.item = { uri: 'spotify:track:B', name: 'Track B', artists: [{ name: 'Artist B' }] };
  await h.events.songchange();
  h.pending[1].resolve({
    lyrics: { syncType: 'LINE_SYNCED', lines: [{ startTimeMs: '1500', words: 'B line' }] },
  });
  await settle();
  h.pending[0].resolve({
    lyrics: { syncType: 'LINE_SYNCED', lines: [{ startTimeMs: '1000', words: 'A line' }] },
  });
  await settle();
  await h.heartbeat();
  const last = h.sent.at(-1);
  assert.equal(last.trackID, 'spotify:track:B');
  assert.equal(last.lines[0].text, 'B line');
  assert.equal(last.lines[0].time, 1500);
  assert.equal(last.position, 2000);
  assert.equal(last.artist, 'Artist B');
  assert.equal(last.status, 'ready');
});
test('unsynced lyrics retain null timing; pause and seeks propagate; cached tracks avoid refetch', async () => {
  const h = harness();
  await settle();
  h.pending[0].resolve({ lyrics: { syncType: 'UNSYNCED', lines: [{ words: 'Plain line' }] } });
  await settle();
  h.Player.isPlaying = () => false;
  h.Player.getProgress = () => 42000;
  await h.events.onplaypause();
  assert.equal(h.sent.at(-1).playing, false);
  assert.equal(h.sent.at(-1).position, 42000);
  assert.equal(h.sent.at(-1).lines[0].time, null);
  h.Player.data.item.uri = 'spotify:episode:podcast';
  await h.events.songchange();
  assert.equal(h.sent.at(-1).status, 'unsupported');
  assert.equal(h.sent.at(-1).lines.length, 0);
  h.Player.data.item.uri = 'spotify:track:A';
  await h.events.songchange();
  assert.equal(h.pending.length, 1);
  assert.equal(h.sent.at(-1).status, 'ready');
});
test('missing lyrics, auth failures, and rate limits are distinct', async () => {
  for (const [code, status] of [
    [404, 'unavailable'],
    [401, 'auth_required'],
    [429, 'rate_limited'],
  ]) {
    const h = harness();
    await settle();
    h.pending[0].reject({ status: code });
    await settle();
    await h.heartbeat();
    assert.equal(h.sent.at(-1).status, status);
    assert.equal(h.pending.length, 1);
  }
});

test('Spotify 1.3 RequestBuilder works without CosmosAsync, including syllable sync', async () => {
  const h = harness(true);
  await settle();
  assert.equal(h.pending[0].url, 'https://spclient.wg.spotify.com/color-lyrics/v2/track/A');
  h.pending[0].resolve({
    lyrics: {
      syncType: 'SYLLABLE_SYNCED',
      lines: [{ startTimeMs: '500', words: 'Syllable line' }],
    },
  });
  await settle();
  await h.heartbeat();
  assert.equal(h.sent.at(-1).status, 'ready');
  assert.equal(h.sent.at(-1).lines[0].time, 500);
});
test('malformed or unordered timestamps fall back to consistently unsynced lines', async () => {
  const h = harness(true);
  await settle();
  h.pending[0].resolve({
    lyrics: {
      syncType: 'LINE_SYNCED',
      lines: [
        { startTimeMs: '500', words: 'First' },
        { startTimeMs: 'bad', words: 'Second' },
      ],
    },
  });
  await settle();
  await h.heartbeat();
  assert.deepEqual(
    h.sent.at(-1).lines.map((line) => line.time),
    [null, null],
  );
});

test('authenticated commands seek the matching track once and refresh playback', async () => {
  const h = harness();
  await settle();
  h.commands.push({ id: 'one', trackID: 'spotify:track:A', position: 42000.2 });
  await h.poll();
  await settle();
  assert.deepEqual(h.seeks, [42000]);
  h.commands.push({ id: 'one', trackID: 'spotify:track:A', position: 42000.2 });
  await h.poll();
  assert.equal(h.seeks.length, 1);
  assert.ok(h.sent.length >= 2);
});
test('commands reject wrong tracks and invalid seek positions', async () => {
  const h = harness();
  await settle();
  const invalid = [
    { id: 'wrong-track', trackID: 'spotify:track:B', position: 100 },
    ...[-1, NaN, Infinity, 100001, '100'].map((position, i) => ({
      id: String(i),
      trackID: 'spotify:track:A',
      position,
    })),
  ];
  for (const command of invalid) {
    h.commands.push(command);
    await h.poll();
  }
  assert.deepEqual(h.seeks, []);
});
test('a song change while a command is in flight cannot seek the new song', async () => {
  const h = harness();
  await settle();
  let resolve;
  h.setCommandResponse(() => new Promise((r) => (resolve = r)));
  const poll = h.poll();
  h.Player.data.item.uri = 'spotify:track:B';
  resolve({
    ok: true,
    json: async () => ({ id: 'late', trackID: 'spotify:track:A', position: 100 }),
  });
  await poll;
  assert.deepEqual(h.seeks, []);
});

test('public album artwork normalizes Spotify image URIs and drops query strings', async () => {
  const h = harness();
  await settle();
  const id = 'a'.repeat(40);
  h.Player.data.item.metadata = { image_url: `spotify:image:${id}` };
  await h.heartbeat();
  assert.equal(h.sent.at(-1).artworkURL, `https://i.scdn.co/image/${id}`);
  h.Player.data.item.images = [
    { url: 'https://image-cdn-ak.spotifycdn.com/image/cover123?unused=secret#fragment' },
  ];
  await h.heartbeat();
  assert.equal(h.sent.at(-1).artworkURL, 'https://image-cdn-ak.spotifycdn.com/image/cover123');
});
test('artwork excludes arbitrary hosts, credentials, protocols, and paths', async () => {
  const h = harness();
  await settle();
  for (const url of [
    'https://example.com/image/abc',
    'http://i.scdn.co/image/abc',
    'https://user:password@i.scdn.co/image/abc',
    'https://i.scdn.co/private/abc',
    'https://i.scdn.co:8443/image/abc',
  ]) {
    h.Player.data.item.images = [{ url }];
    await h.heartbeat();
    assert.equal(h.sent.at(-1).artworkURL, undefined);
  }
});

test('one accessible left topbar button toggles the authenticated local app', async () => {
  const h = harness();
  await settle();
  await h.heartbeat();
  assert.equal(h.buttons.length, 1);
  const button = h.buttons[0];
  assert.equal(button.args[0], 'Toggle Lyricise');
  assert.equal(button.args[4], false);
  await button.args[2]();
  assert.equal(h.toggles.length, 1);
  assert.equal(h.toggles[0].method, 'POST');
  assert.equal(h.toggles[0].headers.Authorization, 'Bearer __LYRICISE_TOKEN__');
  assert.equal(button.disabled, false);
  assert.deepEqual(h.seeks, []);
});

test('Spotify button launches Lyricise when the local app is stopped', async () => {
  const h = harness();
  await settle();
  h.setToggleResponse(() => {
    throw new TypeError('Connection refused');
  });
  await h.buttons[0].args[2]();
  assert.equal(h.launches.length, 1);
  assert.equal(h.launches[0].url, 'http://127.0.0.1:17390/launch');
  assert.equal(h.launches[0].headers.Authorization, 'Bearer __LYRICISE_TOKEN__');
  assert.equal(h.buttons[0].disabled, false);
});
test('a running app bridge rejection does not launch another instance', async () => {
  const h = harness();
  await settle();
  h.setToggleResponse(() => ({ ok: false }));
  await h.buttons[0].args[2]();
  assert.deepEqual(h.launches, []);
});

test('background transport failures never launch the stopped app', async () => {
  const h = harness();
  await settle();
  h.setSnapshotResponse(() => {
    throw new TypeError('Connection refused');
  });
  h.setCommandResponse(() => {
    throw new TypeError('Connection refused');
  });
  await h.heartbeat();
  await h.poll();
  await h.heartbeat();
  assert.deepEqual(h.launches, []);
});

test('transient lyric failures back off, cap retries, and reset for a new track', async () => {
  const h = harness();
  await settle();
  for (const delay of [10000, 20000, 40000, 80000, 160000, 300000, 300000]) {
    const requestsBeforeRetry = h.pending.length;
    h.pending.at(-1).reject({ status: 500 });
    await settle();
    h.advanceTime(delay - 1);
    await h.heartbeat();
    assert.equal(h.pending.length, requestsBeforeRetry);
    h.advanceTime(1);
    await h.heartbeat();
    assert.equal(h.pending.length, requestsBeforeRetry + 1);
  }
  h.Player.data.item.uri = 'spotify:track:B';
  await h.events.songchange();
  h.pending.at(-1).reject({ status: 429 });
  await settle();
  const requestsBeforeRetry = h.pending.length;
  h.advanceTime(59999);
  await h.heartbeat();
  assert.equal(h.pending.length, requestsBeforeRetry);
  h.advanceTime(1);
  await h.heartbeat();
  assert.equal(h.pending.length, requestsBeforeRetry + 1);
});
