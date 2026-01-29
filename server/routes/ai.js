/**
 * AI Asset Generation Routes
 *
 * Proxies requests to Google Imagen API, keeping API key server-side.
 * Provides rate limiting and usage tracking.
 */

const express = require('express');
const router = express.Router();

// Rate limiting
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX_REQUESTS = 5; // 5 requests per minute per IP
const rateLimitMap = new Map();

// Usage tracking
let totalGenerations = 0;
let generationsByDay = {};

/**
 * Simple rate limiter middleware
 */
function rateLimiter(req, res, next) {
    const ip = req.ip || req.connection.remoteAddress;
    const now = Date.now();

    if (!rateLimitMap.has(ip)) {
        rateLimitMap.set(ip, { count: 0, resetTime: now + RATE_LIMIT_WINDOW_MS });
    }

    const limit = rateLimitMap.get(ip);

    if (now > limit.resetTime) {
        limit.count = 0;
        limit.resetTime = now + RATE_LIMIT_WINDOW_MS;
    }

    limit.count++;

    if (limit.count > RATE_LIMIT_MAX_REQUESTS) {
        return res.status(429).json({
            error: 'Rate limit exceeded',
            retryAfter: Math.ceil((limit.resetTime - now) / 1000)
        });
    }

    next();
}

/**
 * POST /api/assets/generate
 *
 * Generate an image using Google Imagen API
 *
 * Body:
 *   - prompt: string (required) - The image generation prompt
 *   - aspect_ratio: string (optional) - "1:1", "16:9", "9:16", "4:3", "3:4"
 *   - style: string (optional) - Style preset name
 */
router.post('/generate', rateLimiter, async (req, res) => {
    const { prompt, aspect_ratio = '1:1', style = 'retro_80s' } = req.body;

    if (!prompt) {
        return res.status(400).json({ error: 'Prompt is required' });
    }

    // Get API key from environment
    const apiKey = process.env.GOOGLE_AI_API_KEY;

    if (!apiKey) {
        console.error('[AI] GOOGLE_AI_API_KEY not configured');
        return res.status(500).json({ error: 'AI generation not configured' });
    }

    console.log(`[AI] Generation request: "${prompt.substring(0, 50)}..." (${aspect_ratio})`);

    try {
        // Call Google Imagen API
        const response = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/imagen-4.0-generate-001:predict?key=${apiKey}`,
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    instances: [{ prompt }],
                    parameters: {
                        sampleCount: 1,
                        aspectRatio: aspect_ratio,
                        safetyFilterLevel: 'block_medium_and_above',
                        personGeneration: 'dont_allow'
                    }
                })
            }
        );

        if (!response.ok) {
            const errorText = await response.text();
            console.error(`[AI] API error ${response.status}: ${errorText}`);
            return res.status(response.status).json({
                error: `API error: ${response.statusText}`,
                details: errorText
            });
        }

        const data = await response.json();

        // Check for predictions
        if (!data.predictions || data.predictions.length === 0) {
            console.error('[AI] No predictions in response');
            return res.status(500).json({ error: 'No image generated' });
        }

        // Get base64 image
        const imageBase64 = data.predictions[0].bytesBase64Encoded;

        if (!imageBase64) {
            console.error('[AI] No image data in prediction');
            return res.status(500).json({ error: 'No image data in response' });
        }

        // Track usage
        totalGenerations++;
        const today = new Date().toISOString().split('T')[0];
        generationsByDay[today] = (generationsByDay[today] || 0) + 1;

        console.log(`[AI] Generation successful (total: ${totalGenerations})`);

        res.json({
            success: true,
            image: imageBase64,
            mimeType: data.predictions[0].mimeType || 'image/png'
        });

    } catch (error) {
        console.error('[AI] Generation error:', error);
        res.status(500).json({ error: 'Generation failed: ' + error.message });
    }
});

/**
 * GET /api/assets/generate/status
 *
 * Check if AI generation is available and get usage stats
 */
router.get('/generate/status', (req, res) => {
    const apiKey = process.env.GOOGLE_AI_API_KEY;

    res.json({
        available: !!apiKey,
        rateLimitPerMinute: RATE_LIMIT_MAX_REQUESTS,
        totalGenerations,
        generationsToday: generationsByDay[new Date().toISOString().split('T')[0]] || 0
    });
});

/**
 * GET /api/assets/generate/presets
 *
 * Get available style presets and object types
 */
router.get('/generate/presets', (req, res) => {
    res.json({
        styles: {
            retro_80s: {
                name: '1980s Retro',
                description: 'Vintage computing aesthetic with CRT colors'
            },
            pixel_art: {
                name: 'Pixel Art',
                description: '16-bit era sprite style'
            },
            photorealistic: {
                name: 'Photorealistic',
                description: 'Studio quality product shot'
            },
            hand_drawn: {
                name: 'Hand Drawn',
                description: 'Vintage technical manual illustration'
            }
        },
        objectTypes: {
            book: 'Book or Manual',
            desk_accessory: 'Desk Accessory',
            tech_prop: 'Tech Equipment',
            poster: 'Poster/Wall Art',
            plant: 'Plant',
            beverage: 'Beverage',
            stationery: 'Office Supplies',
            floppy_disk: 'Floppy Disk',
            cassette: 'Cassette Tape',
            cable: 'Cable/Connector'
        },
        aspectRatios: ['1:1', '16:9', '9:16', '4:3', '3:4']
    });
});

module.exports = router;
