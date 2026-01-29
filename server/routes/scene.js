/**
 * Scene Configuration Routes
 * Manages saving/loading of edit mode scene layouts per player
 */

const express = require('express');
const router = express.Router();

/**
 * Validate session token and return player info
 * @param {object} db - Database instance
 * @param {string} token - Session token
 * @returns {object|null} Player info or null if invalid
 */
function validateToken(db, token) {
  if (!token) return null;

  const session = db.prepare(`
    SELECT s.player_id, s.token, p.handle, p.id as player_id
    FROM sessions s
    JOIN players p ON s.player_id = p.id
    WHERE s.token = ? AND (s.expires_at IS NULL OR s.expires_at > datetime('now'))
  `).get(token);

  return session || null;
}

/**
 * Extract token from request (header, body, or query)
 */
function getToken(req) {
  return req.headers['x-session-token'] ||
         req.body?.token ||
         req.query?.token ||
         req.params?.token;
}

/**
 * POST /api/scene/save
 * Save player's scene configuration
 * Body: { token, config, config_name? }
 */
router.post('/scene/save', (req, res) => {
  const db = req.db;
  const token = getToken(req);
  const { config, config_name = 'default' } = req.body;

  const session = validateToken(db, token);
  if (!session) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      message: 'Invalid or expired session'
    });
  }

  if (!config || typeof config !== 'object') {
    return res.status(400).json({
      success: false,
      error: 'INVALID_CONFIG',
      message: 'Config data is required'
    });
  }

  try {
    const configJson = JSON.stringify(config);

    db.prepare(`
      INSERT INTO scene_configs (player_id, config_name, config_data, updated_at)
      VALUES (?, ?, ?, datetime('now'))
      ON CONFLICT(player_id, config_name) DO UPDATE SET
        config_data = excluded.config_data,
        updated_at = datetime('now')
    `).run(session.player_id, config_name, configJson);

    console.log(`[SCENE] Saved config '${config_name}' for ${session.handle}`);

    res.json({
      success: true,
      message: 'Scene configuration saved',
      config_name
    });
  } catch (error) {
    console.error('[SCENE] Save error:', error.message);
    res.status(500).json({
      success: false,
      error: 'SAVE_FAILED',
      message: 'Failed to save scene configuration'
    });
  }
});

/**
 * GET /api/scene/load/:token
 * Load player's scene configuration
 * Query params: config_name (optional, defaults to 'default')
 */
router.get('/scene/load/:token', (req, res) => {
  const db = req.db;
  const token = req.params.token;
  const configName = req.query.config_name || 'default';

  const session = validateToken(db, token);
  if (!session) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      message: 'Invalid or expired session'
    });
  }

  try {
    // Try to load player's config first
    let config = db.prepare(`
      SELECT config_data, updated_at FROM scene_configs
      WHERE player_id = ? AND config_name = ?
    `).get(session.player_id, configName);

    // If no player config, fall back to master default
    if (!config) {
      config = db.prepare(`
        SELECT config_data, updated_at FROM scene_configs
        WHERE player_id IS NULL AND config_name = 'master'
      `).get();
    }

    if (!config) {
      return res.json({
        success: true,
        config: null,
        config_name: configName,
        is_default: true,
        message: 'No saved configuration found'
      });
    }

    const configData = JSON.parse(config.config_data);

    res.json({
      success: true,
      config: configData,
      config_name: configName,
      is_default: !config.player_id,
      updated_at: config.updated_at
    });
  } catch (error) {
    console.error('[SCENE] Load error:', error.message);
    res.status(500).json({
      success: false,
      error: 'LOAD_FAILED',
      message: 'Failed to load scene configuration'
    });
  }
});

/**
 * POST /api/scene/reset
 * Reset player's scene configuration to master default
 * Body: { token, config_name? }
 */
