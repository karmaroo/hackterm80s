/**
 * WebSocket Server for Real-Time Filesystem Sync
 * Enables multi-device synchronization with instant updates
 */

const WebSocket = require('ws');
const crypto = require('crypto');

// Store active connections by player_id
const playerConnections = new Map(); // player_id -> Set of { ws, sessionToken }

// Scene update debouncing: playerId -> { timeout, lastConfig, ws }
const sceneUpdateDebounce = new Map();
const SCENE_DEBOUNCE_MS = 500;

/**
 * Initialize WebSocket server
 * @param {http.Server} server - HTTP server to attach to
 * @param {Database} db - SQLite database instance
 */
function initWebSocket(server, db) {
  const wss = new WebSocket.Server({ server, path: '/ws' });

  console.log('  WebSocket server initialized at /ws');

  wss.on('connection', (ws, req) => {
    console.log('[WS] New connection from', req.socket.remoteAddress);

    let authenticated = false;
    let playerId = null;
    let sessionToken = null;
    let playerHandle = null;

    // Set up ping interval to keep connection alive
    const pingInterval = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
      }
    }, 30000);

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());
        handleMessage(ws, message, {
          db,
          authenticated,
          playerId,
          sessionToken,
          playerHandle,
          setAuth: (auth) => {
            authenticated = auth.authenticated;
            playerId = auth.playerId;
            sessionToken = auth.sessionToken;
            playerHandle = auth.playerHandle;
          }
        });
      } catch (error) {
        console.error('[WS] Message parse error:', error.message);
        sendError(ws, 'INVALID_MESSAGE', 'Could not parse message');
      }
    });

    ws.on('close', () => {
      clearInterval(pingInterval);
      if (playerId) {
        removeConnection(playerId, ws);
        // Remove from active_sessions
        try {
          db.prepare('DELETE FROM active_sessions WHERE session_token = ?').run(sessionToken);
        } catch (e) {
          // Ignore errors on cleanup
        }
        console.log(`[WS] ${playerHandle || playerId} disconnected`);
      }
    });

    ws.on('error', (error) => {
      console.error('[WS] Connection error:', error.message);
    });

    ws.on('pong', () => {
      // Connection is alive
      if (sessionToken) {
        try {
          db.prepare('UPDATE active_sessions SET last_ping = datetime("now") WHERE session_token = ?').run(sessionToken);
        } catch (e) {
          // Ignore errors
        }
      }
    });
  });

  return wss;
}

/**
 * Handle incoming WebSocket message
 */
function handleMessage(ws, message, context) {
  const { db, authenticated, playerId, sessionToken, playerHandle, setAuth } = context;

  switch (message.type) {
    case 'auth':
      handleAuth(ws, message, db, setAuth);
      break;

    case 'ping':
      ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
      break;

    case 'file_change':
      if (!authenticated) {
        sendError(ws, 'NOT_AUTHENTICATED', 'Must authenticate first');
        return;
      }
      handleFileChange(ws, message, db, playerId, sessionToken, playerHandle);
      break;

    case 'file_delete':
      if (!authenticated) {
        sendError(ws, 'NOT_AUTHENTICATED', 'Must authenticate first');
        return;
      }
      handleFileDelete(ws, message, db, playerId, sessionToken, playerHandle);
      break;

    case 'mkdir':
      if (!authenticated) {
        sendError(ws, 'NOT_AUTHENTICATED', 'Must authenticate first');
        return;
      }
      handleMkdir(ws, message, db, playerId, sessionToken, playerHandle);
      break;

    case 'rmdir':
      if (!authenticated) {
        sendError(ws, 'NOT_AUTHENTICATED', 'Must authenticate first');
        return;
      }
      handleRmdir(ws, message, db, playerId, sessionToken, playerHandle);
      break;

    case 'request_sync':
      if (!authenticated) {
        sendError(ws, 'NOT_AUTHENTICATED', 'Must authenticate first');
        return;
      }
      handleRequestSync(ws, message, db, playerId);
      break;

    case 'scene_update':
      if (!authenticated) {
        sendError(ws, 'NOT_AUTHENTICATED', 'Must authenticate first');
        return;
      }
      handleSceneUpdate(ws, message, db, playerId, sessionToken, playerHandle);
      break;

    case 'scene_save_default':
      if (!authenticated) {
        sendError(ws, 'NOT_AUTHENTICATED', 'Must authenticate first');
        return;
      }
      handleSceneSaveDefault(ws, message, db, playerId, playerHandle);
      break;

    case 'scene_load':
      if (!authenticated) {
        sendError(ws, 'NOT_AUTHENTICATED', 'Must authenticate first');
        return;
      }
      handleSceneLoad(ws, message, db, playerId);
      break;

    default:
      sendError(ws, 'UNKNOWN_TYPE', `Unknown message type: ${message.type}`);
  }
}

