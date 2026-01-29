/**
 * HackTerm80s Multiplayer Backend API
 * Node.js/Express server with SQLite database
 * WebSocket support for real-time multi-device sync
 */

const express = require('express');
const http = require('http');
const cors = require('cors');
const path = require('path');
const Database = require('better-sqlite3');
const { initDatabase } = require('./db/init');
const playersRouter = require('./routes/players');
const filesystemRouter = require('./routes/filesystem');
const sceneRouter = require('./routes/scene');
const aiRouter = require('./routes/ai');
const { initWebSocket, getTotalConnections } = require('./websocket');
const { initEmailTransporter } = require('./utils/email');

const app = express();
const server = http.createServer(app);
const PORT = process.env.PORT || 3000;

// Database setup
const dbPath = process.env.DB_PATH || path.join(__dirname, 'db', 'hackterm.db');
console.log(`Database path: ${dbPath}`);

const db = new Database(dbPath);
initDatabase(db);

// Initialize email transporter
initEmailTransporter();

// Add all CORS and COEP headers BEFORE other middleware
app.use((req, res, next) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Session-Token, Authorization');
  res.setHeader('Access-Control-Allow-Credentials', 'true');

  // COEP compatibility
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');

  // Prevent caching
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');

  // Handle preflight immediately
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  next();
});

// Keep cors middleware for additional handling
app.use(cors({
  origin: true,
  credentials: true
}));

app.use(express.json({ limit: '1mb' }));

// Attach db to all requests
app.use((req, res, next) => {
  req.db = db;
  next();
});

// Request logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`${req.method} ${req.path} ${res.statusCode} ${duration}ms`);
  });
  next();
});

// Routes
app.use('/api', playersRouter);
app.use('/api', filesystemRouter);
app.use('/api', sceneRouter);
app.use('/api/assets', aiRouter);

// Health check / status endpoint
app.get('/api/status', (req, res) => {
  res.json({
    status: 'online',
    version: '1.0.0',
    timestamp: Date.now(),
    websocket_connections: getTotalConnections()
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({
    success: false,
    error: 'INTERNAL_ERROR',
    message: 'An unexpected error occurred'
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'NOT_FOUND',
    message: 'Endpoint not found'
  });
});

// Initialize WebSocket server
initWebSocket(server, db);

// Start server
server.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('========================================');
  console.log('  HackTerm80s Multiplayer API Server');
  console.log('========================================');
  console.log(`  Port: ${PORT}`);
  console.log(`  Database: ${dbPath}`);
  console.log('');
  console.log('  REST Endpoints:');
  console.log('    POST /api/register    - Register new player');
  console.log('    POST /api/recover     - Recover session');
  console.log('    GET  /api/player/:h   - Lookup by handle');
  console.log('    GET  /api/phone/:n    - Lookup by phone');
  console.log('    GET  /api/filesystem  - Get filesystem');
  console.log('    PUT  /api/filesystem  - Sync filesystem');
  console.log('    POST /api/files       - Create/update file');
  console.log('    POST /api/dirs        - Create directory');
  console.log('    GET  /api/versions    - File version history');
  console.log('    POST /api/batch       - Batch operations');
  console.log('    GET  /api/sync        - Incremental sync');
  console.log('    GET  /api/stats       - Server stats');
  console.log('    GET  /api/status      - Health check');
  console.log('');
  console.log('  AI Generation:');
  console.log('    POST /api/assets/generate        - Generate AI asset');
  console.log('    GET  /api/assets/generate/status - Check AI status');
  console.log('    GET  /api/assets/generate/presets - Get style presets');
  console.log('');
  console.log('  WebSocket: ws://localhost:' + PORT + '/ws');
  console.log('========================================');
  console.log('');
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\\nShutting down...');
  db.close();
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('\\nShutting down...');
  db.close();
  process.exit(0);
});
