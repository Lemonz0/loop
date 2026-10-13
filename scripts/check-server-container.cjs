const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { randomBytes } = require('node:crypto');

const name = 'loop-smoke-' + randomBytes(6).toString('hex');
const volumes = [name + '-data', name + '-uploads'];
const bootstrap = randomBytes(32).toString('hex');
const password = randomBytes(24).toString('hex');
const docker = (...args) => execFileSync('docker', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const pause = () => new Promise(resolve => setTimeout(resolve, 500));

async function main() {
  try {
    docker('run', '-d', '--name', name, '-p', '127.0.0.1::8080',
      '-e', 'INVITE_KEY=' + bootstrap,
      '-v', volumes[0] + ':/app/data', '-v', volumes[1] + ':/app/uploads',
      'liquid-glass-server:test');
    let base = 'http://' + docker('port', name, '8080/tcp');
    async function ready() {
      for (let attempt = 0; attempt < 60; attempt++) {
        try {
          const response = await fetch(base + '/health', { signal: AbortSignal.timeout(2000) });
          if (response.ok) return;
        } catch {}
        await pause();
      }
      console.error(docker('logs', '--tail', '40', name));
      throw new Error('Container did not become reachable through its published port');
    }
    await ready();
    assert.equal((await fetch(base + '/api/auth/me')).status, 401);
    const registration = await fetch(base + '/api/auth/invite', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ secretKey: bootstrap, username: 'container_owner', chosenDisplayName: 'Container Owner', password })
    });
    assert.equal(registration.status, 200);
    const { session } = await registration.json();
    const headers = { Authorization: 'Bearer ' + session.token };
    // Verify the second persistent mount independently of the account store.
    docker('exec', name, 'node', '-e', "require('node:fs').writeFileSync('/app/uploads/persistence-check.txt', 'persistent media')");
    docker('restart', name);
    // Docker may assign a new host port when restarting an auto-published port.
    base = 'http://' + docker('port', name, '8080/tcp');
    await ready();
    const me = await fetch(base + '/api/auth/me', { headers });
    assert.equal(me.status, 200);
    assert.equal((await me.json()).user.id, session.user.id);
    assert.equal(docker('exec', name, 'node', '-e', "process.stdout.write(require('node:fs').readFileSync('/app/uploads/persistence-check.txt', 'utf8'))"), 'persistent media');
    console.log('Container is reachable; account sessions and media storage survive restart.');
  } finally {
    try { docker('rm', '-f', name); } catch {}
    for (const volume of volumes) { try { docker('volume', 'rm', volume); } catch {} }
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