/**
 * Handle authentication
 */
function handleAuth(ws, message, db, setAuth) {
  const { token } = message;

  if (!token) {
    sendError(ws, 'MISSING_TOKEN', 'Session token required');
    return;
  }

  const session = db.prepare(`
    SELECT s.player_id, s.token, p.handle
    FROM sessions s
    JOIN players p ON s.player_id = p.id
    WHERE s.token = ? AND (s.expires_at IS NULL OR s.expires_at > datetime('now'))
  `).get(token);

  if (!session) {
    sendError(ws, 'INVALID_TOKEN', 'Invalid or expired session token');
    return;
  }

  // Set authentication state
  setAuth({
    authenticated: true,
    playerId: session.player_id,
    sessionToken: session.token,
    playerHandle: session.handle
  });

  // Add to connections map
  addConnection(session.player_id, ws, session.token);

  // Track in active_sessions table
  try {
    db.prepare(`
      INSERT OR REPLACE INTO active_sessions (session_token, player_id, connected_at, last_ping)
      VALUES (?, ?, datetime('now'), datetime('now'))
    `).run(session.token, session.player_id);
  } catch (e) {
    // Ignore errors
  }

  console.log(`[WS] ${session.handle} authenticated`);

  ws.send(JSON.stringify({
    type: 'auth_ok',
    player_id: session.player_id,
    handle: session.handle,
    timestamp: Date.now()
  }));
}

/**
 * Handle file change (create/update)
 */
function handleFileChange(ws, message, db, playerId, sessionToken, playerHandle) {
  const { path, content, file_type, program, metadata } = message;

  if (!path) {
    sendError(ws, 'MISSING_PATH', 'File path required');
    return;
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
      sessionToken
    );

    console.log(`[WS] ${playerHandle}: file_change ${path}`);

    // Send confirmation to sender
    ws.send(JSON.stringify({
      type: 'file_change_ok',
      path,
      content_hash: hash,
      timestamp: Date.now()
    }));

    // Broadcast to other sessions of same player
    broadcastToPlayer(playerId, sessionToken, {
      type: 'file_changed',
      path,
      content,
      file_type: file_type || 'file',
      program,
      metadata,
      content_hash: hash,
      by_session: sessionToken,
      timestamp: Date.now()
    });

  } catch (error) {
    console.error('[WS] file_change error:', error.message);
    sendError(ws, 'FILE_CHANGE_FAILED', error.message);
  }
}

/**
 * Handle file deletion
 */
function handleFileDelete(ws, message, db, playerId, sessionToken, playerHandle) {
  const { path } = message;

  if (!path) {
    sendError(ws, 'MISSING_PATH', 'File path required');
    return;
  }

  try {
    // Save version before delete
    saveFileVersion(db, playerId, path);

    const result = db.prepare(`
      DELETE FROM player_files WHERE player_id = ? AND path = ?
    `).run(playerId, path);

    if (result.changes === 0) {
      sendError(ws, 'FILE_NOT_FOUND', `File not found: ${path}`);
      return;
    }

    console.log(`[WS] ${playerHandle}: file_delete ${path}`);

    // Send confirmation
    ws.send(JSON.stringify({
      type: 'file_delete_ok',
      path,
      timestamp: Date.now()
    }));

    // Broadcast to other sessions
    broadcastToPlayer(playerId, sessionToken, {
      type: 'file_deleted',
      path,
      by_session: sessionToken,
      timestamp: Date.now()
    });

  } catch (error) {
    console.error('[WS] file_delete error:', error.message);
    sendError(ws, 'FILE_DELETE_FAILED', error.message);
  }
}

