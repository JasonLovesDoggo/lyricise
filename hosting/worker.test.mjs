import assert from 'node:assert/strict';
import test from 'node:test';
import worker from './worker.mjs';

const request = (path, method = 'GET') => worker.fetch(new Request(`https://lyricise.jsn.cam${path}`, { method }));

test('installer GET and HEAD redirect to the published release', () => {
  for (const method of ['GET', 'HEAD']) {
    const response = request('/install.sh', method);
    assert.equal(response.status, 302);
    assert.equal(response.headers.get('location'), 'https://github.com/JasonLovesDoggo/lyricise/releases/latest/download/install.sh');
  }
});
test('root opens the project; unknown paths and writes do not redirect', () => {
  assert.equal(request('/').headers.get('location'), 'https://github.com/JasonLovesDoggo/lyricise');
  assert.equal(request('/missing').status, 404);
  assert.equal(request('/install.sh', 'POST').status, 405);
});
