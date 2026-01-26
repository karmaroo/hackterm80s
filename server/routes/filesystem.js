/**
 * Filesystem Sync Routes
 * Provides granular file operations, version management, and real-time sync support
 */

const express = require('express');
const crypto = require('crypto');
const router = express.Router();

// Max versions to keep per file
const MAX_VERSIONS = 5;

/**
 * Compute SHA256 hash of content
 */
function computeHash(content) {
  if (!content) return null;
  return crypto.createHash('sha256').update(content).digest('hex');
}

/**
 * Save current file state to version history before modification
 */
function saveFileVersion(db, playerId, path) {
  // Get current file
  const currentFile = db.prepare(`
    SELECT file_type, content, content_hash, file_size
    FROM player_files
    WHERE player_id = ? AND path = ?
  `).get(playerId, path);

  if (!currentFile) return; // No existing file to version

  // Get next version number (rotate 1-5)
  const result = db.prepare(`
    SELECT MAX(version_number) as max_v
    FROM file_versions
    WHERE player_id = ? AND path = ?
  `).get(playerId, path);

  const nextVersion = ((result?.max_v || 0) % MAX_VERSIONS) + 1;

  // Insert or replace version
  db.prepare(`
    INSERT OR REPLACE INTO file_versions
    (player_id, path, version_number, file_type, content, content_hash, file_size, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
  `).run(
    playerId,
    path,
    nextVersion,
    currentFile.file_type,
    currentFile.content,
    currentFile.content_hash,
    currentFile.file_size
  );
}

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
    SELECT s.player_id, s.token, p.handle
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
  req.sessionToken = session.token;
  next();
}

// ============================================================================
// FULL FILESYSTEM OPERATIONS (Legacy support)
// ============================================================================

/**
 * GET /api/filesystem/:token
 * Get player's full filesystem
 */