/**
 * Handle mkdir
 */
function handleMkdir(ws, message, db, playerId, sessionToken, playerHandle) {
  const { path } = message;

  if (!path) {
    sendError(ws, 'MISSING_PATH', 'Directory path required');
    return;
  }

  try {
    // Check if already exists
    const existing = db.prepare(`
      SELECT id FROM player_files WHERE player_id = ? AND path = ?
    `).get(playerId, path);

    if (existing) {
      sendError(ws, 'ALREADY_EXISTS', 'Directory already exists');
      return;
    }

    db.prepare(`
      INSERT INTO player_files (player_id, path, file_type, updated_at, updated_by_session)
      VALUES (?, ?, 'dir', datetime('now'), ?)
    `).run(playerId, path, sessionToken);

    console.log(`[WS] ${playerHandle}: mkdir ${path}`);

    // Send confirmation
    ws.send(JSON.stringify({
      type: 'mkdir_ok',
      path,
      timestamp: Date.now()
    }));

    // Broadcast to other sessions
    broadcastToPlayer(playerId, sessionToken, {
      type: 'file_changed',
      path,
      file_type: 'dir',
      content: null,
      by_session: sessionToken,
      timestamp: Date.now()
    });

  } catch (error) {
    console.error('[WS] mkdir error:', error.message);
    sendError(ws, 'MKDIR_FAILED', error.message);
  }
}

/**
 * Handle rmdir
 */
function handleRmdir(ws, message, db, playerId, sessionToken, playerHandle) {
  const { path } = message;

  if (!path) {
    sendError(ws, 'MISSING_PATH', 'Directory path required');
    return;
  }

  try {
    // Check if directory exists
    const dir = db.prepare(`
      SELECT id, file_type FROM player_files WHERE player_id = ? AND path = ?
    `).get(playerId, path);

    if (!dir) {
      sendError(ws, 'DIR_NOT_FOUND', `Directory not found: ${path}`);
      return;
    }

    if (dir.file_type !== 'dir') {
      sendError(ws, 'NOT_A_DIRECTORY', 'Path is not a directory');
      return;
    }

    // Check if empty
    const children = db.prepare(`
      SELECT COUNT(*) as count FROM player_files
      WHERE player_id = ? AND path LIKE ? AND path != ?
    `).get(playerId, path + '\\%', path);

    if (children.count > 0) {
      sendError(ws, 'DIR_NOT_EMPTY', 'Directory is not empty');
      return;
    }

    db.prepare(`
      DELETE FROM player_files WHERE player_id = ? AND path = ?
    `).run(playerId, path);

    console.log(`[WS] ${playerHandle}: rmdir ${path}`);

    // Send confirmation
    ws.send(JSON.stringify({
      type: 'rmdir_ok',
      path,
      timestamp: Date.now()
    }));

    // Broadcast to other sessions
    broadcastToPlayer(playerId, sessionToken, {
      type: 'file_deleted',
      path,
      by_session: sessionToken,
      timestamp: Date.now()
    });

  } catch (error) {
    console.error('[WS] rmdir error:', error.message);
    sendError(ws, 'RMDIR_FAILED', error.message);
  }
}

/**
 * Handle sync request (get all files)
 */
function handleRequestSync(ws, message, db, playerId) {
  const { since } = message;

  let files;
  if (since) {
    const sinceDate = new Date(since).toISOString();
    files = db.prepare(`
      SELECT path, file_type, content, content_hash, file_size, program, metadata, updated_at
      FROM player_files
      WHERE player_id = ? AND updated_at > ?
    `).all(playerId, sinceDate);
  } else {
    files = db.prepare(`
      SELECT path, file_type, content, content_hash, file_size, program, metadata, updated_at
      FROM player_files
      WHERE player_id = ?
    `).all(playerId);
  }

  ws.send(JSON.stringify({
    type: 'sync_data',
    files: files.map(f => ({
      path: f.path,
      type: f.file_type,
      content: f.content,
      content_hash: f.content_hash,
      file_size: f.file_size,
      program: f.program,
      metadata: f.metadata ? JSON.parse(f.metadata) : null,
      updated_at: f.updated_at
    })),
    server_time: Date.now()
  }));
}

