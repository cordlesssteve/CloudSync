#!/usr/bin/env node
/**
 * CloudSync Web Dashboard Server
 * Provides real-time monitoring and management interface for CloudSync
 */

const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const fs = require('fs').promises;
const path = require('path');
const { spawn, exec } = require('child_process');
const cron = require('node-cron');
const chokidar = require('chokidar');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

const PORT = process.env.PORT || 3000;
const PROJECT_ROOT = path.resolve(__dirname, '..');
const CONFIG_PATH = path.join(PROJECT_ROOT, 'config', 'cloudsync.conf');
const HOME_DIR = process.env.HOME;
const CLOUDSYNC_DIR = path.join(HOME_DIR, '.cloudsync');

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Global state
let systemStatus = {
  lastUpdate: new Date(),
  health: {},
  features: {},
  conflicts: [],
  stats: {},
  isOnline: false
};

/**
 * Parse CloudSync configuration file
 */
async function loadConfig() {
  try {
    const configContent = await fs.readFile(CONFIG_PATH, 'utf8');
    const config = {};

    configContent.split('\n').forEach(line => {
      line = line.trim();
      if (line && !line.startsWith('#')) {
        const [key, value] = line.split('=').map(s => s.trim());
        if (key && value) {
          // Remove quotes and parse value
          let parsedValue = value.replace(/^["']|["']$/g, '');
          if (parsedValue === 'true') parsedValue = true;
          else if (parsedValue === 'false') parsedValue = false;
          else if (!isNaN(parsedValue)) parsedValue = Number(parsedValue);

          config[key] = parsedValue;
        }
      }
    });

    return config;
  } catch (error) {
    console.error('Error loading config:', error.message);
    return {};
  }
}

/**
 * Execute shell command and return result
 */
function executeCommand(command, args = []) {
  return new Promise((resolve, reject) => {
    const process = spawn(command, args, {
      cwd: PROJECT_ROOT,
      env: { ...process.env, PATH: process.env.PATH }
    });

    let stdout = '';
    let stderr = '';

    process.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    process.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    process.on('close', (code) => {
      if (code === 0) {
        resolve({ stdout, stderr, exitCode: code });
      } else {
        reject({ stdout, stderr, exitCode: code });
      }
    });

    process.on('error', (error) => {
      reject({ error: error.message, exitCode: -1 });
    });
  });
}

/**
 * Run health check and update system status
 */
async function updateSystemHealth() {
  try {
    console.log('Running health check...');
    const healthScript = path.join(PROJECT_ROOT, 'scripts', 'monitoring', 'sync-health-check.sh');

    const result = await executeCommand('bash', [healthScript]);

    // Parse health check output
    const health = {
      lastCheck: new Date(),
      rcloneConnectivity: result.stdout.includes('✅ rclone connectivity: OK'),
      conflicts: result.stdout.includes('No conflicts detected') ? 0 :
                parseInt(result.stdout.match(/Found (\d+) conflict files/)?.[1] || '0'),
      diskUsage: parseInt(result.stdout.match(/Disk usage: (\d+)%/)?.[1] || '0'),
      features: {
        smartDeduplication: result.stdout.includes('✅ Smart Deduplication'),
        checksumVerification: result.stdout.includes('✅ Checksum Verification'),
        bidirectionalSync: result.stdout.includes('✅ Bidirectional Sync'),
        conflictResolution: result.stdout.includes('✅ Conflict Resolution')
      }
    };

    systemStatus.health = health;
    systemStatus.lastUpdate = new Date();
    systemStatus.isOnline = true;

    // Read additional stats files
    await loadAdditionalStats();

    // Emit to all connected clients
    io.emit('systemStatus', systemStatus);

  } catch (error) {
    console.error('Health check failed:', error);
    systemStatus.isOnline = false;
    systemStatus.lastUpdate = new Date();
    io.emit('systemStatus', systemStatus);
  }
}

/**
 * Load additional statistics from JSON files
 */
async function loadAdditionalStats() {
  try {
    // Load bisync stats
    const bisyncStatsPath = path.join(CLOUDSYNC_DIR, 'last-bisync-stats.json');
    try {
      const bisyncStats = await fs.readFile(bisyncStatsPath, 'utf8');
      systemStatus.stats.lastBisync = JSON.parse(bisyncStats);
    } catch (e) {
      systemStatus.stats.lastBisync = null;
    }

    // Load last sync timestamp
    try {
      const lastSyncPath = path.join(CLOUDSYNC_DIR, 'last-sync');
      const lastSync = await fs.readFile(lastSyncPath, 'utf8');
      systemStatus.stats.lastSync = lastSync.trim();
    } catch (e) {
      systemStatus.stats.lastSync = null;
    }

    // Load feature timestamps
    const featureFiles = ['last-dedupe', 'last-checksum-verify', 'last-bisync'];
    systemStatus.stats.features = {};

    for (const file of featureFiles) {
      try {
        const content = await fs.readFile(path.join(CLOUDSYNC_DIR, file), 'utf8');
        systemStatus.stats.features[file] = content.trim();
      } catch (e) {
        systemStatus.stats.features[file] = null;
      }
    }

  } catch (error) {
    console.error('Error loading additional stats:', error);
  }
}

/**
 * Get conflict information
 */
async function getConflicts() {
  try {
    const conflictDir = path.join(CLOUDSYNC_DIR, 'conflicts');
    const conflictFile = path.join(conflictDir, 'detected-conflicts.txt');

    try {
      const conflicts = await fs.readFile(conflictFile, 'utf8');
      return conflicts.split('\n').filter(line => line.trim()).map(line => ({
        file: line.trim(),
        detected: new Date() // We'd need to parse the actual timestamp from logs
      }));
    } catch (e) {
      return [];
    }
  } catch (error) {
    console.error('Error getting conflicts:', error);
    return [];
  }
}

// API Routes

/**
 * Get current system status
 */
app.get('/api/status', async (req, res) => {
  res.json(systemStatus);
});

/**
 * Get configuration
 */
app.get('/api/config', async (req, res) => {
  try {
    const config = await loadConfig();
    res.json(config);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Get logs
 */
app.get('/api/logs/:type', async (req, res) => {
  try {
    const { type } = req.params;
    const { lines = 100 } = req.query;

    let logFile;
    switch (type) {
      case 'health':
        logFile = path.join(CLOUDSYNC_DIR, 'health-check.log');
        break;
      case 'sync':
        logFile = path.join(CLOUDSYNC_DIR, 'bisync.log');
        break;
      case 'dedupe':
        logFile = path.join(CLOUDSYNC_DIR, 'dedupe.log');
        break;
      default:
        return res.status(400).json({ error: 'Invalid log type' });
    }

    try {
      const result = await executeCommand('tail', ['-n', lines.toString(), logFile]);
      res.json({
        logs: result.stdout.split('\n').filter(line => line.trim()),
        file: logFile
      });
    } catch (e) {
      res.json({ logs: [], file: logFile, error: 'Log file not found' });
    }

  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Run sync operation
 */
app.post('/api/sync', async (req, res) => {
  try {
    const { type = 'bidirectional', dryRun = false, options = {} } = req.body;

    let scriptPath;
    let args = [];

    switch (type) {
      case 'bidirectional':
        scriptPath = path.join(PROJECT_ROOT, 'scripts', 'core', 'bidirectional-sync.sh');
        if (dryRun) args.push('--dry-run');
        break;
      case 'dedupe':
        scriptPath = path.join(PROJECT_ROOT, 'scripts', 'core', 'smart-dedupe.sh');
        if (dryRun) args.push('--dry-run');
        break;
      case 'checksum':
        scriptPath = path.join(PROJECT_ROOT, 'scripts', 'core', 'checksum-verify.sh');
        break;
      default:
        return res.status(400).json({ error: 'Invalid sync type' });
    }

    // Add additional options
    Object.entries(options).forEach(([key, value]) => {
      if (value) {
        args.push(`--${key}`);
        if (typeof value === 'string' && value !== 'true') {
          args.push(value);
        }
      }
    });

    console.log(`Starting sync: ${type}, args:`, args);

    // Start sync in background and return immediately
    const syncProcess = spawn('bash', [scriptPath, ...args], {
      cwd: PROJECT_ROOT,
      detached: true,
      stdio: 'pipe'
    });

    let output = '';
    syncProcess.stdout.on('data', (data) => {
      output += data.toString();
      // Emit real-time output to clients
      io.emit('syncProgress', {
        type,
        output: data.toString(),
        timestamp: new Date()
      });
    });

    syncProcess.stderr.on('data', (data) => {
      output += data.toString();
      io.emit('syncProgress', {
        type,
        output: data.toString(),
        error: true,
        timestamp: new Date()
      });
    });

    syncProcess.on('close', (code) => {
      io.emit('syncComplete', {
        type,
        exitCode: code,
        output,
        timestamp: new Date()
      });

      // Update system health after sync
      setTimeout(updateSystemHealth, 2000);
    });

    res.json({
      message: `${type} sync started`,
      pid: syncProcess.pid,
      dryRun
    });

  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Get conflicts
 */
app.get('/api/conflicts', async (req, res) => {
  try {
    const conflicts = await getConflicts();
    res.json(conflicts);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Serve the main dashboard
 */
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Socket.io for real-time updates
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);

  // Send current status immediately
  socket.emit('systemStatus', systemStatus);

  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });

  socket.on('requestUpdate', () => {
    updateSystemHealth();
  });
});

// File watchers for real-time updates
function setupFileWatchers() {
  const watchPaths = [
    path.join(CLOUDSYNC_DIR, '*.log'),
    path.join(CLOUDSYNC_DIR, '*.json'),
    path.join(CLOUDSYNC_DIR, 'last-*')
  ];

  watchPaths.forEach(watchPath => {
    chokidar.watch(watchPath, { ignoreInitial: true }).on('change', () => {
      console.log('File changed, updating status...');
      setTimeout(updateSystemHealth, 1000);
    });
  });
}

// Scheduled health checks every 5 minutes
cron.schedule('*/5 * * * *', () => {
  console.log('Scheduled health check');
  updateSystemHealth();
});

// Initialize
async function initialize() {
  try {
    await updateSystemHealth();
    setupFileWatchers();

    server.listen(PORT, () => {
      console.log(`CloudSync Dashboard running on http://localhost:${PORT}`);
      console.log('Press Ctrl+C to stop');
    });
  } catch (error) {
    console.error('Failed to initialize:', error);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down gracefully...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  server.close(() => {
    process.exit(0);
  });
});

// Start the server
initialize().catch(console.error);