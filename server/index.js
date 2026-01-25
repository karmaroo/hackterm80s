/**
 * HackTerm80s Multiplayer Backend API
 * Node.js/Express server with SQLite database
 */

const express = require('express');
const cors = require('cors');
const path = require('path');
const Database = require('better-sqlite3');
const { initDatabase } = require('./db/init');
const playersRouter = require('./routes/players');
const filesystemRouter = require('./routes/filesystem');

const app = express();
const PORT = process.env.PORT || 3000;

// Database setup
const dbPath = process.env.DB_PATH || path.join(__dirname, 'db', 'hackterm.db');
console.log(`Database path: ${dbPath}`);

const db = new Database(dbPath);
initDatabase(db);

// Middleware
app.use(cors({
  origin: [
    'http://localhost:9080',
    'http://localhost:8080',
    'http://127.0.0.1:9080',
    /\.localhost$/
  ],
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

// Health check / status endpoint
app.get('/api/status', (req, res) => {
  res.json({
    status: 'online',
    version: '1.0.0',
    timestamp: Date.now()
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

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('========================================');
  console.log('  HackTerm80s Multiplayer API Server');
  console.log('========================================');
  console.log(`  Port: ${PORT}`);
  console.log(`  Database: ${dbPath}`);
  console.log('');
  console.log('  Endpoints:');
  console.log('    POST /api/register    - Register new player');
  console.log('    POST /api/recover     - Recover session');
  console.log('    GET  /api/player/:h   - Lookup by handle');
  console.log('    GET  /api/phone/:n    - Lookup by phone');
  console.log('    GET  /api/filesystem  - Get filesystem');
  console.log('    PUT  /api/filesystem  - Sync filesystem');
  console.log('    GET  /api/stats       - Server stats');
  console.log('    GET  /api/status      - Health check');
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
