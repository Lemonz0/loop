import { WebSocket, WebSocketServer } from 'ws';
import { IncomingMessage } from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { ClientMessageEnvelope, ServerMessageEnvelope, UserProfile, ChatMessage, CallSignalPayload, RoomTheme } from './types.js';
import { randomUUID } from 'node:crypto';
import { ProfileStore } from './profiles.js';
import { ApiError, AuthStore } from './auth.js';
import { serverLogger } from './logger.js';

interface ConnectedClient {
  ws: WebSocket;
  user: UserProfile;
  joinedRooms: Set<string>;
  ip: string;
  token: string;
}

export class WebSocketHub {
  private clients = new Map<WebSocket, ConnectedClient>();
  private messageHistory = new Map<string, ChatMessage[]>();
  private calls: { id: string; roomId: string; callerId: string; date: string; isVideo: boolean; participantIds: string[] }[] = [];
  private lastSeen = new Map<string, string>();
  private roomThemes = new Map<string, RoomTheme>();

  private dataDir = path.resolve(process.cwd(), 'data');
  private messagesFilePath = path.join(this.dataDir, 'messages.json');
  private themesFilePath = path.join(this.dataDir, 'themes.json');

  constructor(private wss: WebSocketServer, private auth: AuthStore, dataDirectory?: string, private profiles?: ProfileStore) {
    if (dataDirectory) { this.dataDir = dataDirectory; this.messagesFilePath = path.join(dataDirectory, 'messages.json'); this.themesFilePath = path.join(dataDirectory, 'themes.json'); }
    const callsFile = path.join(this.dataDir, 'calls.json');
    if (fs.existsSync(callsFile)) this.calls = JSON.parse(fs.readFileSync(callsFile, 'utf8'));
    this.loadPersistedData();
    this.setupServer();
  }

  private loadPersistedData(): void {
    try {
      if (!fs.existsSync(this.dataDir)) {
        fs.mkdirSync(this.dataDir, { recursive: true });
      }
      if (fs.existsSync(this.messagesFilePath)) {
        const raw = fs.readFileSync(this.messagesFilePath, 'utf-8');
        const parsed = JSON.parse(raw);
        for (const [roomId, msgs] of Object.entries(parsed)) {
          this.messageHistory.set(roomId, msgs as ChatMessage[]);
        }
        serverLogger.info('STORAGE', `Loaded persisted messages for ${this.messageHistory.size} room(s)`);
      }
      if (fs.existsSync(this.themesFilePath)) {
        const raw = fs.readFileSync(this.themesFilePath, 'utf-8');
        const parsed = JSON.parse(raw);
        for (const [roomId, theme] of Object.entries(parsed)) {
          this.roomThemes.set(roomId, theme as RoomTheme);
        }
        serverLogger.info('STORAGE', `Loaded persisted themes for ${this.roomThemes.size} room(s)`);
      }
    } catch (err: any) {
      serverLogger.warn('STORAGE', `Failed to load persisted data: ${err.message}`);
    }
  }

  private saveMessages(): void {
    try {
      const obj: Record<string, ChatMessage[]> = {};
      for (const [roomId, msgs] of this.messageHistory.entries()) {
        obj[roomId] = msgs;
      }
      fs.writeFileSync(this.messagesFilePath, JSON.stringify(obj, null, 2), 'utf-8');
    } catch (err: any) {
      serverLogger.error('STORAGE', `Failed to save messages: ${err.message}`);
    }
  }

  private saveThemes(): void {
    try {
      const obj: Record<string, RoomTheme> = {};
      for (const [roomId, theme] of this.roomThemes.entries()) {
        obj[roomId] = theme;
      }
      fs.writeFileSync(this.themesFilePath, JSON.stringify(obj, null, 2), 'utf-8');
    } catch (err: any) {
      serverLogger.error('STORAGE', `Failed to save themes: ${err.message}`);
    }
  }

