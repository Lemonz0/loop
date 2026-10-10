import * as fs from 'node:fs';
import * as path from 'node:path';
import * as http2 from 'node:http2';
import { createHash, createPrivateKey, sign } from 'node:crypto';
import { ApiError, AuthStore } from './auth.js';
import { ChatMessage } from './types.js';
import { serverLogger } from './logger.js';

interface Device { userId: string; sessionHash: string; token: string; topic: string; environment: 'development' | 'production'; sound: boolean }
export interface PushOptions { keyId?: string; teamId?: string; keyPath?: string; topic?: string; send?: (device: Device, payload: object) => Promise<number> }
const hash = (value: string) => createHash('sha256').update(value).digest('hex');

/** Session-bound private registrations. Payloads deliberately omit message text. */
export class PushStore {
  private devices: Device[];
  private file: string;
  private jwt?: { value: string; issuedAt: number };
  readonly available: boolean;
  constructor(private auth: AuthStore, directory: string, private options: PushOptions) {
    this.file = path.join(directory, 'push-devices.json');
    this.devices = fs.existsSync(this.file) ? JSON.parse(fs.readFileSync(this.file, 'utf8')) : [];
    this.available = !!(options.topic && (options.send || (options.keyId && options.teamId && options.keyPath && fs.existsSync(options.keyPath))));
  }
  register(userId: string, session: string, body: Record<string, unknown>) {
    if (!this.available) return { available: false, registered: false };
    if (typeof body.deviceToken !== 'string' || !/^[a-f0-9]{32,512}$/i.test(body.deviceToken) || body.topic !== this.options.topic ||
        !['development', 'production'].includes(String(body.environment)) || typeof body.sound !== 'boolean') throw new ApiError(400, 'Invalid push registration');
    const device: Device = { userId, sessionHash: hash(session), token: body.deviceToken.toLowerCase(), topic: this.options.topic!, environment: body.environment as Device['environment'], sound: body.sound };
    // A device can belong to only one session/account at a time.
    this.devices = this.devices.filter(d => !(d.token === device.token && d.topic === device.topic));
    this.devices = this.devices.filter(d => this.auth.hasActiveSession(d.userId, d.sessionHash));
    if (this.devices.filter(d => d.userId === userId).length >= 20) throw new ApiError(429, 'Too many push devices');
    this.devices.push(device); this.save();
    return { available: true, registered: true };
  }
  unregister(session: string) { this.devices = this.devices.filter(d => d.sessionHash !== hash(session)); this.save(); }
  async message(userIds: string[], message: ChatMessage) {
    if (!this.available) return;
    await Promise.all(this.devices.filter(d => userIds.includes(d.userId)).map(async device => {
      if (!this.auth.hasActiveSession(device.userId, device.sessionHash) || !this.auth.canAccessRoom(device.userId, message.roomId)) { this.remove(device); return; }
      const payload = { aps: { alert: { title: 'Loop', body: 'You have a new message.' }, 'thread-id': message.roomId, ...(device.sound ? { sound: 'default' } : {}) }, roomId: message.roomId, messageId: message.id, userId: device.userId };
      try {
        const status = await (this.options.send ? this.options.send(device, payload) : this.deliver(device, payload));
        if (status === 410) this.remove(device);
        else if (status !== 200) serverLogger.warn('PUSH_FAILED', `APNs rejected a notification (${status})`);
      } catch { serverLogger.warn('PUSH_FAILED', 'APNs delivery failed'); }
    }));
  }
  private remove(device: Device) { this.devices = this.devices.filter(d => d !== device); this.save(); }
  private save() { fs.mkdirSync(path.dirname(this.file), { recursive: true }); const temporary = this.file + '.tmp'; fs.writeFileSync(temporary, JSON.stringify(this.devices), { mode: 0o600 }); fs.renameSync(temporary, this.file); }
  private providerToken() {
    const now = Math.floor(Date.now() / 1000);
    if (this.jwt && now - this.jwt.issuedAt < 3000) return this.jwt.value;
    const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url');
    const unsigned = encode({ alg: 'ES256', kid: this.options.keyId }) + '.' + encode({ iss: this.options.teamId, iat: now });
    const key = createPrivateKey(fs.readFileSync(this.options.keyPath!));
    const signature = sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
    this.jwt = { value: unsigned + '.' + signature, issuedAt: now }; return this.jwt.value;
  }
  private deliver(device: Device, payload: object): Promise<number> {
    const authorization = 'bearer ' + this.providerToken();
    return new Promise((resolve, reject) => {
      const session = http2.connect(device.environment === 'development' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com');
      let settled = false;
      const finish = (status?: number, error?: Error) => { if (settled) return; settled = true; clearTimeout(timer); session.destroy(); if (error) reject(error); else resolve(status ?? 500); };
      const timer = setTimeout(() => finish(undefined, new Error('APNs timeout')), 10000);
      session.on('error', error => finish(undefined, error));
      session.on('connect', () => {
        const request = session.request({ ':method': 'POST', ':path': '/3/device/' + device.token, authorization,
          'apns-topic': device.topic, 'apns-push-type': 'alert', 'apns-priority': '10', 'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600) });
        let status = 500;
        request.on('response', headers => { status = Number(headers[':status']); });
        request.on('error', error => finish(undefined, error));
        request.on('end', () => finish(status)); request.resume(); request.end(JSON.stringify(payload));
      });
    });
  }
}
