import { ApiError } from './auth.js';

export interface ICEServer { urls: string[]; username?: string; credential?: string }
export interface ICEOptions {
  cloudflareKeyId?: string; cloudflareToken?: string;
  turnURL?: string; turnUsername?: string; turnPassword?: string;
  fetch?: typeof fetch; now?: () => number;
}

/** The long-lived Cloudflare key stays here; phones receive expiring credentials. */
export class CallICEProvider {
  private cached?: { expiresAt: number; servers: ICEServer[] };
  private pending?: Promise<ICEServer[]>;
  constructor(private options: ICEOptions) {}
  async servers(): Promise<ICEServer[]> {
    const direct: ICEServer[] = [{ urls: ['stun:stun.cloudflare.com:3478', 'stun:stun.l.google.com:19302'] }];
    const o = this.options;
    if (o.cloudflareKeyId && o.cloudflareToken) {
      const now = (o.now ?? Date.now)();
      if (this.cached && this.cached.expiresAt > now) return [...direct, ...this.cached.servers];
      this.pending ??= this.generate();
      try { return [...direct, ...await this.pending]; } finally { this.pending = undefined; }
    }
    if (o.turnURL && o.turnUsername && o.turnPassword) direct.push({
      urls: o.turnURL.split(',').map(url => url.trim()).filter(url => /^turns?:/.test(url)),
      username: o.turnUsername, credential: o.turnPassword
    });
    return direct;
  }
  private async generate(): Promise<ICEServer[]> {
    const o = this.options;
    try {
      const response = await (o.fetch ?? fetch)(`https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(o.cloudflareKeyId!)}/credentials/generate-ice-servers`, {
        method: 'POST', headers: { Authorization: `Bearer ${o.cloudflareToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ ttl: 86400 }), signal: AbortSignal.timeout(8000)
      });
      if (!response.ok) throw new Error();
      const body = await response.json() as { iceServers?: unknown };
      const raw = Array.isArray(body.iceServers) ? body.iceServers : [body.iceServers];
      const servers: ICEServer[] = [];
      for (const item of raw) {
        if (!item || typeof item !== 'object') continue;
        const value = item as Record<string, unknown>;
        const urls = (Array.isArray(value.urls) ? value.urls : [value.urls]).filter((url): url is string => typeof url === 'string' && /^turns?:/.test(url));
        if (urls.length && typeof value.username === 'string' && typeof value.credential === 'string') servers.push({ urls, username: value.username, credential: value.credential });
      }
      if (!servers.length) throw new Error();
      this.cached = { expiresAt: (o.now ?? Date.now)() + 23 * 3600000, servers };
      return servers;
    } catch { throw new ApiError(503, 'Call relay is temporarily unavailable. Try again shortly.'); }
  }
}
