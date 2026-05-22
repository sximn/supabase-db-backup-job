const express = require('express');
const { spawn } = require('child_process');
const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');

const app = express();
const BACKUPS_DIR = process.env.BACKUPS_DIR || '/backups';
const PORT = Number.parseInt(process.env.PORT || '3000', 10);
const UI_USER = process.env.BACKUP_UI_USER || 'admin';
const UI_PASSWORD = process.env.BACKUP_UI_PASSWORD;
const BACKUP_NAME_RE = /^backup-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-UTC\.tar\.zst$/;

if (!UI_PASSWORD) {
  console.error('BACKUP_UI_PASSWORD is required. Refusing to start an unauthenticated backup console.');
  process.exit(1);
}

app.disable('x-powered-by');
app.set('trust proxy', true);
app.use(express.json());

app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'same-origin');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  res.setHeader('Cache-Control', 'no-store');
  next();
});

app.get('/healthz', (req, res) => res.json({ ok: true }));

function safeCompare(a, b) {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function requireBasicAuth(req, res, next) {
  const header = req.get('authorization') || '';
  const [scheme, credentials] = header.split(' ');

  if (scheme === 'Basic' && credentials) {
    const decoded = Buffer.from(credentials, 'base64').toString('utf8');
    const separator = decoded.indexOf(':');
    const user = separator === -1 ? '' : decoded.slice(0, separator);
    const password = separator === -1 ? '' : decoded.slice(separator + 1);

    if (safeCompare(user, UI_USER) && safeCompare(password, UI_PASSWORD)) {
      return next();
    }
  }

  res.setHeader('WWW-Authenticate', 'Basic realm="Supabase Backup Manager", charset="UTF-8"');
  return res.status(401).json({ error: 'Authentication required' });
}

function requireSameOrigin(req, res, next) {
  if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) return next();

  const source = req.get('origin') || req.get('referer');
  if (!source) return res.status(403).json({ error: 'Missing origin' });

  try {
    const sourceUrl = new URL(source);
    if (sourceUrl.host === req.get('host')) return next();
  } catch {
    return res.status(403).json({ error: 'Invalid origin' });
  }

  return res.status(403).json({ error: 'Cross-origin request blocked' });
}

function backupPath(name) {
  if (!BACKUP_NAME_RE.test(name)) return null;
  return path.join(BACKUPS_DIR, name);
}

app.use(requireBasicAuth);
app.use(requireSameOrigin);
app.use(express.static('public'));

// List backups sorted by creation time (newest first)
app.get('/api/backups', async (req, res, next) => {
  try {
    await fs.mkdir(BACKUPS_DIR, { recursive: true });
    const entries = await fs.readdir(BACKUPS_DIR);
    const files = await Promise.all(
      entries
        .filter((name) => backupPath(name))
        .map(async (name) => {
          const stat = await fs.stat(path.join(BACKUPS_DIR, name));
          return { name, size: stat.size, createdAt: stat.mtime };
        })
    );

    files.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    res.json(files);
  } catch (err) {
    next(err);
  }
});

// Download a backup
app.get('/api/backups/:name', async (req, res, next) => {
  try {
    const file = backupPath(req.params.name);
    if (!file) return res.status(400).json({ error: 'Invalid backup name' });

    await fs.access(file);
    return res.download(file);
  } catch (err) {
    if (err.code === 'ENOENT') return res.status(404).json({ error: 'Not found' });
    return next(err);
  }
});

// Delete a backup
app.delete('/api/backups/:name', async (req, res, next) => {
  try {
    const file = backupPath(req.params.name);
    if (!file) return res.status(400).json({ error: 'Invalid backup name' });

    await fs.unlink(file);
    return res.json({ ok: true });
  } catch (err) {
    if (err.code === 'ENOENT') return res.status(404).json({ error: 'Not found' });
    return next(err);
  }
});

let runningBackup = null;

// Trigger backup manually
app.post('/api/backup/run', (req, res) => {
  if (runningBackup) {
    return res.status(409).json({ error: 'Backup already running' });
  }

  const child = spawn('/app/backup.sh', {
    stdio: ['ignore', 'pipe', 'pipe'],
    env: process.env,
  });

  runningBackup = child;
  res.status(202).json({ ok: true, message: 'Backup started in background' });

  child.stdout.on('data', (chunk) => process.stdout.write(chunk));
  child.stderr.on('data', (chunk) => process.stderr.write(chunk));
  child.on('close', (code) => {
    runningBackup = null;
    if (code === 0) console.log('Backup completed successfully');
    else console.error(`Backup failed with exit code ${code}`);
  });
});

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

const server = app.listen(PORT, () => console.log(`Backup UI running on :${PORT}`));
server.on('error', (err) => {
  console.error(`Failed to start server on port ${PORT}:`, err);
  process.exit(1);
});