router.post('/scene/reset', (req, res) => {
  const db = req.db;
  const token = getToken(req);
  const { config_name = 'default' } = req.body;

  const session = validateToken(db, token);
  if (!session) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      message: 'Invalid or expired session'
    });
  }

  try {
    // Delete player's saved config
    const result = db.prepare(`
      DELETE FROM scene_configs
      WHERE player_id = ? AND config_name = ?
    `).run(session.player_id, config_name);

    console.log(`[SCENE] Reset config '${config_name}' for ${session.handle}`);

    res.json({
      success: true,
      message: 'Scene configuration reset to default',
      deleted: result.changes > 0
    });
  } catch (error) {
    console.error('[SCENE] Reset error:', error.message);
    res.status(500).json({
      success: false,
      error: 'RESET_FAILED',
      message: 'Failed to reset scene configuration'
    });
  }
});

/**
 * GET /api/scene/default
 * Get the master default scene configuration (public endpoint)
 */
router.get('/scene/default', (req, res) => {
  const db = req.db;

  try {
    const config = db.prepare(`
      SELECT config_data, updated_at FROM scene_configs
      WHERE player_id IS NULL AND config_name = 'master'
    `).get();

    if (!config) {
      return res.json({
        success: true,
        config: { version: 1, elements: {} },
        message: 'No master configuration set'
      });
    }

    res.json({
      success: true,
      config: JSON.parse(config.config_data),
      updated_at: config.updated_at
    });
  } catch (error) {
    console.error('[SCENE] Get default error:', error.message);
    res.status(500).json({
      success: false,
      error: 'LOAD_FAILED',
      message: 'Failed to load default configuration'
    });
  }
});

/**
 * POST /api/scene/save-default
 * Save as master default (admin only - requires admin_key)
 * Body: { admin_key, config }
 */
router.post('/scene/save-default', (req, res) => {
  const db = req.db;
  const { admin_key, config } = req.body;

  // Simple admin key check - in production, use proper authentication
  const expectedKey = process.env.ADMIN_KEY || 'hackterm-admin-2024';

  if (admin_key !== expectedKey) {
    return res.status(403).json({
      success: false,
      error: 'FORBIDDEN',
      message: 'Invalid admin key'
    });
  }

  if (!config || typeof config !== 'object') {
    return res.status(400).json({
      success: false,
      error: 'INVALID_CONFIG',
      message: 'Config data is required'
    });
  }

  try {
    const configJson = JSON.stringify(config);

    db.prepare(`
      INSERT INTO scene_configs (player_id, config_name, config_data, updated_at)
      VALUES (NULL, 'master', ?, datetime('now'))
      ON CONFLICT(player_id, config_name) DO UPDATE SET
        config_data = excluded.config_data,
        updated_at = datetime('now')
    `).run(configJson);

    console.log('[SCENE] Master default config updated by admin');

    res.json({
      success: true,
      message: 'Master default configuration saved'
    });
  } catch (error) {
    console.error('[SCENE] Save default error:', error.message);
    res.status(500).json({
      success: false,
      error: 'SAVE_FAILED',
      message: 'Failed to save default configuration'
    });
  }
});

/**
 * GET /api/scene/list/:token
 * List all saved scene configurations for a player
 */
router.get('/scene/list/:token', (req, res) => {
  const db = req.db;
  const token = req.params.token;

  const session = validateToken(db, token);
  if (!session) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      message: 'Invalid or expired session'
    });
  }

  try {
    const configs = db.prepare(`
      SELECT config_name, updated_at FROM scene_configs
      WHERE player_id = ?
      ORDER BY updated_at DESC
    `).all(session.player_id);

    res.json({
      success: true,
      configs: configs.map(c => ({
        name: c.config_name,
        updated_at: c.updated_at
      }))
    });
  } catch (error) {
    console.error('[SCENE] List error:', error.message);
    res.status(500).json({
      success: false,
      error: 'LIST_FAILED',
      message: 'Failed to list scene configurations'
    });
  }
});

module.exports = router;
