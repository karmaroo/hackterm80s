/**
 * Filesystem Sync Routes
 */

const express = require('express');
const router = express.Router();

/**
 * Middleware to validate session token
 */
function validateToken(req, res, next) {
  const token = req.params.token || req.body.token || req.headers['x-session-token'];
  const db = req.db;

  if (!token) {
    return res.status(401).json({
      success: false,
      error: 'MISSING_TOKEN',
      message: 'Session token required'
    });
  }

  const session = db.prepare(`
    SELECT s.player_id, p.handle
    FROM sessions s
    JOIN players p ON s.player_id = p.id
    WHERE s.token = ? AND (s.expires_at IS NULL OR s.expires_at > datetime('now'))
  `).get(token);

  if (!session) {
    return res.status(401).json({
      success: false,
      error: 'INVALID_TOKEN',
      message: 'Invalid or expired session token'
    });
  }

  req.playerId = session.player_id;
  req.playerHandle = session.handle;
  next();
}

/**
 * GET /api/filesystem/:token
 * Get player's filesystem
 */
router.get('/filesystem/:token', validateToken, (req, res) => {
  const db = req.db;
  const playerId = req.playerId;

  const files = db.prepare(`
    SELECT path, file_type, content, metadata
    FROM player_files
    WHERE player_id = ?
  `).all(playerId);

  // Convert to filesystem dictionary format
  const filesystem = {};
  for (const file of files) {
    filesystem[file.path] = {
      type: file.file_type,
      content: file.content,
      metadata: file.metadata ? JSON.parse(file.metadata) : null
    };
  }

  res.json({
    success: true,
    handle: req.playerHandle,
    filesystem
  });
});

/**
 * PUT /api/filesystem/:token
 * Sync player's filesystem (full replacement)
 */
router.put('/filesystem/:token', validateToken, (req, res) => {
  const { filesystem } = req.body;
  const db = req.db;
  const playerId = req.playerId;

  if (!filesystem || typeof filesystem !== 'object') {
    return res.status(400).json({
      success: false,
      error: 'INVALID_DATA',
      message: 'Filesystem object required'
    });
  }

  const syncFilesystem = db.transaction(() => {
    // Delete existing files
    db.prepare('DELETE FROM player_files WHERE player_id = ?').run(playerId);

    // Insert new files
    const stmt = db.prepare(`
      INSERT INTO player_files (player_id, path, file_type, content, metadata, updated_at)
      VALUES (?, ?, ?, ?, ?, datetime('now'))
    `);

    let fileCount = 0;
    for (const [path, data] of Object.entries(filesystem)) {
      // Skip root directory entries
      if (path === 'C:\\' || path === 'A:\\') continue;

      stmt.run(
        playerId,
        path,
        data.type || 'file',
        data.content || null,
        data.metadata ? JSON.stringify(data.metadata) : null
      );
      fileCount++;
    }

    return fileCount;
  });

  try {
    const count = syncFilesystem();
    console.log(`[SYNC] ${req.playerHandle}: ${count} files synced`);

    res.json({
      success: true,
      files_synced: count
    });
  } catch (error) {
    console.error('[SYNC] Error:', error.message);
    res.status(500).json({
      success: false,
      error: 'SYNC_FAILED',
      message: 'Filesystem sync failed'
    });
  }
});

/**
 * PATCH /api/filesystem/:token
 * Partial filesystem update (add/update specific files)
 */
router.patch('/filesystem/:token', validateToken, (req, res) => {
  const { changes } = req.body;
  const db = req.db;
  const playerId = req.playerId;

  if (!changes || typeof changes !== 'object') {
    return res.status(400).json({
      success: false,
      error: 'INVALID_DATA',
      message: 'Changes object required'
    });
  }

  const applyChanges = db.transaction(() => {
    const upsertStmt = db.prepare(`
      INSERT INTO player_files (player_id, path, file_type, content, metadata, updated_at)
      VALUES (?, ?, ?, ?, ?, datetime('now'))
      ON CONFLICT(player_id, path) DO UPDATE SET
        file_type = excluded.file_type,
        content = excluded.content,
        metadata = excluded.metadata,
        updated_at = datetime('now')
    `);

    const deleteStmt = db.prepare(`
      DELETE FROM player_files WHERE player_id = ? AND path = ?
    `);

    let updated = 0;
    let deleted = 0;

    for (const [path, data] of Object.entries(changes)) {
      if (data === null) {
        // Delete file
        deleteStmt.run(playerId, path);
        deleted++;
      } else {
        // Upsert file
        upsertStmt.run(
          playerId,
          path,
          data.type || 'file',
          data.content || null,
          data.metadata ? JSON.stringify(data.metadata) : null
        );
        updated++;
      }
    }

    return { updated, deleted };
  });

  try {
    const result = applyChanges();
    res.json({
      success: true,
      updated: result.updated,
      deleted: result.deleted
    });
  } catch (error) {
    console.error('[PATCH] Error:', error.message);
    res.status(500).json({
      success: false,
      error: 'PATCH_FAILED',
      message: 'Filesystem update failed'
    });
  }
});

module.exports = router;
