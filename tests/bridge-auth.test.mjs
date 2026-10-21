import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../apps/bridge/server.mjs', import.meta.url));

function launch(tokenFile, port = 0, token = '') {
  const child = spawn(process.execPath, [script], {
    env: { ...process.env, CHAOS_CAT_PORT: String(port), CHAOS_CAT_HOST: '127.0.0.1',
      CHAOS_CAT_BRIDGE_TOKEN_FILE: tokenFile, CHAOS_CAT_BRIDGE_TOKEN: token },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stderr.on('data', chunk => { output += chunk; });
  const ready = new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', code => reject(new Error(`bridge exited ${code}: ${output}`)));
    child.stdout.on('data', chunk => {
      output += chunk;
      const match = output.match(/running at http:\/\/localhost:(\d+)/);
      if (match) resolve(Number(match[1]));
    });
  });
  return { child, ready };
}

async function stop(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  const exited = once(child, 'exit');
  child.kill();
  await exited;
}

function upgrade(port, headers = {}, query = '') {
  return new Promise((resolve, reject) => {
    const request = http.request({ hostname: '127.0.0.1', port, path: '/ws' + query,
      headers: { Connection: 'Upgrade', Upgrade: 'websocket',
        'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': 'dGhlIHNhbXBsZSBub25jZQ==', ...headers } });
    request.on('upgrade', (response, socket) => resolve({ status: response.statusCode, socket }));
    request.on('response', response => { response.resume(); resolve({ status: response.statusCode }); });
    request.on('error', reject);
    request.setTimeout(2000, () => request.destroy(new Error('WebSocket upgrade timeout')));
    request.end();
  });
}

test('bridge authenticates HTTP and WebSocket clients across restart and duplicate launch', { timeout: 15000 }, async t => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'chaos-cat-auth-test-'));
  const tokenFile = path.join(directory, 'bridge.token');
  const children = [];
  t.after(async () => {
    await Promise.all(children.map(stop));
    await fs.rm(directory, { recursive: true, force: true });
  });
  const server = launch(tokenFile);
  children.push(server.child);
  const port = await server.ready;
  const base = `http://127.0.0.1:${port}`;
  const token = (await fs.readFile(tokenFile, 'utf8')).trim();
  assert.match(token, /^[a-f0-9]{64}$/);
  assert.equal((await fs.stat(tokenFile)).mode & 0o777, 0o600);
  const auth = { 'x-chaos-cat-token': token };

  for (const endpoint of ['/api/health', '/api/events']) {
    for (const headers of [{}, { 'x-chaos-cat-token': 'invalid' }]) {
      const response = await fetch(base + endpoint, { headers });
      assert.equal(response.status, 401);
      assert.equal(response.headers.get('access-control-allow-origin'), null);
      await response.arrayBuffer();
    }
    const response = await fetch(base + endpoint, { headers: { ...auth, Origin: 'https://untrusted.example' } });
    assert.equal(response.status, 403);
    await response.arrayBuffer();
  }
  const rejected = await fetch(base + '/api/events', { method: 'POST', body: JSON.stringify({ type: 'cleanup.requested' }) });
  assert.equal(rejected.status, 401);
  await rejected.arrayBuffer();
  const empty = await (await fetch(base + '/api/events', { headers: auth })).json();
  assert.deepEqual(empty.events, []);

  for (const origin of [undefined, 'http://localhost:44777', 'http://127.0.0.1:44777']) {
    const response = await fetch(base + '/api/health', { headers: { ...auth, ...(origin ? { Origin: origin } : {}) } });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).authVersion, 1);
  }
  const sent = await fetch(base + '/api/events', { method: 'POST', headers: auth,
    body: JSON.stringify({ type: 'client.hello', source: 'auth-test' }) });
  assert.equal(sent.status, 200);
  await sent.arrayBuffer();
  assert.equal((await (await fetch(base + '/api/events', { headers: auth })).json()).events.length, 1);

  assert.equal((await upgrade(port)).status, 401);
  assert.equal((await upgrade(port, { ...auth, Origin: 'https://untrusted.example' })).status, 401);
  for (const [headers, query] of [[auth, ''], [{ Origin: 'http://localhost:44777' }, `?token=${token}`]]) {
    const connection = await upgrade(port, headers, query);
    assert.equal(connection.status, 101);
    connection.socket.destroy();
  }

  // A competing instance with a different configured token cannot overwrite
  // the credential that clients are using for the live bridge.
  const duplicate = launch(tokenFile, port, 'different-token');
  children.push(duplicate.child);
  await assert.rejects(duplicate.ready, /EADDRINUSE/);
  assert.equal((await fs.readFile(tokenFile, 'utf8')).trim(), token);
  const live = await fetch(base + '/api/health', { headers: auth });
  assert.equal(live.status, 200);
  await live.arrayBuffer();

  await stop(server.child);
  const restarted = launch(tokenFile, port);
  children.push(restarted.child);
  await restarted.ready;
  assert.equal((await fs.readFile(tokenFile, 'utf8')).trim(), token);
  const healthy = await fetch(base + '/api/health', { headers: auth });
  assert.equal(healthy.status, 200);
  assert.equal((await healthy.json()).authVersion, 1);
});