// ============================================================================
// Scene Configuration Handlers
// ============================================================================

/**
 * Handle scene update (auto-save with debouncing)
 */
function handleSceneUpdate(ws, message, db, playerId, sessionToken, playerHandle) {
  const { config, config_name = 'default' } = message;

  if (!config || typeof config !== 'object') {
    sendError(ws, 'INVALID_CONFIG', 'Config data is required');
    return;
  }

  // Clear any existing debounce timer for this player
  const existing = sceneUpdateDebounce.get(playerId);
  if (existing?.timeout) {
    clearTimeout(existing.timeout);
  }

  // Set new debounce timer
  const timeout = setTimeout(() => {
    try {
      let finalConfig = config;

      // Handle delta updates - merge with existing config
      if (config.is_delta) {
        const existingRow = db.prepare(`
          SELECT config_data FROM scene_configs
          WHERE player_id = ? AND config_name = ?
        `).get(playerId, config_name);

        if (existingRow) {
          const existingConfig = JSON.parse(existingRow.config_data);

          // Get current copy paths to know which elements to keep
          const copyPaths = new Set((config.copies || []).map(c => c.path));

          // Filter out deleted copies from existing elements
          const filteredElements = { ...existingConfig.elements };
          for (const path of Object.keys(filteredElements)) {
            // If this was a copy (has is_copy flag) and is no longer in copies list, remove it
            const elemData = filteredElements[path];
            if (elemData && elemData.is_copy && !copyPaths.has(path)) {
              delete filteredElements[path];
            }
          }

          // Merge: keep filtered elements, overwrite with delta elements
          finalConfig = {
            ...existingConfig,
            version: config.version || existingConfig.version,
            timestamp: config.timestamp,
            hidden: config.hidden || existingConfig.hidden || [],
            locked: config.locked || existingConfig.locked || [],
            copies: config.copies || existingConfig.copies || [],
            custom_names: config.custom_names || existingConfig.custom_names || {},
            elements: {
              ...filteredElements,
              ...config.elements  // Delta elements overwrite existing
            }
          };
          delete finalConfig.is_delta;
        }
      }

      const configJson = JSON.stringify(finalConfig);
      db.prepare(`
        INSERT INTO scene_configs (player_id, config_name, config_data, updated_at)
        VALUES (?, ?, ?, datetime('now'))
        ON CONFLICT(player_id, config_name) DO UPDATE SET
          config_data = excluded.config_data,
          updated_at = datetime('now')
      `).run(playerId, config_name, configJson);

      console.log(`[WS] ${playerHandle}: scene_update saved (${config_name})`);

      // Confirm to sender
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          type: 'scene_update_ok',
          config_name,
          timestamp: Date.now()
        }));
      }

      // Broadcast to other sessions of same player
      broadcastToPlayer(playerId, sessionToken, {
        type: 'scene_changed',
        config,
        config_name,
        by_session: sessionToken,
        timestamp: Date.now()
      });

    } catch (error) {
      console.error('[WS] scene_update error:', error.message);
      if (ws.readyState === WebSocket.OPEN) {
        sendError(ws, 'SCENE_UPDATE_FAILED', error.message);
      }
    }

    sceneUpdateDebounce.delete(playerId);
  }, SCENE_DEBOUNCE_MS);

  sceneUpdateDebounce.set(playerId, { timeout, lastConfig: config, ws });
}

/**
 * Handle scene save as default (admin only)
 */
