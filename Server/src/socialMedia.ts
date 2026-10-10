import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { ApiError, AuthStore } from './auth.js';
let photoWork = 0;
export async function uploadSocialPhoto(req: http.IncomingMessage, auth: AuthStore, userId: string, circleId: string, directory: string) {
  auth.members(userId, circleId);
  if (photoWork >= 2) throw new ApiError(429, 'Photo processing is busy; try again');
  photoWork++;
  try {
    const chunks: Buffer[] = []; let size = 0;
    for await (const chunk of req) { size += chunk.length; if (size > 20 * 1024 * 1024) throw new ApiError(413, 'Photo must be under 20 MB'); chunks.push(Buffer.from(chunk)); }
    const input = Buffer.concat(chunks);
    // Reject SVG/PDF and other active formats before passing bytes to an image decoder.
    const supported = input.subarray(0,3).equals(Buffer.from([255,216,255])) || input.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])) || input.subarray(0,6).toString().startsWith('GIF8') || (input.subarray(0,4).toString() === 'RIFF' && input.subarray(8,12).toString() === 'WEBP');
    if (!supported) throw new ApiError(415, 'Choose a JPEG, PNG, GIF, or WebP photo');
    let result;
    try { result = await sharp(input, { limitInputPixels: 40000000 }).autoOrient().resize({ width: 2048, height: 2048, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 85 }).toBuffer({ resolveWithObject: true }); }
    catch { throw new ApiError(415, 'This image could not be processed'); }
    fs.mkdirSync(directory, { recursive: true }); const filename = randomUUID() + '.jpg';
    fs.writeFileSync(path.join(directory, filename), result.data, { mode: 0o600, flag: 'wx' });
    auth.registerMedia(userId, circleId, filename, { width: result.info.width, height: result.info.height });
    return { fileUrl: '/uploads/' + filename, byteSize: result.data.length, width: result.info.width, height: result.info.height };
  } finally { photoWork--; }
}
