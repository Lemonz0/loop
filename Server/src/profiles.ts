import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { AuthStore, ApiError } from './auth.js';

interface Details { bio?: string; pronouns?: string; status?: string; timeZone?: string; showLocalTime?: boolean; presence?: 'everyone' | 'nobody'; private?: boolean; links?: string[]; kind?: 'person' | 'bot' | 'official'; verified?: boolean; deactivated?: boolean }
interface Personal { nickname: string; note: string; contact: boolean; blocked: boolean; muted: boolean; requested: boolean; clearBefore?: string; disappearingSeconds: number }
interface State { details: Record<string, Details>; personal: Record<string, Record<string, Personal>>; reports: { viewer: string; target: string; reason: string; date: string }[] }
const empty = (): Personal => ({ nickname: '', note: '', contact: false, blocked: false, muted: false, requested: false, disappearingSeconds: 0 });
/** Viewer-owned notes and relationships never appear in another viewer's response. */
export class ProfileStore {
  private state: State;
  private file: string;
  constructor(private auth: AuthStore, directory: string) {
    this.file = path.join(directory, 'profiles.json');
    this.state = fs.existsSync(this.file) ? JSON.parse(fs.readFileSync(this.file, 'utf8')) : { details: {}, personal: {}, reports: [] };
    if (!this.state.details || !this.state.personal || !Array.isArray(this.state.reports)) throw new Error('Invalid profile store');
  }
  private save(update: (draft: State) => void) {
    const draft = structuredClone(this.state); update(draft);
    const temporary = this.file + '.' + randomUUID() + '.tmp';
    try { fs.writeFileSync(temporary, JSON.stringify(draft), { mode: 0o600, flag: 'wx' }); fs.renameSync(temporary, this.file); this.state = draft; }
    finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
  }
  personal(viewer: string, target: string): Personal { return { ...(this.state.personal[viewer]?.[target] ?? empty()) }; }
  blocked(a: string, b: string) { return this.personal(a, b).blocked || this.personal(b, a).blocked; }
  canSeePresence(viewer: string, target: string) {
    const d = this.state.details[target];
    return viewer === target || (this.auth.shareCircle(viewer, target) && !this.blocked(viewer, target) && d?.presence !== 'nobody' && !d?.private && !d?.deactivated);
  }
  canContact(viewer: string, target: string) {
    const d = this.state.details[target];
    return !this.blocked(viewer, target) && !d?.deactivated && (!d?.private || this.personal(target, viewer).contact);
  }
  card(viewer: string, target: string, circleId?: string) {
    const identity = this.auth.profileIdentity(viewer, target), d = this.state.details[target] ?? {}, personal = this.personal(viewer, target);
    const isSelf = viewer === target, deleted = identity.deleted || !!d.deactivated;
    const privateProfile = !isSelf && !!d.private && !this.personal(target, viewer).contact;
    const blocked = !isSelf && this.blocked(viewer, target);
    const restricted = deleted || privateProfile || blocked;
    const user = deleted ? { id: target, displayName: 'Deleted account', username: '' } : { ...identity.user, username: privateProfile ? '' : identity.user.username, bio: undefined };
    const mutualGroups = restricted ? [] : this.auth.circlesFor(viewer).filter(c => c.memberIds.includes(target)).map(c => ({ id: c.id, name: c.name }));
    // Mutual contacts only include identities in the viewer's circles. No global directory disclosure.
    const mutualContacts = restricted ? [] : Object.entries(this.state.personal[viewer] ?? {}).filter(([id, p]) => p.contact && this.personal(target, id).contact && this.auth.shareCircle(viewer, id)).map(([id]) => this.auth.socialUser(id));
    return { user, isSelf, state: deleted ? 'deleted' : blocked ? 'blocked' : privateProfile ? 'private' : 'active',
      kind: restricted ? 'person' : d.kind ?? 'person', verified: !restricted && !!d.verified, personal: deleted ? empty() : personal,
      bio: restricted ? undefined : d.bio, pronouns: restricted ? undefined : d.pronouns, customStatus: restricted ? undefined : d.status,
      timeZone: !restricted && d.showLocalTime ? d.timeZone : undefined, memberSince: restricted ? undefined : identity.memberSince,
      presenceVisible: !restricted && this.canSeePresence(viewer, target), mutualGroups, mutualContacts,
      links: restricted ? [] : d.links ?? [], group: circleId && !restricted ? this.auth.membership(viewer, target, circleId) : undefined,
      canCall: !isSelf && !restricted && (d.kind ?? 'person') === 'person', canMessage: !isSelf && !restricted && this.canContact(viewer, target) };
  }
  edit(viewer: string, input: Record<string, unknown>) {
    const details: Details = {};
    for (const [key, max] of [['bio', 2000], ['pronouns', 80], ['status', 140], ['timeZone', 100]] as const) {
      if (typeof input[key] !== 'string' || (input[key] as string).length > max) throw new ApiError(400, `Invalid ${key}`);
      details[key] = (input[key] as string).trim();
    }
    if (details.timeZone) { try { new Intl.DateTimeFormat('en', { timeZone: details.timeZone }); } catch { throw new ApiError(400, 'Invalid time zone'); } }
    if (typeof input.private !== 'boolean' || typeof input.showLocalTime !== 'boolean' || !['everyone', 'nobody'].includes(input.presence as string)) throw new ApiError(400, 'Invalid privacy settings');
    if (!Array.isArray(input.links) || input.links.length > 5 || input.links.some(l => typeof l !== 'string' || l.length > 500 || !/^https:\/\//.test(l))) throw new ApiError(400, 'Use up to five HTTPS links');
    details.private = input.private; details.showLocalTime = input.showLocalTime; details.presence = input.presence as Details['presence']; details.links = input.links;
    this.save(draft => { draft.details[viewer] = { ...draft.details[viewer], ...details }; });
    return this.card(viewer, viewer);
  }
  settings(viewer: string) { return { bio: '', pronouns: '', status: '', timeZone: '', private: false, showLocalTime: false, presence: 'everyone', links: [], ...this.state.details[viewer] }; }
  requestsFor(viewer: string) {
    return Object.entries(this.state.personal).filter(([target, entries]) => entries[viewer]?.requested && this.auth.shareCircle(viewer, target) && !this.blocked(viewer, target)).map(([target]) => this.auth.socialUser(target));
  }
  action(viewer: string, target: string, input: Record<string, unknown>) {
    this.auth.profileIdentity(viewer, target);
    if (viewer === target) throw new ApiError(400, 'Use Edit profile for your own account');
    const action = input.action;
    if (!['note', 'contact', 'block', 'mute', 'request', 'report', 'clear', 'disappearing'].includes(action as string)) throw new ApiError(400, 'Invalid profile action');
    if (['contact', 'block', 'mute'].includes(action as string) && typeof input.value !== 'boolean') throw new ApiError(400, 'Invalid value');
    if (action === 'note' && (typeof input.note !== 'string' || input.note.length > 4000 || typeof input.nickname !== 'string' || input.nickname.length > 80)) throw new ApiError(400, 'Invalid private note');
    if (action === 'report' && (typeof input.reason !== 'string' || !input.reason.trim() || input.reason.length > 1000)) throw new ApiError(400, 'Add a report reason');
    if (action === 'disappearing' && ![0, 86400, 604800].includes(input.seconds as number)) throw new ApiError(400, 'Invalid message duration');
    this.save(draft => {
      draft.personal[viewer] ??= {}; const p = draft.personal[viewer][target] ?? empty();
      if (action === 'note') { p.note = input.note as string; p.nickname = input.nickname as string; }
      if (action === 'contact') { p.contact = input.value as boolean; if (p.contact && draft.personal[target]?.[viewer]) draft.personal[target][viewer].requested = false; }
      if (action === 'block') p.blocked = input.value as boolean;
      if (action === 'mute') p.muted = input.value as boolean;
      if (action === 'request') p.requested = true;
      if (action === 'clear') p.clearBefore = new Date().toISOString();
      if (action === 'disappearing') p.disappearingSeconds = input.seconds as number;
      if (action === 'report') { draft.reports.push({ viewer, target, reason: input.reason as string, date: new Date().toISOString() }); }
      draft.personal[viewer][target] = p;
    });
    return this.card(viewer, target);
  }
}