  synchronizeRooms() {
    for (const client of this.clients.values()) {
      if (!this.active(client)) continue;
      let changed = false;
      for (const roomId of client.joinedRooms) if (!this.auth.canAccessRoom(client.user.id, roomId)) { client.joinedRooms.delete(roomId); changed = true; }
      for (const roomId of this.auth.roomsFor(client.user.id)) {
        if (client.joinedRooms.has(roomId)) continue;
        changed = true; client.joinedRooms.add(roomId);
        this.send(client.ws, { type: 'room_history', roomId, history: this.visibleHistory(client.user.id, roomId) });
      }
      if (changed) this.send(client.ws, { type: 'account_updated' });
    }
  }
  notifyCircleChange(roomId: string) { this.broadcastToRoom(roomId, { type: 'account_updated' }); }
  notifyAccountChange(userId: string) {
    for (const client of this.clients.values()) if (this.auth.shareCircle(userId, client.user.id) && this.active(client)) this.send(client.ws, { type: 'account_updated' });
  }

  private canInteract(viewer: string, roomId: string) {
    if (!this.auth.canWriteRoom(viewer, roomId)) return false;
    const room = this.auth.chatRooms(viewer).find(r => r.id === roomId);
    return !!room && (room.isGroup || room.participantIds.filter(id => id !== viewer).every(id => this.profiles?.canContact(viewer, id) ?? true));
  }
  private visibleHistory(viewer: string, roomId: string) {
    const room = this.auth.chatRooms(viewer).find(r => r.id === roomId); if (!room) return [];
    const peer = !room.isGroup ? room.participantIds.find(id => id !== viewer) : undefined;
    const personal = peer ? this.profiles?.personal(viewer, peer) : undefined;
    const durations = [personal?.disappearingSeconds ?? 0, peer ? this.profiles?.personal(peer, viewer).disappearingSeconds ?? 0 : 0].filter(n => n > 0);
    const duration = durations.length ? Math.min(...durations) : 0;
    return (this.messageHistory.get(roomId) ?? []).filter(m => (!personal?.clearBefore || m.timestamp > personal.clearBefore) && (!duration || Date.parse(m.timestamp) + duration * 1000 > Date.now()));
  }
  sharedItems(viewer: string, target: string, roomId?: string) {
    const room = this.auth.chatRooms(viewer).find(r => roomId ? r.id === roomId && r.participantIds.includes(target) : !r.isGroup && r.participantIds.includes(target));
    if (!room) return [];
    return this.visibleHistory(viewer, room.id).filter(m => m.mediaAttachment || /https:\/\//.test(m.content)).slice(-200).reverse();
  }
  canReadChatMedia(viewer: string, filename: string) {
    let referenced = false;
    for (const [roomId, messages] of this.messageHistory) {
      if (!messages.some(m => m.mediaAttachment?.remoteURL === '/uploads/' + filename)) continue;
      referenced = true;
      if (this.auth.canAccessRoom(viewer, roomId) && this.visibleHistory(viewer, roomId).some(m => m.mediaAttachment?.remoteURL === '/uploads/' + filename)) return true;
    }
    return !referenced;
  }
  refreshHistories(viewer: string) { for (const client of this.clients.values()) if (this.active(client) && client.user.id === viewer) for (const roomId of client.joinedRooms) this.send(client.ws, { type: 'room_history', roomId, history: this.visibleHistory(viewer, roomId) }); }
  refreshPresence() {
    for (const viewer of this.clients.values()) if (this.active(viewer)) for (const target of this.clients.values()) {
      if (!this.auth.shareCircle(viewer.user.id, target.user.id)) continue;
      this.send(viewer.ws, { type: 'presence_updated', presence: { userId: target.user.id, displayName: target.user.displayName, isOnline: this.profiles?.canSeePresence(viewer.user.id, target.user.id) ?? true, lastSeen: new Date(0).toISOString() } });
    }
  }
  presenceFor(userId: string) { return { userId, displayName: this.auth.socialUser(userId).name, isOnline: [...this.clients.values()].some(c => c.user.id === userId && this.active(c)), lastSeen: this.lastSeen.get(userId) ?? new Date(0).toISOString() }; }
  callsFor(viewer: string) { return this.calls.filter(c => c.participantIds.includes(viewer) && this.auth.canAccessRoom(viewer, c.roomId)).map(c => ({ ...c, users: c.participantIds.filter(id => id !== viewer).map(id => this.auth.socialUser(id)) })); }
  react(viewer: string, roomId: string, messageId: string, emoji: unknown) {
    if (!this.canInteract(viewer, roomId)) throw new ApiError(403, 'Room permission required');
    if (typeof emoji !== 'string' || !['❤️', '👍', '😂', '😮', '😢'].includes(emoji)) throw new ApiError(400, 'Invalid reaction');
    const message = this.visibleHistory(viewer, roomId).find(m => m.id === messageId); if (!message) throw new ApiError(404, 'Message unavailable');
    message.reactions ??= []; const previous = message.reactions.find(r => r.userId === viewer); message.reactions = message.reactions.filter(r => r.userId !== viewer);
    if (previous?.emoji !== emoji) message.reactions.push({ userId: viewer, emoji }); this.saveMessages(); this.broadcastToRoom(roomId, { type: 'message_received', roomId, message });
  }
  private setupServer(): void {
    this.wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
      const clientIp = (req.headers['x-forwarded-for'] as string) || req.socket.remoteAddress || 'unknown';
      serverLogger.info('WS_CONNECT', 'New WebSocket client connected', { ip: clientIp });

      const authTimeout = setTimeout(() => { if (!this.clients.has(ws)) ws.close(1008, 'Authentication required'); }, 10000);
      authTimeout.unref();
      ws.on('close', () => clearTimeout(authTimeout));
      ws.on('message', (raw: Buffer) => {
        try {
          const envelope: ClientMessageEnvelope = JSON.parse(raw.toString('utf-8'));
          if (!envelope || typeof envelope !== 'object' || Array.isArray(envelope)) throw new Error('Invalid envelope');
          this.handleClientEnvelope(ws, envelope, clientIp);
        } catch (err: any) {
          serverLogger.error('WS_PARSE_ERROR', `Failed to parse client message: ${err.message}`, { ip: clientIp });
        }
      });

      ws.on('close', (code, reason) => {
        this.handleClientDisconnect(ws, code, reason.toString('utf-8'));
      });

      ws.on('error', (err) => {
        serverLogger.error('WS_SOCKET_ERROR', `Socket error: ${err.message}`, { ip: clientIp });
      });
    });
  }

  private handleClientEnvelope(ws: WebSocket, envelope: ClientMessageEnvelope, ip: string): void {
    const existingClient = this.clients.get(ws);
    const clientId = existingClient?.user.id || 'anonymous';

    if (envelope.type !== 'auth') {
      try { if (!existingClient) throw new Error(); existingClient.user = this.auth.authenticate(existingClient.token); }
      catch { this.send(ws, { type: 'error', reason: 'Authentication required' }); ws.close(1008, 'Authentication required'); return; }
      if (envelope.type !== 'ping' && (typeof envelope.roomId !== 'string' || !existingClient || !this.auth.canAccessRoom(existingClient.user.id, envelope.roomId))) {
        this.send(ws, { type: 'error', reason: 'Room membership required' }); return;
      }
      if (envelope.type !== 'join_room' && envelope.type !== 'ping' && !existingClient?.joinedRooms.has(envelope.roomId!)) {
        this.send(ws, { type: 'error', reason: 'Join the room first' }); return;
      }
    }
    if (existingClient && envelope.roomId && ['send_message', 'typing', 'call_signal', 'update_room_theme'].includes(envelope.type) && !this.canInteract(existingClient.user.id, envelope.roomId)) { this.send(ws, { type: 'error', reason: 'Messaging is restricted for this account' }); return; }
    switch (envelope.type) {
      case 'auth': {
        if (existingClient) { this.send(ws, { type: 'error', reason: 'Already authenticated' }); return; }
        let user: UserProfile;
        try { user = this.auth.authenticate(envelope.token); }
        catch { this.send(ws, { type: 'error', reason: 'Invalid or expired session' }); ws.close(1008, 'Authentication failed'); return; }
        const client: ConnectedClient = {
          ws,
          user,
          joinedRooms: new Set(this.auth.roomsFor(user.id)),
          token: envelope.token!,
          ip,
        };
        this.clients.set(ws, client);

        serverLogger.info('USER_AUTHENTICATED', `User authenticated as ${user.displayName} (${user.id})`, {
          clientId: user.id,
          ip,
          metadata: { joinedRooms: Array.from(client.joinedRooms) }
        });

        this.send(ws, { type: 'authenticated', user });

        for (const peer of this.clients.values()) {
          if (this.active(peer) && this.auth.shareCircle(user.id, peer.user.id) && (this.profiles?.canSeePresence(user.id, peer.user.id) ?? true)) this.send(ws, { type: 'presence_updated', presence: { userId: peer.user.id, displayName: peer.user.displayName, isOnline: true, lastSeen: new Date().toISOString() } });
        }
        // Broadcast presence online to circle
        this.broadcastPresence(user.id, user.displayName, true);

        // Send room history and current theme for all pre-joined rooms
        for (const roomId of client.joinedRooms) {
          const history = this.visibleHistory(user.id, roomId);
          this.send(ws, { type: 'room_history', roomId, history });

          const theme = this.roomThemes.get(roomId);
          if (theme) {
            this.send(ws, { type: 'room_theme_updated', roomId, roomTheme: theme });
          }
        }
        break;
      }

      case 'join_room': {
        if (!existingClient || !envelope.roomId) return;
        existingClient.joinedRooms.add(envelope.roomId);
        const history = this.visibleHistory(existingClient.user.id, envelope.roomId);
        this.send(ws, { type: 'room_history', roomId: envelope.roomId, history });
        const theme = this.roomThemes.get(envelope.roomId);
        if (theme) {
          this.send(ws, { type: 'room_theme_updated', roomId: envelope.roomId, roomTheme: theme });
        }
        break;
      }

      case 'leave_room': {
        existingClient?.joinedRooms.delete(envelope.roomId!); break;
      }
      case 'send_message': {
        if (!envelope.message || !envelope.roomId) return;
        if (typeof envelope.message.id !== 'string' || envelope.message.id.length > 128 || typeof envelope.message.content !== 'string' || envelope.message.content.length > 16000) {
          this.send(ws, { type: 'error', reason: 'Invalid message' }); return;
        }
        const msg: ChatMessage = { id: envelope.message.id, roomId: envelope.roomId, senderId: existingClient!.user.id,
          senderName: existingClient!.user.displayName, senderAvatarURL: existingClient!.user.avatarURL, content: envelope.message.content,
          timestamp: new Date().toISOString(), status: 'sent' };
        if (envelope.message.replyToId) { const original = this.visibleHistory(existingClient!.user.id, envelope.roomId).find(m => m.id === envelope.message!.replyToId); if (!original) { this.send(ws, { type: 'error', reason: 'Reply unavailable' }); return; } msg.replyToId = original.id; }
        if (envelope.message.mediaAttachment) {
          const attachment = envelope.message.mediaAttachment;
          let filename: string;
          try { filename = path.basename(new URL(attachment.remoteURL ?? '', 'http://localhost').pathname); }
          catch { this.send(ws, { type: 'error', reason: 'Invalid attachment' }); return; }
          if (!this.auth.mediaBelongsToRoom(filename, envelope.roomId) || typeof attachment.fileName !== 'string' || typeof attachment.byteSize !== 'number' || !['image','video','audio','document'].includes(attachment.mediaType)) {
            this.send(ws, { type: 'error', reason: 'Invalid attachment' }); return;
          }
          msg.mediaAttachment = { id: randomUUID(), fileName: attachment.fileName.slice(0, 200), byteSize: attachment.byteSize, mimeType: attachment.mimeType, mediaType: attachment.mediaType, remoteURL: '/uploads/' + filename, durationSeconds: Number.isFinite(attachment.durationSeconds) ? Math.max(0, Math.min(3600, attachment.durationSeconds!)) : undefined };
        }

        serverLogger.info('MESSAGE_SENT', `New message in ${envelope.roomId} from ${msg.senderName}`, {
          clientId,
          ip,
          metadata: {
            messageId: msg.id,
            roomId: envelope.roomId,
            hasMedia: !!msg.mediaAttachment,
            mediaType: msg.mediaAttachment?.mediaType
          }
        });

        // Persist in memory history and to disk
        let list = this.messageHistory.get(envelope.roomId);
        if (!list) {
          list = [];
          this.messageHistory.set(envelope.roomId, list);
        }
        list.push(msg);
        this.saveMessages();
        if (this.auth.isDirectRoom(envelope.roomId)) { this.auth.activateDirectRoom(envelope.roomId); this.notifyCircleChange(envelope.roomId); }

        // Broadcast to all room participants
        this.broadcastToRoom(envelope.roomId, {
          type: 'message_received',
          roomId: envelope.roomId,
          message: msg,
        });
        break;
      }

      case 'typing': {
        if (!existingClient || !envelope.roomId) return;

        serverLogger.debug('TYPING_INDICATOR', `${existingClient.user.displayName} isTyping=${envelope.isTyping}`, {
          clientId,
          ip,
          metadata: { roomId: envelope.roomId, isTyping: !!envelope.isTyping }
        });

        this.broadcastToRoom(envelope.roomId, {
          type: 'typing_indicator',
          roomId: envelope.roomId,
          userId: existingClient.user.id,
          displayName: existingClient.user.displayName,
          isTyping: !!envelope.isTyping,
        }, ws);
        break;
      }

      case 'call_signal': {
        if (!envelope.callSignal || !envelope.roomId) return;
        if (typeof envelope.callSignal !== 'object' || !['offer','answer','ice_candidate','hangup','ping'].includes(envelope.callSignal.signalType)) { this.send(ws, { type: 'error', reason: 'Invalid call signal' }); return; }
        const sig = { ...envelope.callSignal, senderId: existingClient!.user.id, roomId: envelope.roomId };
        if (typeof sig.callId !== 'string' || sig.callId.length > 128 || typeof sig.isVideo !== 'boolean') { this.send(ws, { type: 'error', reason: 'Invalid call identity' }); return; }
        if (sig.targetId && !this.auth.canAccessRoom(sig.targetId, envelope.roomId)) { this.send(ws, { type: 'error', reason: 'Call target is not in this room' }); return; }

        serverLogger.info('CALL_SIGNAL', `Signaling event [${sig.signalType}] for call ${sig.callId}`, {
          clientId,
          ip,
          metadata: {
            callId: sig.callId,
            signalType: sig.signalType,
            roomId: envelope.roomId,
            targetId: sig.targetId,
            isVideo: sig.isVideo
          }
        });

        if (sig.signalType === 'offer' && !this.calls.some(c => c.id === sig.callId)) { const room = this.auth.chatRooms(existingClient!.user.id).find(r => r.id === envelope.roomId)!; this.calls.push({ id: sig.callId, roomId: sig.roomId, callerId: sig.senderId, date: new Date().toISOString(), isVideo: sig.isVideo, participantIds: room.participantIds }); this.calls = this.calls.slice(-2000); fs.writeFileSync(path.join(this.dataDir, 'calls.json'), JSON.stringify(this.calls), { mode: 0o600 }); }
        if (sig.targetId) {
          this.sendToUser(sig.targetId, {
            type: 'call_signal',
            roomId: envelope.roomId,
            callSignal: sig,
          });
        } else {
          this.broadcastToRoom(envelope.roomId, {
            type: 'call_signal',
            roomId: envelope.roomId,
            callSignal: sig,
          }, ws);
        }
        break;
      }

      case 'update_room_theme': {
        if (!envelope.roomId || !envelope.roomTheme) return;
        if (typeof envelope.roomTheme !== 'object' || !['preset','custom'].includes(envelope.roomTheme.themeType)) { this.send(ws, { type: 'error', reason: 'Invalid room theme' }); return; }
        const theme = { ...envelope.roomTheme, roomId: envelope.roomId };
        theme.updatedAt = new Date().toISOString();
        theme.updatedBy = existingClient?.user.displayName || 'Friend';

        this.roomThemes.set(envelope.roomId, theme);
        this.saveThemes();

        serverLogger.info('ROOM_THEME_UPDATED', `Room theme updated for [${envelope.roomId}]: ${theme.themeType}`, {
          clientId,
          ip,
          metadata: {
            roomId: envelope.roomId,
            themeType: theme.themeType,
            presetName: theme.presetName,
            wallpaperUrl: theme.wallpaperUrl,
            updatedBy: theme.updatedBy
          }
        });

        // Broadcast to all participants in the room
        this.broadcastToRoom(envelope.roomId, {
          type: 'room_theme_updated',
          roomId: envelope.roomId,
          roomTheme: theme
        });
        break;
      }

      case 'ping': {
        serverLogger.debug('WS_HEARTBEAT', 'Client ping received', { clientId, ip });
        this.send(ws, { type: 'pong' });
        break;
      }
    }
  }

  private handleClientDisconnect(ws: WebSocket, code: number, reason: string): void {
    const client = this.clients.get(ws);
    if (client) {
      serverLogger.info('WS_DISCONNECT', `Client disconnected: ${client.user.displayName} (${client.user.id}) code=${code}`, {
        clientId: client.user.id,
        ip: client.ip,
        metadata: { code, reason }
      });
      this.clients.delete(ws);
      if (![...this.clients.values()].some(c => c.user.id === client.user.id && this.active(c))) this.broadcastPresence(client.user.id, client.user.displayName, false);
    }
  }

  private active(client: ConnectedClient): boolean {
    try { this.auth.authenticate(client.token); return true; }
    catch { client.ws.close(1008, 'Session expired or revoked'); return false; }
  }

  private broadcastToRoom(roomId: string, envelope: ServerMessageEnvelope, excludeWs?: WebSocket): void {
    const payload = JSON.stringify(envelope);
    for (const [ws, client] of this.clients.entries()) {
      if (this.active(client) && ws !== excludeWs && client.joinedRooms.has(roomId) && this.auth.canAccessRoom(client.user.id, roomId) && ws.readyState === WebSocket.OPEN) {
        ws.send(payload);
      }
    }
  }

  private sendToUser(userId: string, envelope: ServerMessageEnvelope): void {
    const payload = JSON.stringify(envelope);
    for (const [ws, client] of this.clients.entries()) {
      if (this.active(client) && client.user.id === userId && ws.readyState === WebSocket.OPEN) {
        ws.send(payload);
      }
    }
  }

  private broadcastPresence(userId: string, displayName: string, isOnline: boolean): void {
    this.lastSeen.set(userId, new Date().toISOString());
    const payload = JSON.stringify({
      type: 'presence_updated',
      presence: {
        userId,
        displayName,
        isOnline,
        lastSeen: new Date().toISOString(),
      },
    });

    for (const [ws, client] of this.clients.entries()) {
      if (this.active(client) && this.auth.shareCircle(userId, client.user.id) && (this.profiles?.canSeePresence(client.user.id, userId) ?? true) && ws.readyState === WebSocket.OPEN) {
        ws.send(payload);
      }
    }
  }

  private send(ws: WebSocket, envelope: ServerMessageEnvelope): void {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(envelope));
    }
  }
}
