import { randomUUID } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { AuthStore, ApiError } from './auth.js';
interface PostRecord { id: string; circleId: string; authorId: string; imageURL: string; caption: string; createdAt: string; likes: string[]; comments: { userId: string; text: string }[] }
interface StoryRecord extends Omit<PostRecord, 'comments'> { expiresAt: string; seen: string[] }
interface TrollRecord { id: string; circleId: string; moderationAuthorId: string; subjects: Record<string, number>; imageURL: string; caption: string; createdAt: string; reactions: string[]; hiddenFor: string[]; removed: boolean; aspectRatio: number }
interface SocialState { version: 1; posts: PostRecord[]; stories: StoryRecord[]; trolls: TrollRecord[]; reports: { id: string; trollId: string; userId: string; reason: string; createdAt: string }[]; replies: { id: string; storyId: string; senderId: string; recipientId: string; text: string; createdAt: string }[] }
function caption(value: unknown, maximum = 2000): string {
  if (value === undefined) return '';
  if (typeof value !== 'string' || value.length > maximum) throw new ApiError(400, 'Text is too long');
  return value.trim();
}
function toggle(ids: string[], id: string) { const i = ids.indexOf(id); if (i < 0) ids.push(id); else ids.splice(i, 1); }
export class SocialStore {
  private state: SocialState;
  private file: string;
  constructor(private auth: AuthStore, directory: string, private uploads: string, private now = () => Date.now()) {
    this.file = path.join(directory, 'social.json');
    this.state = fs.existsSync(this.file) ? JSON.parse(fs.readFileSync(this.file, 'utf8')) : { version: 1, posts: [], stories: [], trolls: [], reports: [], replies: [] };
    if (this.state.version !== 1 || !Array.isArray(this.state.posts) || !Array.isArray(this.state.stories) || !Array.isArray(this.state.trolls)) throw new Error('Invalid social store');
  }
  private commit<T>(operation: (state: SocialState) => T): T {
    const draft = structuredClone(this.state); const result = operation(draft);
    const temporary = this.file + '.' + randomUUID() + '.tmp';
    try { fs.writeFileSync(temporary, JSON.stringify(draft), { flag: 'wx', mode: 0o600 }); fs.renameSync(temporary, this.file); this.state = draft; }
    finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
    return result;
  }
  private member(userId: string, circleId: string) { return this.auth.members(userId, circleId); }
  private photo(userId: string, circleId: string, value: unknown) {
    if (typeof value !== 'string' || !/^\/uploads\/[a-f0-9-]+\.jpg$/.test(value)) throw new ApiError(400, 'Invalid photo');
    return { url: value, metadata: this.auth.socialPhoto(userId, circleId, path.basename(value)) };
  }
  private visible(post: TrollRecord, userId: string) {
    return !post.removed && !post.hiddenFor.includes(userId) && Object.entries(post.subjects).every(([id, version]) => this.auth.socialUser(id).allowsTrollPosts && this.auth.consentVersion(id) === version);
  }
  private postDTO(post: PostRecord, userId: string) { return { id: post.id, author: this.auth.socialUser(post.authorId), media: [{ url: post.imageURL }], caption: post.caption, createdAt: post.createdAt, likes: post.likes.length, comments: post.comments.map(c => c.text), commentDetails: post.comments.map(c => ({ author: this.auth.socialUser(c.userId), text: c.text })), isLiked: post.likes.includes(userId) }; }
  private storyDTO(story: StoryRecord, userId: string) { return { id: story.id, user: this.auth.socialUser(story.authorId), media: { url: story.imageURL }, caption: story.caption, createdAt: story.createdAt, expiresAt: story.expiresAt, isSeen: story.seen.includes(userId), isLiked: story.likes.includes(userId) }; }
  private trollDTO(post: TrollRecord, userId: string) { return { id: post.id, imageURL: post.imageURL, caption: post.caption, createdAt: post.createdAt, reactions: post.reactions.length, hasReacted: post.reactions.includes(userId), aspectRatio: post.aspectRatio }; }
  snapshot(userId: string, circleId: string) {
    const members = this.member(userId, circleId);
    return { friends: members.sort((a,b) => a.id === userId ? -1 : b.id === userId ? 1 : a.name.localeCompare(b.name)),
      posts: this.state.posts.filter(p => p.circleId === circleId).map(p => this.postDTO(p, userId)),
      stories: this.state.stories.filter(s => s.circleId === circleId && Date.parse(s.expiresAt) > this.now()).map(s => this.storyDTO(s, userId)),
      trollPosts: this.state.trolls.filter(p => p.circleId === circleId && this.visible(p, userId)).map(p => this.trollDTO(p, userId)) };
  }
  create(userId: string, circleId: string, kind: string, body: Record<string, unknown>) {
    this.member(userId, circleId); const photo = this.photo(userId, circleId, body.imageURL), text = caption(body.caption);
    const common = { id: randomUUID(), circleId, authorId: userId, imageURL: photo.url, caption: text, createdAt: new Date(this.now()).toISOString(), likes: [] as string[] };
    if (kind === 'posts') return this.commit(state => { const post = { ...common, comments: [] }; state.posts.unshift(post); return this.postDTO(post, userId); });
    if (kind === 'stories') return this.commit(state => { const story = { ...common, expiresAt: new Date(this.now() + 86400000).toISOString(), seen: [] }; state.stories.unshift(story); return this.storyDTO(story, userId); });
    const members = this.member(userId, circleId);
    if (!Array.isArray(body.subjectIDs) || body.subjectIDs.length === 0 || body.subjectIDs.length > 50 || !body.subjectIDs.every(id => typeof id === 'string')) throw new ApiError(400, 'Select everyone in the photo');
    const subjects: Record<string, number> = {};
    for (const id of new Set(body.subjectIDs as string[])) {
      if (!members.some(m => m.id === id && m.allowsTrollPosts)) throw new ApiError(403, 'A pictured friend has opted out or is not in this circle');
      subjects[id] = this.auth.consentVersion(id);
    }
    // Separate anonymous URL prevents matching the upload URL to an identified post/avatar.
    const anonymousName = randomUUID() + '.jpg';
    fs.copyFileSync(path.join(this.uploads, path.basename(photo.url)), path.join(this.uploads, anonymousName));
    this.auth.registerMedia(userId, circleId, anonymousName, { width: photo.metadata.width!, height: photo.metadata.height!, anonymous: true });
    return this.commit(state => {
      const post: TrollRecord = { id: common.id, circleId, moderationAuthorId: userId, subjects, imageURL: '/uploads/' + anonymousName, caption: text, createdAt: common.createdAt, reactions: [], hiddenFor: [], removed: false, aspectRatio: Math.max(0.65, Math.min(1.4, (photo.metadata.width ?? 1)/(photo.metadata.height ?? 1))) };
      state.trolls.unshift(post); return this.trollDTO(post, userId);
    });
  }
  action(userId: string, circleId: string, kind: string, id: string, action: string, body: Record<string, unknown>) {
    this.member(userId, circleId);
    if (kind === 'posts') return this.commit(state => {
      const post = state.posts.find(p => p.id === id && p.circleId === circleId); if (!post) throw new ApiError(404, 'Post not found');
      if (action === 'like') toggle(post.likes, userId);
      else if (action === 'comments') { const text = caption(body.text, 2000); if (!text) throw new ApiError(400, 'Write a comment'); post.comments.push({ userId, text }); }
      else if (action === 'edit') { if (post.authorId !== userId) throw new ApiError(403, 'Post owner required'); post.caption = caption(body.caption); }
      else if (action === 'delete') { if (post.authorId !== userId) throw new ApiError(403, 'Post owner required'); state.posts = state.posts.filter(p => p.id !== id); return { success: true }; }
      else throw new ApiError(404, 'Action not found');
      return this.postDTO(post, userId);
    });
    if (kind === 'stories') return this.commit(state => {
      const story = state.stories.find(s => s.id === id && s.circleId === circleId && Date.parse(s.expiresAt) > this.now());
      if (!story) throw new ApiError(404, 'Story expired or unavailable');
      if (action === 'like') toggle(story.likes, userId);
      else if (action === 'seen') { if (!story.seen.includes(userId)) story.seen.push(userId); }
      else if (action === 'replies') { const text = caption(body.text, 2000); if (!text) throw new ApiError(400, 'Write a reply'); state.replies.push({ id: randomUUID(), storyId: id, senderId: userId, recipientId: story.authorId, text, createdAt: new Date(this.now()).toISOString() }); }
      else throw new ApiError(404, 'Action not found');
      return { success: true };
    });
    return this.commit(state => {
      const post = state.trolls.find(p => p.id === id && p.circleId === circleId); if (!post || !this.visible(post, userId)) throw new ApiError(404, 'Post not found');
      if (action === 'react') { toggle(post.reactions, userId); return this.trollDTO(post, userId); }
      if (action === 'report') {
        const reason = caption(body.reason, 1000); if (!reason) throw new ApiError(400, 'Choose a reason');
        state.reports.push({ id: randomUUID(), trollId: id, userId, reason, createdAt: new Date(this.now()).toISOString() }); post.hiddenFor.push(userId); return { success: true };
      }
      throw new ApiError(404, 'Action not found');
    });
  }
  postLikes(userId: string, circleId: string, id: string) {
    this.member(userId, circleId);
    const post = this.state.posts.find(p => p.id === id && p.circleId === circleId);
    if (!post) throw new ApiError(404, 'Post not found');
    if (post.authorId !== userId) throw new ApiError(403, 'Post owner required');
    return { users: post.likes.map(id => this.auth.socialUser(id)) };
  }
  replies(userId: string, circleId: string, storyId: string) {
    this.member(userId, circleId); const story = this.state.stories.find(s => s.id === storyId && s.circleId === circleId);
    if (!story || story.authorId !== userId) throw new ApiError(404, 'Replies not found');
    return this.state.replies.filter(r => r.storyId === storyId).map(r => ({ id: r.id, sender: this.auth.socialUser(r.senderId), text: r.text, createdAt: r.createdAt }));
  }
  inbox(userId: string, circleId: string) {
    this.member(userId, circleId);
    return this.state.replies.filter(r => r.recipientId === userId && this.state.stories.some(s => s.id === r.storyId && s.circleId === circleId))
      .map(r => ({ id: r.id, sender: this.auth.socialUser(r.senderId), text: r.text, createdAt: r.createdAt }));
  }
  reports(userId: string, circleId: string) {
    if (!this.auth.circlesFor(userId).some(c => c.id === circleId && c.ownerId === userId)) throw new ApiError(403, 'Circle owner required');
    return this.state.reports.filter(r => this.state.trolls.some(t => t.id === r.trollId && t.circleId === circleId && !t.removed)).map(r => ({ id: r.id, trollId: r.trollId, reason: r.reason, createdAt: r.createdAt }));
  }
  removeTroll(userId: string, circleId: string, id: string) {
    this.reports(userId, circleId);
    this.commit(state => { const post = state.trolls.find(p => p.id === id && p.circleId === circleId); if (!post) throw new ApiError(404, 'Post not found'); post.removed = true; });
    return { success: true };
  }
  canReadMedia(userId: string, filename: string): boolean {
    const url = '/uploads/' + filename;
    const posts = this.state.posts.filter(p => p.imageURL === url), stories = this.state.stories.filter(s => s.imageURL === url), trolls = this.state.trolls.filter(p => p.imageURL === url);
    if (!posts.length && !stories.length && !trolls.length) return true; // Ordinary chat/avatar or an unpublished upload.
    return posts.some(p => this.auth.circlesFor(userId).some(c => c.id === p.circleId)) ||
      stories.some(s => Date.parse(s.expiresAt) > this.now() && this.auth.circlesFor(userId).some(c => c.id === s.circleId)) ||
      trolls.some(p => this.visible(p, userId) && this.auth.circlesFor(userId).some(c => c.id === p.circleId));
  }
}
