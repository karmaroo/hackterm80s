/**
 * Database Schema Initialization
 */

const { initPhonePool } = require('../utils/phone_pool');

/**
 * Check if a column exists in a table
 * @param {Database} db - SQLite database instance
 * @param {string} table - Table name
 * @param {string} column - Column name
 * @returns {boolean}
 */
function columnExists(db, table, column) {
  const info = db.prepare(`PRAGMA table_info(${table})`).all();
  return info.some(col => col.name === column);
}

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

  // Migrate players: add email column if missing
  if (!columnExists(db, 'players', 'email')) {
    console.log('  Adding email column to players');
    db.exec(`ALTER TABLE players ADD COLUMN email TEXT`);
  }

  // Create indexes
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_players_handle ON players(handle);
    CREATE INDEX IF NOT EXISTS idx_players_phone ON players(phone_number);
    CREATE INDEX IF NOT EXISTS idx_players_recovery ON players(recovery_code);
    CREATE INDEX IF NOT EXISTS idx_players_email ON players(email);
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

  // Migrate player_files: add new columns if missing
  if (!columnExists(db, 'player_files', 'content_hash')) {
    console.log('  Adding content_hash column to player_files');
    db.exec(`ALTER TABLE player_files ADD COLUMN content_hash TEXT`);
  }
  if (!columnExists(db, 'player_files', 'file_size')) {
    console.log('  Adding file_size column to player_files');
    db.exec(`ALTER TABLE player_files ADD COLUMN file_size INTEGER DEFAULT 0`);
  }
  if (!columnExists(db, 'player_files', 'program')) {
    console.log('  Adding program column to player_files');
    db.exec(`ALTER TABLE player_files ADD COLUMN program TEXT`);
  }
  if (!columnExists(db, 'player_files', 'updated_by_session')) {
    console.log('  Adding updated_by_session column to player_files');
    db.exec(`ALTER TABLE player_files ADD COLUMN updated_by_session TEXT`);
  }

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_player_files ON player_files(player_id);
    CREATE INDEX IF NOT EXISTS idx_player_files_updated ON player_files(player_id, updated_at);
  `);

  // File versions table (for version history, max 5 versions per file)
  db.exec(`
    CREATE TABLE IF NOT EXISTS file_versions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      player_id INTEGER NOT NULL REFERENCES players(id),
      path TEXT NOT NULL,
      version_number INTEGER NOT NULL,
      file_type TEXT NOT NULL,
      content TEXT,
      content_hash TEXT,
      file_size INTEGER,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_file_versions_lookup ON file_versions(player_id, path, version_number);
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

  // Active WebSocket sessions (for real-time sync)
  db.exec(`
    CREATE TABLE IF NOT EXISTS active_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_token TEXT UNIQUE NOT NULL,
      player_id INTEGER NOT NULL REFERENCES players(id),
      connected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      last_ping DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_active_sessions_player ON active_sessions(player_id);
  `);

  // Scene configurations (for edit mode)
  db.exec(`
    CREATE TABLE IF NOT EXISTS scene_configs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      player_id INTEGER REFERENCES players(id),
      config_name TEXT NOT NULL DEFAULT 'default',
      config_data TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(player_id, config_name)
    )
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_scene_configs_player ON scene_configs(player_id);
    CREATE INDEX IF NOT EXISTS idx_scene_configs_name ON scene_configs(config_name);
  `);

  // Global/default scene config (player_id = NULL means system default)
  // This stores the "master" layout all new players get
  const defaultExists = db.prepare(
    "SELECT id FROM scene_configs WHERE player_id IS NULL AND config_name = 'master'"
  ).get();

  if (!defaultExists) {
    console.log('  Creating default scene config placeholder');
    db.prepare(`
      INSERT INTO scene_configs (player_id, config_name, config_data)
      VALUES (NULL, 'master', '{"version":1,"elements":{}}')
    `).run();
  }

  console.log('Database schema initialized');

  // Initialize phone pool
  initPhonePool(db);
}

module.exports = { initDatabase };
