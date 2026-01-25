/**
 * Database Schema Initialization
 */

const { initPhonePool } = require('../utils/phone_pool');

/**
 * Initialize database schema
 * @param {Database} db - SQLite database instance
 */
function initDatabase(db) {
  console.log('Initializing database schema...');

  // Enable foreign keys
  db.pragma('foreign_keys = ON');

  // Players table
  db.exec(`
    CREATE TABLE IF NOT EXISTS players (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      handle TEXT UNIQUE NOT NULL,
      phone_number TEXT UNIQUE NOT NULL,
      recovery_code TEXT UNIQUE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      last_seen DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);

  // Create indexes
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_players_handle ON players(handle);
    CREATE INDEX IF NOT EXISTS idx_players_phone ON players(phone_number);
    CREATE INDEX IF NOT EXISTS idx_players_recovery ON players(recovery_code);
  `);

  // Phone number pool
  db.exec(`
    CREATE TABLE IF NOT EXISTS phone_pool (
      number TEXT PRIMARY KEY,
      allocated INTEGER DEFAULT 0,
      player_id INTEGER REFERENCES players(id)
    )
  `);

  // Player filesystems
  db.exec(`
    CREATE TABLE IF NOT EXISTS player_files (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      player_id INTEGER NOT NULL REFERENCES players(id),
      path TEXT NOT NULL,
      file_type TEXT NOT NULL,
      content TEXT,
      metadata TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(player_id, path)
    )
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_player_files ON player_files(player_id);
  `);

  // Session tokens
  db.exec(`
    CREATE TABLE IF NOT EXISTS sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      player_id INTEGER NOT NULL REFERENCES players(id),
      token TEXT UNIQUE NOT NULL,
      browser_id TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      expires_at DATETIME
    )
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token);
    CREATE INDEX IF NOT EXISTS idx_sessions_player ON sessions(player_id);
  `);

  console.log('Database schema initialized');

  // Initialize phone pool
  initPhonePool(db);
}

module.exports = { initDatabase };