router.get('/filesystem/:token', validateToken, (req, res) => {
  const db = req.db;
  const playerId = req.playerId;

  const files = db.prepare(`
    SELECT path, file_type, content, content_hash, file_size, program, metadata, updated_at
    FROM player_files
    WHERE player_id = ?
  `).all(playerId);

  // Convert to filesystem dictionary format
  const filesystem = {};
  for (const file of files) {
    filesystem[file.path] = {
      type: file.file_type,
      content: file.content,
      content_hash: file.content_hash,
      file_size: file.file_size,
      program: file.program,
      metadata: file.metadata ? JSON.parse(file.metadata) : null,
      updated_at: file.updated_at
    };
  }

  res.json({
    success: true,
    handle: req.playerHandle,
    filesystem,
    server_time: Date.now()
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
      INSERT INTO player_files (player_id, path, file_type, content, content_hash, file_size, program, metadata, updated_at, updated_by_session)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
    `);

    let fileCount = 0;
    for (const [path, data] of Object.entries(filesystem)) {
      // Skip root directory entries
      if (path === 'C:\\' || path === 'A:\\') continue;

      const content = data.content || null;
      const hash = computeHash(content);
      const size = content ? content.length : 0;

      stmt.run(
        playerId,
        path,
        data.type || 'file',
        content,
        hash,
        size,
        data.program || null,
        data.metadata ? JSON.stringify(data.metadata) : null,
        req.sessionToken
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
      files_synced: count,
      server_time: Date.now()
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
      INSERT INTO player_files (player_id, path, file_type, content, content_hash, file_size, program, metadata, updated_at, updated_by_session)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
      ON CONFLICT(player_id, path) DO UPDATE SET
        file_type = excluded.file_type,
        content = excluded.content,
        content_hash = excluded.content_hash,
        file_size = excluded.file_size,
        program = excluded.program,
        metadata = excluded.metadata,
        updated_at = datetime('now'),
        updated_by_session = excluded.updated_by_session
    `);

    const deleteStmt = db.prepare(`
      DELETE FROM player_files WHERE player_id = ? AND path = ?
    `);

    let updated = 0;
    let deleted = 0;

    for (const [path, data] of Object.entries(changes)) {
      if (data === null) {
        // Save version before delete
        saveFileVersion(db, playerId, path);
        deleteStmt.run(playerId, path);
        deleted++;
      } else {
        // Save version before update
        saveFileVersion(db, playerId, path);

        const content = data.content || null;
        const hash = computeHash(content);
        const size = content ? content.length : 0;

        upsertStmt.run(
          playerId,
          path,
          data.type || 'file',
          content,
          hash,
          size,
          data.program || null,
          data.metadata ? JSON.stringify(data.metadata) : null,
          req.sessionToken
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
      deleted: result.deleted,
      server_time: Date.now()
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

// ============================================================================
// GRANULAR FILE OPERATIONS
// ============================================================================

/**
 * POST /api/files/:token
 * Create or update a single file
 */
router.post('/files/:token', validateToken, (req, res) => {
  const { path, file_type, content, program, metadata } = req.body;
  const db = req.db;
  const playerId = req.playerId;

  if (!path) {
    return res.status(400).json({
      success: false,
      error: 'MISSING_PATH',
      message: 'File path required'
    });
  }

  try {
    // Save version before update
    saveFileVersion(db, playerId, path);

    const hash = computeHash(content);
    const size = content ? content.length : 0;

    db.prepare(`
      INSERT INTO player_files (player_id, path, file_type, content, content_hash, file_size, program, metadata, updated_at, updated_by_session)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
      ON CONFLICT(player_id, path) DO UPDATE SET
        file_type = excluded.file_type,
        content = excluded.content,
        content_hash = excluded.content_hash,
        file_size = excluded.file_size,
        program = excluded.program,
        metadata = excluded.metadata,
        updated_at = datetime('now'),
        updated_by_session = excluded.updated_by_session
    `).run(
      playerId,
      path,
      file_type || 'file',
      content || null,
      hash,
      size,
      program || null,
      metadata ? JSON.stringify(metadata) : null,
      req.sessionToken
    );

    console.log(`[FILE] ${req.playerHandle}: created/updated ${path}`);

    res.json({
      success: true,
      path,
      content_hash: hash,
      file_size: size,
      server_time: Date.now()
    });
  } catch (error) {
    console.error('[FILE] Error:', error.message);
    res.status(500).json({
      success: false,
      error: 'FILE_FAILED',
      message: 'File operation failed'
    });
  }
});

/**
 * GET /api/files/:token/:path
 * Get a single file with metadata
 * Note: path should be URL encoded (e.g., C%3A%5CGAMES%5CREADME.TXT)
 */
router.get('/files/:token/*', validateToken, (req, res) => {
  const db = req.db;
  const playerId = req.playerId;
  const path = req.params[0]; // Get the wildcard path

  const file = db.prepare(`
    SELECT path, file_type, content, content_hash, file_size, program, metadata, created_at, updated_at
    FROM player_files
    WHERE player_id = ? AND path = ?
  `).get(playerId, path);

  if (!file) {
    return res.status(404).json({
      success: false,
      error: 'FILE_NOT_FOUND',
      message: `File not found: ${path}`
    });
  }

  res.json({
    success: true,
    file: {
      path: file.path,
      type: file.file_type,
      content: file.content,
      content_hash: file.content_hash,
      file_size: file.file_size,
      program: file.program,
      metadata: file.metadata ? JSON.parse(file.metadata) : null,
      created_at: file.created_at,
      updated_at: file.updated_at
    }
  });
});

/**
 * DELETE /api/files/:token/:path
 * Delete a single file (saves version first)
 */
router.delete('/files/:token/*', validateToken, (req, res) => {
  const db = req.db;
  const playerId = req.playerId;
  const path = req.params[0];

  try {
    // Save version before delete
    saveFileVersion(db, playerId, path);

    const result = db.prepare(`
      DELETE FROM player_files WHERE player_id = ? AND path = ?
    `).run(playerId, path);

    if (result.changes === 0) {
      return res.status(404).json({
        success: false,
        error: 'FILE_NOT_FOUND',
        message: `File not found: ${path}`
      });
    }

    console.log(`[FILE] ${req.playerHandle}: deleted ${path}`);

    res.json({
      success: true,
      path,
      server_time: Date.now()
    });
  } catch (error) {
    console.error('[FILE DELETE] Error:', error.message);
    res.status(500).json({
      success: false,
      error: 'DELETE_FAILED',
      message: 'File deletion failed'
    });
  }
});

// ============================================================================
// DIRECTORY OPERATIONS
// ============================================================================

/**
 * POST /api/dirs/:token
 * Create a directory
 */
router.post('/dirs/:token', validateToken, (req, res) => {
  const { path } = req.body;
  const db = req.db;
  const playerId = req.playerId;

  if (!path) {
    return res.status(400).json({
      success: false,
      error: 'MISSING_PATH',
      message: 'Directory path required'
    });
  }

  try {
    // Check if already exists
    const existing = db.prepare(`
      SELECT id FROM player_files WHERE player_id = ? AND path = ?
    `).get(playerId, path);

    if (existing) {
      return res.status(409).json({
        success: false,
        error: 'ALREADY_EXISTS',
        message: 'Directory already exists'
      });
    }

    db.prepare(`
      INSERT INTO player_files (player_id, path, file_type, updated_at, updated_by_session)
      VALUES (?, ?, 'dir', datetime('now'), ?)
    `).run(playerId, path, req.sessionToken);

    console.log(`[DIR] ${req.playerHandle}: created ${path}`);

    res.json({
      success: true,
      path,
      server_time: Date.now()
    });
  } catch (error) {
    console.error('[DIR] Error:', error.message);
    res.status(500).json({
      success: false,
      error: 'DIR_FAILED',
      message: 'Directory creation failed'
    });
  }
});

/**
 * DELETE /api/dirs/:token/:path
 * Remove a directory (must be empty)
 */
router.delete('/dirs/:token/*', validateToken, (req, res) => {
  const db = req.db;
  const playerId = req.playerId;
  const path = req.params[0];

  try {
    // Check if directory exists
    const dir = db.prepare(`
      SELECT id, file_type FROM player_files WHERE player_id = ? AND path = ?
    `).get(playerId, path);

    if (!dir) {
      return res.status(404).json({
        success: false,
        error: 'DIR_NOT_FOUND',
        message: `Directory not found: ${path}`
      });
    }

    if (dir.file_type !== 'dir') {
      return res.status(400).json({
        success: false,
        error: 'NOT_A_DIRECTORY',
        message: 'Path is not a directory'
      });
    }

    // Check if directory has children
    const children = db.prepare(`
      SELECT COUNT(*) as count FROM player_files
      WHERE player_id = ? AND path LIKE ? AND path != ?
    `).get(playerId, path + '\\%', path);

    if (children.count > 0) {
      return res.status(400).json({
        success: false,
        error: 'DIR_NOT_EMPTY',
        message: 'Directory is not empty'
      });
    }

    db.prepare(`
      DELETE FROM player_files WHERE player_id = ? AND path = ?
    `).run(playerId, path);

    console.log(`[DIR] ${req.playerHandle}: removed ${path}`);

    res.json({
      success: true,
      path,
      server_time: Date.now()
    });
  } catch (error) {
    console.error('[DIR DELETE] Error:', error.message);
    res.status(500).json({
      success: false,
      error: 'DIR_DELETE_FAILED',
      message: 'Directory deletion failed'
    });
  }
});

// ============================================================================
// VERSION MANAGEMENT
// ============================================================================

/**
 * GET /api/versions/:token/:path
 * List version history for a file
 */
router.get('/versions/:token/*', validateToken, (req, res) => {
  const db = req.db;
  const playerId = req.playerId;
  const path = req.params[0];

  const versions = db.prepare(`
    SELECT version_number, file_type, content_hash, file_size, created_at
    FROM file_versions
    WHERE player_id = ? AND path = ?
    ORDER BY created_at DESC
  `).all(playerId, path);

  // Also get current file info
  const current = db.prepare(`
    SELECT file_type, content_hash, file_size, updated_at
    FROM player_files
    WHERE player_id = ? AND path = ?
  `).get(playerId, path);

  res.json({
    success: true,
    path,
    current: current ? {
      type: current.file_type,
      content_hash: current.content_hash,
      file_size: current.file_size,
      updated_at: current.updated_at
    } : null,
    versions: versions.map(v => ({
      version: v.version_number,
      type: v.file_type,
      content_hash: v.content_hash,
      file_size: v.file_size,
      created_at: v.created_at
    }))
  });
});

/**
 * POST /api/versions/:token/:path/restore/:version
 * Restore a file to a previous version
 */
router.post('/versions/:token/*/restore/:version', validateToken, (req, res) => {
  const db = req.db;
  const playerId = req.playerId;
  // Extract path from params - it's between token and /restore
  const pathParts = req.params[0];
  const version = parseInt(req.params.version);

  if (isNaN(version) || version < 1 || version > MAX_VERSIONS) {
    return res.status(400).json({
      success: false,
      error: 'INVALID_VERSION',
      message: `Version must be between 1 and ${MAX_VERSIONS}`
    });
  }

  try {
    // Get the version to restore
    const versionData = db.prepare(`
      SELECT file_type, content, content_hash, file_size
      FROM file_versions
      WHERE player_id = ? AND path = ? AND version_number = ?
    `).get(playerId, pathParts, version);

    if (!versionData) {
      return res.status(404).json({
        success: false,
        error: 'VERSION_NOT_FOUND',
        message: `Version ${version} not found for ${pathParts}`
      });
    }

    // Save current version before restoring
    saveFileVersion(db, playerId, pathParts);

    // Restore the file
    db.prepare(`
      INSERT INTO player_files (player_id, path, file_type, content, content_hash, file_size, updated_at, updated_by_session)
      VALUES (?, ?, ?, ?, ?, ?, datetime('now'), ?)
      ON CONFLICT(player_id, path) DO UPDATE SET
        file_type = excluded.file_type,
        content = excluded.content,
        content_hash = excluded.content_hash,
        file_size = excluded.file_size,
        updated_at = datetime('now'),
        updated_by_session = excluded.updated_by_session
    `).run(
      playerId,
      pathParts,
      versionData.file_type,
      versionData.content,
      versionData.content_hash,
      versionData.file_size,
      req.sessionToken
    );

    console.log(`[VERSION] ${req.playerHandle}: restored ${pathParts} to version ${version}`);

    res.json({
      success: true,
      path: pathParts,
      restored_version: version,
      server_time: Date.now()
    });
  } catch (error) {
    console.error('[VERSION RESTORE] Error:', error.message);
    res.status(500).json({
      success: false,
      error: 'RESTORE_FAILED',
      message: 'Version restore failed'
    });
  }
});

// ============================================================================
// BATCH OPERATIONS
// ============================================================================

/**
 * POST /api/batch/:token
 * Apply multiple file operations atomically
 */
router.post('/batch/:token', validateToken, (req, res) => {
  const { operations } = req.body;
  const db = req.db;
  const playerId = req.playerId;

  if (!operations || !Array.isArray(operations)) {
    return res.status(400).json({
      success: false,
      error: 'INVALID_DATA',
      message: 'Operations array required'
    });
  }

  const executeBatch = db.transaction(() => {
    const results = [];

    for (const op of operations) {
      switch (op.op) {
        case 'create':
        case 'update': {
          saveFileVersion(db, playerId, op.path);
          const hash = computeHash(op.content);
          const size = op.content ? op.content.length : 0;

          db.prepare(`
            INSERT INTO player_files (player_id, path, file_type, content, content_hash, file_size, program, metadata, updated_at, updated_by_session)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
            ON CONFLICT(player_id, path) DO UPDATE SET
              file_type = excluded.file_type,
              content = excluded.content,
              content_hash = excluded.content_hash,
              file_size = excluded.file_size,
              program = excluded.program,
              metadata = excluded.metadata,
              updated_at = datetime('now'),
              updated_by_session = excluded.updated_by_session
          `).run(
            playerId,
            op.path,
            op.type || 'file',
            op.content || null,
            hash,
            size,
            op.program || null,
            op.metadata ? JSON.stringify(op.metadata) : null,
            req.sessionToken
          );
          results.push({ op: op.op, path: op.path, success: true });
          break;
        }

        case 'delete': {
          saveFileVersion(db, playerId, op.path);
          const result = db.prepare(`
            DELETE FROM player_files WHERE player_id = ? AND path = ?
          `).run(playerId, op.path);
          results.push({ op: 'delete', path: op.path, success: result.changes > 0 });
          break;
        }

        case 'mkdir': {
          const existing = db.prepare(`
            SELECT id FROM player_files WHERE player_id = ? AND path = ?
          `).get(playerId, op.path);

          if (!existing) {
            db.prepare(`
              INSERT INTO player_files (player_id, path, file_type, updated_at, updated_by_session)
              VALUES (?, ?, 'dir', datetime('now'), ?)
            `).run(playerId, op.path, req.sessionToken);
          }
          results.push({ op: 'mkdir', path: op.path, success: true });
          break;
        }

        case 'rmdir': {
          const children = db.prepare(`
            SELECT COUNT(*) as count FROM player_files
            WHERE player_id = ? AND path LIKE ? AND path != ?
          `).get(playerId, op.path + '\\%', op.path);

          if (children.count === 0) {
            db.prepare(`
              DELETE FROM player_files WHERE player_id = ? AND path = ? AND file_type = 'dir'
            `).run(playerId, op.path);
            results.push({ op: 'rmdir', path: op.path, success: true });
          } else {
            results.push({ op: 'rmdir', path: op.path, success: false, error: 'NOT_EMPTY' });
          }
          break;
        }

        default:
          results.push({ op: op.op, path: op.path, success: false, error: 'UNKNOWN_OP' });
      }
    }

    return results;
  });

  try {
    const results = executeBatch();
    console.log(`[BATCH] ${req.playerHandle}: ${operations.length} operations`);

    res.json({
      success: true,
      results,
      server_time: Date.now()
    });
  } catch (error) {
    console.error('[BATCH] Error:', error.message);
    res.status(500).json({
      success: false,
      error: 'BATCH_FAILED',
      message: 'Batch operation failed'
    });
  }
});

// ============================================================================
// INCREMENTAL SYNC
// ============================================================================

/**
 * GET /api/sync/:token
 * Get changes since a timestamp
 */
router.get('/sync/:token', validateToken, (req, res) => {
  const db = req.db;
  const playerId = req.playerId;
  const since = req.query.since ? new Date(parseInt(req.query.since)).toISOString() : null;

  let files;
  if (since) {
    files = db.prepare(`
      SELECT path, file_type, content, content_hash, file_size, program, metadata, updated_at, updated_by_session
      FROM player_files
      WHERE player_id = ? AND updated_at > ?
    `).all(playerId, since);
  } else {
    // Full sync if no timestamp
    files = db.prepare(`
      SELECT path, file_type, content, content_hash, file_size, program, metadata, updated_at, updated_by_session
      FROM player_files
      WHERE player_id = ?
    `).all(playerId);
  }

  res.json({
    success: true,
    files: files.map(f => ({
      path: f.path,
      type: f.file_type,
      content: f.content,
      content_hash: f.content_hash,
      file_size: f.file_size,
      program: f.program,
      metadata: f.metadata ? JSON.parse(f.metadata) : null,
      updated_at: f.updated_at,
      updated_by: f.updated_by_session
    })),
    server_time: Date.now()
  });
});

module.exports = router;
