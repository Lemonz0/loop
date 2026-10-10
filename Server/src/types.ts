export interface UserProfile {
  id: string;
  username: string;
  displayName: string;
  avatarURL?: string;
  allowsTrollPosts?: boolean;
}

export interface AuthSession {
  token: string;
  user: UserProfile;
  issuedAt: string;
  expiresAt: string;
}

export interface MediaAttachment {
  id: string;
  fileName: string;
  mimeType: string;
  byteSize: number;
  localURL?: string;
  remoteURL?: string;
  thumbnailURL?: string;
  width?: number;
  height?: number;
  durationSeconds?: number;
  mediaType: 'image' | 'video' | 'audio' | 'document';
}

export interface ChatMessage {
  id: string;
  roomId: string;
  senderId: string;
  senderName: string;
  senderAvatarURL?: string;
  content: string;
  mediaAttachment?: MediaAttachment;
  timestamp: string;
  status: 'sending' | 'sent' | 'delivered' | 'read' | 'failed';
  isFromCurrentUser?: boolean;
}

export interface CallSignalPayload {
  callId: string;
  roomId: string;
  senderId: string;
  targetId?: string;
  signalType: 'offer' | 'answer' | 'ice_candidate' | 'hangup' | 'ping';
  sdp?: string;
  sdpMid?: string;
  sdpMLineIndex?: number;
  candidate?: string;
  isVideo: boolean;
}

export interface RoomTheme {
  roomId: string;
  themeType: 'preset' | 'custom';
  presetName?: 'onyx' | 'aurora' | 'daylight' | 'slate' | 'frost';
  wallpaperUrl?: string;
  updatedBy: string;
  updatedAt: string;
}

export interface ClientMessageEnvelope {
  type: 'auth' | 'join_room' | 'leave_room' | 'send_message' | 'typing' | 'call_signal' | 'ping' | 'update_room_theme';
  token?: string;
  user?: UserProfile;
  roomId?: string;
  message?: ChatMessage;
  isTyping?: boolean;
  callSignal?: CallSignalPayload;
  roomTheme?: RoomTheme;
}

export interface ServerMessageEnvelope {
  type: 'authenticated' | 'message_received' | 'message_status_updated' | 'typing_indicator' | 'presence_updated' | 'call_signal' | 'room_history' | 'room_theme_updated' | 'pong' | 'error' | 'account_updated';
  user?: UserProfile;
  roomId?: string;
  message?: ChatMessage;
  messageId?: string;
  status?: string;
  userId?: string;
  displayName?: string;
  isTyping?: boolean;
  presence?: {
    userId: string;
    displayName: string;
    isOnline: boolean;
    lastSeen: string;
  };
  callSignal?: CallSignalPayload;
  history?: ChatMessage[];
  roomTheme?: RoomTheme;
  reason?: string;
}
