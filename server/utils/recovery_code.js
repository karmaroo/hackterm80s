/**
 * Recovery Code Generator
 * Format: WORD-XXXX-XXXX
 * Example: PHANTOM-7X9K-M2P1
 */

// Hacker-themed word pool (100 words)
const WORDS = [
  'SHADOW', 'PHANTOM', 'CIPHER', 'GHOST', 'COBRA', 'VIPER', 'BLADE', 'STORM',
  'FROST', 'RAVEN', 'SPECTER', 'MATRIX', 'NEURAL', 'NEON', 'CHROME', 'RAZOR',
  'BYTE', 'PIXEL', 'VECTOR', 'BINARY', 'DAEMON', 'KERNEL', 'SOCKET', 'PACKET',
  'CIPHER', 'CRYPTO', 'HACKER', 'PHREAKER', 'CRACKER', 'WAREZ', 'ELITE', 'ZERO',
  'VOID', 'NULL', 'STACK', 'HEAP', 'BUFFER', 'EXPLOIT', 'PAYLOAD', 'SHELL',
  'ROOT', 'ADMIN', 'SYSOP', 'BACKDOOR', 'TROJAN', 'WORM', 'VIRUS', 'LOGIC',
  'GATE', 'FLUX', 'PULSE', 'SURGE', 'SPARK', 'BOLT', 'THUNDER', 'LIGHTNING',
  'DARK', 'LIGHT', 'NOVA', 'STAR', 'MOON', 'SUN', 'COMET', 'NEBULA',
  'OMEGA', 'ALPHA', 'DELTA', 'GAMMA', 'BETA', 'SIGMA', 'THETA', 'ZETA',
  'CYBER', 'TECH', 'NET', 'WEB', 'GRID', 'MESH', 'NODE', 'LINK',
  'IRON', 'STEEL', 'TITAN', 'ATLAS', 'HAWK', 'EAGLE', 'FALCON', 'WOLF',
  'LION', 'TIGER', 'DRAGON', 'PHOENIX', 'HYDRA', 'KRAKEN', 'LEVIATHAN', 'SPHINX',
  'ORACLE', 'PROPHET', 'MYSTIC', 'WIZARD'
];

// Character set (excludes confusing chars: 0/O, 1/I/L)
const CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/**
 * Generate a random recovery code
 * @returns {string} Recovery code in format WORD-XXXX-XXXX
 */
function generateRecoveryCode() {
  const word = WORDS[Math.floor(Math.random() * WORDS.length)];
  const part1 = Array(4).fill().map(() =>
    CHARS[Math.floor(Math.random() * CHARS.length)]
  ).join('');
  const part2 = Array(4).fill().map(() =>
    CHARS[Math.floor(Math.random() * CHARS.length)]
  ).join('');
  return `${word}-${part1}-${part2}`;
}

/**
 * Validate recovery code format
 * @param {string} code - The code to validate
 * @returns {boolean} True if valid format
 */
function isValidRecoveryCode(code) {
  if (!code || typeof code !== 'string') return false;
  const parts = code.toUpperCase().split('-');
  if (parts.length !== 3) return false;
  if (!WORDS.includes(parts[0])) return false;
  if (parts[1].length !== 4 || parts[2].length !== 4) return false;
  const validChars = new RegExp(`^[${CHARS}]+$`);
  return validChars.test(parts[1]) && validChars.test(parts[2]);
}

module.exports = {
  generateRecoveryCode,
  isValidRecoveryCode,
  WORDS
};
