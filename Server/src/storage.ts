import * as fs from 'node:fs';
import * as path from 'node:path';
import * as http from 'node:http';
import { randomUUID } from 'node:crypto';

const UPLOADS_DIR = path.resolve(process.cwd(), 'uploads');

if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

export async function saveUploadedFile(req: http.IncomingMessage, fileName: string, uploadsDirectory = UPLOADS_DIR): Promise<{ savedPath: string; publicUrl: string; byteSize: number }> {
  return new Promise((resolve, reject) => {
    const rawExtension = path.extname(fileName).toLowerCase();
    const ext = /^\.[a-z0-9]{1,10}$/.test(rawExtension) ? rawExtension : '.bin';
    const uniqueName = `${randomUUID()}${ext}`;
    fs.mkdirSync(uploadsDirectory, { recursive: true });
    const destinationPath = path.join(uploadsDirectory, uniqueName);
    const writeStream = fs.createWriteStream(destinationPath);

    let totalBytes = 0;
    let settled = false;
    let failed = false;
    function fail(error: Error) {
      if (settled) return;
      settled = true; failed = true; writeStream.destroy(); reject(error);
    }
    writeStream.on('close', () => { if (failed) fs.unlink(destinationPath, () => {}); });
    req.on('aborted', () => fail(new Error('Upload aborted')));
    const MAX_ALLOWED_BYTES = 150 * 1024 * 1024; // 150 MB

    req.on('data', (chunk) => {
      totalBytes += chunk.length;
      if (totalBytes > MAX_ALLOWED_BYTES) {
        const error = new Error('File exceeds 150 MB limit.');
        fail(error); req.destroy(error);
      }
    });

    req.pipe(writeStream);

    writeStream.on('finish', () => {
      if (settled) return; settled = true;
      const publicUrl = `/uploads/${uniqueName}`;
      resolve({ savedPath: destinationPath, publicUrl, byteSize: totalBytes });
    });

    writeStream.on('error', (err) => {
      fail(err);
    });

    req.on('error', (err) => {
      reject(err);
    });
  });
}

export function streamMediaFile(req: http.IncomingMessage, res: http.ServerResponse, fileName: string, uploadsDirectory = UPLOADS_DIR): void {
  const safeFileName = path.basename(fileName);
  const filePath = path.join(uploadsDirectory, safeFileName);

  if (!fs.existsSync(filePath)) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'File not found' }));
    return;
  }

  const stat = fs.statSync(filePath);
  const fileSize = stat.size;
  const range = req.headers.range;

  // Detect MIME type
  let contentType = 'application/octet-stream';
  if (safeFileName.endsWith('.mp4')) contentType = 'video/mp4';
  else if (safeFileName.endsWith('.mov')) contentType = 'video/quicktime';
  else if (safeFileName.endsWith('.jpg') || safeFileName.endsWith('.jpeg')) contentType = 'image/jpeg';
  else if (safeFileName.endsWith('.png')) contentType = 'image/png';
  else if (safeFileName.endsWith('.gif')) contentType = 'image/gif';

  // HTTP Range request support (essential for iOS AVPlayer video scrubbing)
  if (range) {
    const match = /^bytes=(\d*)-(\d*)$/.exec(range);
    const start = match?.[1] ? Number(match[1]) : match?.[2] ? Math.max(0, fileSize - Number(match[2])) : NaN;
    const end = match?.[1] && match[2] ? Math.min(Number(match[2]), fileSize - 1) : fileSize - 1;
    if (!match || !Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start >= fileSize || end < start) {
      res.writeHead(416, { 'Content-Range': 'bytes */' + fileSize }); res.end(); return;
    }
    const chunksize = end - start + 1;
    const fileStream = fs.createReadStream(filePath, { start, end });

    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunksize,
      'Content-Type': contentType,
    });
    fileStream.on('error', () => res.destroy());
    fileStream.pipe(res);
  } else {
    res.writeHead(200, {
      'Content-Length': fileSize,
      'Content-Type': contentType,
      'Accept-Ranges': 'bytes',
    });
    const stream = fs.createReadStream(filePath);
    stream.on('error', () => res.destroy());
    stream.pipe(res);
  }
}