function handleSceneSaveDefault(ws, message, db, playerId, playerHandle) {
  const { admin_key, config } = message;
  const expectedKey = process.env.ADMIN_KEY || 'hackterm-admin-2024';

  if (admin_key !== expectedKey) {
    sendError(ws, 'FORBIDDEN', 'Invalid admin key');
    return;
  }

  if (!config || typeof config !== 'object') {
    sendError(ws, 'INVALID_CONFIG', 'Config data is required');
    return;
  }

  try {
    const configJson = JSON.stringify(config);

    // Save to master config (player_id = NULL)
    db.prepare(`
      INSERT INTO scene_configs (player_id, config_name, config_data, updated_at)
      VALUES (NULL, 'master', ?, datetime('now'))
      ON CONFLICT(player_id, config_name) DO UPDATE SET
        config_data = excluded.config_data,
        updated_at = datetime('now')
    `).run(configJson);

    console.log(`[WS] ${playerHandle}: saved master default config`);

    ws.send(JSON.stringify({
      type: 'scene_save_default_ok',
      timestamp: Date.now()
    }));
  } catch (error) {
    console.error('[WS] scene_save_default error:', error.message);
    sendError(ws, 'SCENE_SAVE_DEFAULT_FAILED', error.message);
  }
}

/**
 * Handle scene load request
 */
function handleSceneLoad(ws, message, db, playerId) {
  const { config_name = 'default' } = message;

  try {
    // Try player config first
    let config = db.prepare(`
      SELECT config_data, updated_at FROM scene_configs
      WHERE player_id = ? AND config_name = ?
    `).get(playerId, config_name);

    let isDefault = false;

    // Fallback to master if no player config
    if (!config) {
      config = db.prepare(`
        SELECT config_data, updated_at FROM scene_configs
        WHERE player_id IS NULL AND config_name = 'master'
      `).get();
      isDefault = true;
    }

    ws.send(JSON.stringify({
      type: 'scene_load_response',
      config: config ? JSON.parse(config.config_data) : null,
      config_name,
      is_default: isDefault,
      updated_at: config?.updated_at,
      timestamp: Date.now()
    }));
  } catch (error) {
    console.error('[WS] scene_load error:', error.message);
    sendError(ws, 'SCENE_LOAD_FAILED', error.message);
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Add connection to player's connection set
 */
function addConnection(playerId, ws, sessionToken) {
  if (!playerConnections.has(playerId)) {
    playerConnections.set(playerId, new Set());
  }
  playerConnections.get(playerId).add({ ws, sessionToken });
}

/**
 * Remove connection from player's connection set
 */
function removeConnection(playerId, ws) {
  const connections = playerConnections.get(playerId);
  if (connections) {
    for (const conn of connections) {
      if (conn.ws === ws) {
        connections.delete(conn);
        break;
      }
    }
    if (connections.size === 0) {
      playerConnections.delete(playerId);
    }
  }
}

/**
 * Broadcast message to all other sessions of a player
 */
function broadcastToPlayer(playerId, excludeToken, message) {
  const connections = playerConnections.get(playerId);
  if (!connections) return;

  const data = JSON.stringify(message);

  for (const conn of connections) {
    if (conn.sessionToken !== excludeToken && conn.ws.readyState === WebSocket.OPEN) {
      conn.ws.send(data);
    }
  }
}

/**
 * Send error message
 */
function sendError(ws, code, message) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({
      type: 'error',
      code,
      message,
      timestamp: Date.now()
    }));
  }
}

/**
 * Compute SHA256 hash
 */
function computeHash(content) {
  if (!content) return null;
  return crypto.createHash('sha256').update(content).digest('hex');
}

/**
 * Save file version before modification
 */
function saveFileVersion(db, playerId, path) {
  const currentFile = db.prepare(`
    SELECT file_type, content, content_hash, file_size
    FROM player_files
    WHERE player_id = ? AND path = ?
  `).get(playerId, path);

  if (!currentFile) return;

  const result = db.prepare(`
    SELECT MAX(version_number) as max_v
    FROM file_versions
    WHERE player_id = ? AND path = ?
  `).get(playerId, path);

  const nextVersion = ((result?.max_v || 0) % 5) + 1;

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
 * Get connection count for a player
 */
function getPlayerConnectionCount(playerId) {
  const connections = playerConnections.get(playerId);
  return connections ? connections.size : 0;
}

/**
 * Get total active connections
 */
function getTotalConnections() {
  let total = 0;
  for (const connections of playerConnections.values()) {
    total += connections.size;
  }
  return total;
}

module.exports = {
  initWebSocket,
  broadcastToPlayer,
  getPlayerConnectionCount,
  getTotalConnections
};
