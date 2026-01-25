/**
 * Player Registration and Recovery Routes
 */

const express = require('express');
const crypto = require('crypto');
const router = express.Router();
const { generateRecoveryCode } = require('../utils/recovery_code');
const { allocatePhoneNumber, getPoolStats } = require('../utils/phone_pool');

/**
 * POST /api/register
 * Register a new player with a handle
 */
router.post('/register', (req, res) => {
  const { handle, browser_id } = req.body;
  const db = req.db;

  // Validate handle
  if (!handle || typeof handle !== 'string') {
    return res.status(400).json({
      success: false,
      error: 'INVALID_HANDLE',
      message: 'Handle is required'
    });
  }

  const cleanHandle = handle.toUpperCase().trim();

  if (cleanHandle.length < 3 || cleanHandle.length > 12) {
    return res.status(400).json({
      success: false,
      error: 'INVALID_HANDLE',
      message: 'Handle must be 3-12 characters'
    });
  }

  // Check for valid characters (alphanumeric, underscore, hyphen)
  if (!/^[A-Z0-9_-]+$/.test(cleanHandle)) {
    return res.status(400).json({
      success: false,
      error: 'INVALID_HANDLE',
      message: 'Handle can only contain letters, numbers, underscore, and hyphen'
    });
  }

  // Check if handle already exists
  const existing = db.prepare('SELECT id FROM players WHERE handle = ?').get(cleanHandle);
  if (existing) {
    return res.status(409).json({
      success: false,
      error: 'HANDLE_TAKEN',
      message: 'Handle already registered'
    });
  }

  // Check pool availability
  const stats = getPoolStats(db);
  if (stats.available === 0) {
    return res.status(503).json({
      success: false,
      error: 'NO_NUMBERS',
      message: 'No phone numbers available'
    });
  }

  // Generate recovery code
  let recoveryCode;
  let attempts = 0;
  do {
    recoveryCode = generateRecoveryCode();
    const existingCode = db.prepare('SELECT id FROM players WHERE recovery_code = ?').get(recoveryCode);
    if (!existingCode) break;
    attempts++;
  } while (attempts < 10);

  if (attempts >= 10) {
    return res.status(500).json({
      success: false,
      error: 'INTERNAL_ERROR',
      message: 'Could not generate unique recovery code'
    });
  }

  // Start transaction
  const createPlayer = db.transaction(() => {
    // Create player (phone number will be null initially)
    const result = db.prepare(`
      INSERT INTO players (handle, phone_number, recovery_code)
      VALUES (?, '', ?)
    `).run(cleanHandle, recoveryCode);

    const playerId = result.lastInsertRowid;

    // Allocate phone number
    const phoneNumber = allocatePhoneNumber(db, playerId);
    if (!phoneNumber) {
      throw new Error('Failed to allocate phone number');
    }

    // Update player with phone number
    db.prepare('UPDATE players SET phone_number = ? WHERE id = ?').run(phoneNumber, playerId);

    // Generate session token
    const sessionToken = crypto.randomBytes(32).toString('hex');

    // Create session
    db.prepare(`
      INSERT INTO sessions (player_id, token, browser_id, expires_at)
      VALUES (?, ?, ?, datetime('now', '+30 days'))
    `).run(playerId, sessionToken, browser_id || null);

    return {
      playerId,
      phoneNumber,
      sessionToken
    };
  });

  try {
    const { phoneNumber, sessionToken } = createPlayer();

    console.log(`[REGISTER] New player: ${cleanHandle} (${phoneNumber})`);

    res.json({
      success: true,
      handle: cleanHandle,
      phone_number: phoneNumber,
      recovery_code: recoveryCode,
      session_token: sessionToken
    });
  } catch (error) {
    console.error('[REGISTER] Error:', error.message);
    res.status(500).json({
      success: false,
      error: 'INTERNAL_ERROR',
      message: 'Registration failed'
    });
  }
});

/**
 * POST /api/recover
 * Recover a session using recovery code
 */
router.post('/recover', (req, res) => {
  const { recovery_code, browser_id } = req.body;
  const db = req.db;

  if (!recovery_code) {
    return res.status(400).json({
      success: false,
      error: 'MISSING_CODE',
      message: 'Recovery code is required'
    });
  }

  const code = recovery_code.toUpperCase().trim();

  // Find player by recovery code
  const player = db.prepare(`
    SELECT id, handle, phone_number FROM players
    WHERE recovery_code = ?
  `).get(code);

  if (!player) {
    return res.status(404).json({
      success: false,
      error: 'INVALID_CODE',
      message: 'Recovery code not found'
    });
  }

  // Generate new session token for this device
  const sessionToken = crypto.randomBytes(32).toString('hex');

  // Create session
  db.prepare(`
    INSERT INTO sessions (player_id, token, browser_id, expires_at)
    VALUES (?, ?, ?, datetime('now', '+30 days'))
  `).run(player.id, sessionToken, browser_id || null);

  // Update last seen
  db.prepare('UPDATE players SET last_seen = CURRENT_TIMESTAMP WHERE id = ?').run(player.id);

  console.log(`[RECOVER] Player recovered: ${player.handle}`);

  res.json({
    success: true,
    handle: player.handle,
    phone_number: player.phone_number,
    session_token: sessionToken
  });
});

/**
 * GET /api/player/:handle
 * Lookup player by handle
 */
router.get('/player/:handle', (req, res) => {
  const handle = req.params.handle.toUpperCase();
  const db = req.db;

  const player = db.prepare(`
    SELECT handle, phone_number, created_at FROM players WHERE handle = ?
  `).get(handle);

  if (!player) {
    return res.status(404).json({ error: 'NOT_FOUND' });
  }

  res.json({
    handle: player.handle,
    phone_number: player.phone_number,
    registered: player.created_at
  });
});

/**
 * GET /api/phone/:number
 * Lookup player by phone number
 */
router.get('/phone/:number', (req, res) => {
  const number = req.params.number;
  const db = req.db;

  const player = db.prepare(`
    SELECT handle, phone_number FROM players WHERE phone_number = ?
  `).get(number);

  if (!player) {
    return res.status(404).json({ error: 'NOT_FOUND' });
  }

  res.json({
    handle: player.handle,
    phone_number: player.phone_number
  });
});

/**
 * GET /api/stats
 * Get server statistics (for debugging/admin)
 */
router.get('/stats', (req, res) => {
  const db = req.db;

  const playerCount = db.prepare('SELECT COUNT(*) as count FROM players').get();
  const poolStats = getPoolStats(db);

  res.json({
    players: playerCount.count,
    phone_pool: poolStats
  });
});

module.exports = router;
