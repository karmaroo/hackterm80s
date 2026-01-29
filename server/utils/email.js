/**
 * Email Utility for sending recovery codes
 *
 * TODO: Configure actual email provider (Mailgun, SendGrid, SMTP, etc.)
 * For now, logs emails to console for development.
 */

const nodemailer = require('nodemailer');

// Configure transporter based on environment
let transporter = null;

function initEmailTransporter() {
  const smtpHost = process.env.SMTP_HOST;
  const smtpPort = process.env.SMTP_PORT || 587;
  const smtpUser = process.env.SMTP_USER;
  const smtpPass = process.env.SMTP_PASS;

  if (smtpHost && smtpUser && smtpPass) {
    transporter = nodemailer.createTransport({
      host: smtpHost,
      port: parseInt(smtpPort),
      secure: smtpPort === '465',
      auth: {
        user: smtpUser,
        pass: smtpPass
      }
    });
    console.log('[EMAIL] SMTP configured:', smtpHost);
  } else {
    console.log('[EMAIL] No SMTP configured - emails will be logged to console');
  }
}

/**
 * Send recovery code email to player
 * @param {string} email - Player's email address
 * @param {string} handle - Player's handle
 * @param {string} recoveryCode - The recovery code
 * @param {string} phoneNumber - Assigned phone number
 * @returns {Promise<boolean>} - Success status
 */
async function sendRecoveryCodeEmail(email, handle, recoveryCode, phoneNumber) {
  const subject = 'HackTerm80s - Your Recovery Code';
  const text = `
Welcome to HackTerm80s, ${handle}!

Your account has been created successfully.

========================================
SAVE THIS RECOVERY CODE
========================================

Recovery Code: ${recoveryCode}

Your Phone Number: ${phoneNumber}

========================================

Use this code to recover your session on any computer:
  SESSION RECOVER ${recoveryCode}

Keep this code secret - anyone with it can access your account.

- The Shadow Network
`;

  const html = `
<div style="font-family: 'Courier New', monospace; background: #0a0a0a; color: #00ff00; padding: 20px; max-width: 600px;">
  <h1 style="color: #00ff00; border-bottom: 2px solid #00ff00;">HackTerm80s</h1>
  <p>Welcome to the Shadow Network, <strong>${handle}</strong>!</p>

  <div style="background: #1a1a1a; border: 1px solid #00ff00; padding: 20px; margin: 20px 0;">
    <h2 style="color: #ffff00; margin-top: 0;">*** SAVE THIS RECOVERY CODE ***</h2>
    <p style="font-size: 24px; color: #00ffff; letter-spacing: 4px;"><strong>${recoveryCode}</strong></p>
    <p>Your Phone Number: <strong>${phoneNumber}</strong></p>
  </div>

  <p>Use this code to recover your session on any computer:</p>
  <pre style="background: #000; padding: 10px; color: #00ff00;">SESSION RECOVER ${recoveryCode}</pre>

  <p style="color: #ff6600;">Keep this code secret - anyone with it can access your account.</p>

  <p style="color: #666; margin-top: 30px;">- The Shadow Network</p>
</div>
`;

  if (transporter) {
    try {
      await transporter.sendMail({
        from: process.env.SMTP_FROM || '"HackTerm80s" <noreply@hackterm80s.com>',
        to: email,
        subject,
        text,
        html
      });
      console.log(`[EMAIL] Recovery code sent to ${email}`);
      return true;
    } catch (error) {
      console.error(`[EMAIL] Failed to send to ${email}:`, error.message);
      return false;
    }
  } else {
    // Development mode - log to console
    console.log('========================================');
    console.log('[EMAIL] Would send to:', email);
    console.log('[EMAIL] Subject:', subject);
    console.log('[EMAIL] Recovery Code:', recoveryCode);
    console.log('========================================');
    return true;
  }
}

/**
 * Validate email format
 * @param {string} email - Email to validate
 * @returns {boolean}
 */
function isValidEmail(email) {
  if (!email || typeof email !== 'string') return false;
  // Basic email regex - not perfect but catches most issues
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email.trim());
}

module.exports = {
  initEmailTransporter,
  sendRecoveryCodeEmail,
  isValidEmail
};
