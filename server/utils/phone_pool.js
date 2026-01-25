/**
 * Phone Number Pool Management
 * Allocates numbers from 555-1000 to 555-9999
 */

const PHONE_MIN = 1000;
const PHONE_MAX = 9999;

/**
 * Initialize the phone pool table with available numbers
 * @param {Database} db - SQLite database instance
 */
function initPhonePool(db) {
  const count = db.prepare('SELECT COUNT(*) as c FROM phone_pool').get();

  if (count.c === 0) {
    console.log('Initializing phone pool (555-1000 to 555-9999)...');
    const stmt = db.prepare('INSERT INTO phone_pool (number) VALUES (?)');
    const insertMany = db.transaction((numbers) => {
      for (const num of numbers) {
        stmt.run(num);
      }
    });

    const numbers = [];
    for (let i = PHONE_MIN; i <= PHONE_MAX; i++) {
      numbers.push(`555-${i}`);
    }
    insertMany(numbers);
    console.log(`Phone pool initialized with ${numbers.length} numbers`);
  }
}

/**
 * Allocate a random available phone number to a player
 * @param {Database} db - SQLite database instance
 * @param {number} playerId - Player ID to assign the number to
 * @returns {string|null} The allocated phone number, or null if none available
 */
function allocatePhoneNumber(db, playerId) {
  // Get a random unallocated number
  const number = db.prepare(`
    SELECT number FROM phone_pool
    WHERE allocated = 0
    ORDER BY RANDOM()
    LIMIT 1
  `).get();

  if (!number) {
    return null; // No numbers available
  }

  // Mark as allocated
  db.prepare(`
    UPDATE phone_pool
    SET allocated = 1, player_id = ?
    WHERE number = ?
  `).run(playerId, number.number);

  return number.number;
}

/**
 * Release a phone number back to the pool
 * @param {Database} db - SQLite database instance
 * @param {string} phoneNumber - The phone number to release
 */
function releasePhoneNumber(db, phoneNumber) {
  db.prepare(`
    UPDATE phone_pool
    SET allocated = 0, player_id = NULL
    WHERE number = ?
  `).run(phoneNumber);
}

/**
 * Get statistics about the phone pool
 * @param {Database} db - SQLite database instance
 * @returns {object} Pool statistics
 */
function getPoolStats(db) {
  const stats = db.prepare(`
    SELECT
      COUNT(*) as total,
      SUM(CASE WHEN allocated = 1 THEN 1 ELSE 0 END) as allocated,
      SUM(CASE WHEN allocated = 0 THEN 1 ELSE 0 END) as available
    FROM phone_pool
  `).get();
  return stats;
}

module.exports = {
  initPhonePool,
  allocatePhoneNumber,
  releasePhoneNumber,
  getPoolStats,
  PHONE_MIN,
  PHONE_MAX
};
