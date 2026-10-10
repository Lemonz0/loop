import * as fs from 'node:fs';
import * as path from 'node:path';

export type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';

export interface LogRecord {
  timestamp: string;
  level: LogLevel;
  eventType: string;
  clientId?: string;
  ip?: string;
  message: string;
  metadata?: Record<string, any>;
}

class AppLogger {
  private logDirectory: string;
  private logFilePath: string;
  private logStream: fs.WriteStream | null = null;

  constructor() {
    this.logDirectory = path.resolve(process.cwd(), 'logs');
    this.logFilePath = path.join(this.logDirectory, 'app.log');
    this.initFileStream();
  }

  private initFileStream(): void {
    try {
      if (!fs.existsSync(this.logDirectory)) {
        fs.mkdirSync(this.logDirectory, { recursive: true });
      }
      this.logStream = fs.createWriteStream(this.logFilePath, { flags: 'a', encoding: 'utf-8' });
    } catch (err) {
      console.error('[Logger] Failed to initialize log file stream:', err);
    }
  }

  public log(
    level: LogLevel,
    eventType: string,
    message: string,
    options?: { clientId?: string; ip?: string; metadata?: Record<string, any> }
  ): void {
    const record: LogRecord = {
      timestamp: new Date().toISOString(),
      level,
      eventType,
      clientId: options?.clientId,
      ip: options?.ip,
      message,
      metadata: options?.metadata,
    };

    // 1. Console stream with color-coded tags
    const color = this.getLevelColor(level);
    const reset = '\x1b[0m';
    const clientTag = record.clientId ? ` [client:${record.clientId}]` : '';
    const ipTag = record.ip ? ` [ip:${record.ip}]` : '';
    const metaTag = record.metadata ? ` ${JSON.stringify(record.metadata)}` : '';

    console.log(
      `${color}[${record.timestamp}] [${record.level}] [${record.eventType}]${reset}${clientTag}${ipTag} ${record.message}${metaTag}`
    );

    // 2. Append to persistent app.log file in JSON line format
    if (this.logStream) {
      try {
        this.logStream.write(JSON.stringify(record) + '\n');
      } catch (err) {
        console.error('[Logger] File write failed:', err);
      }
    }
  }

  public debug(eventType: string, message: string, options?: { clientId?: string; ip?: string; metadata?: Record<string, any> }): void {
    this.log('DEBUG', eventType, message, options);
  }

  public info(eventType: string, message: string, options?: { clientId?: string; ip?: string; metadata?: Record<string, any> }): void {
    this.log('INFO', eventType, message, options);
  }

  public warn(eventType: string, message: string, options?: { clientId?: string; ip?: string; metadata?: Record<string, any> }): void {
    this.log('WARN', eventType, message, options);
  }

  public error(eventType: string, message: string, options?: { clientId?: string; ip?: string; metadata?: Record<string, any> }): void {
    this.log('ERROR', eventType, message, options);
  }

  private getLevelColor(level: LogLevel): string {
    switch (level) {
      case 'DEBUG':
        return '\x1b[36m'; // Cyan
      case 'INFO':
        return '\x1b[32m'; // Green
      case 'WARN':
        return '\x1b[33m'; // Yellow
      case 'ERROR':
        return '\x1b[31m'; // Red
      default:
        return '\x1b[0m';
    }
  }
}

export const serverLogger = new AppLogger();
