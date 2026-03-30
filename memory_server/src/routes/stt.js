const express = require('express');
const multer  = require('multer');
const fs      = require('fs');
const path    = require('path');
const { SpeechClient } = require('@google-cloud/speech');

const router = express.Router();

// ── Multer: store audio temporarily ──────────────────────────────────────────
const upload = multer({
  dest: path.join(__dirname, '../../uploads/tmp'),
  limits: { fileSize: parseInt(process.env.MAX_FILE_SIZE) || 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['audio/aac', 'audio/mpeg', 'audio/wav', 'audio/webm',
                     'audio/ogg', 'application/octet-stream'];
    cb(null, true); // accept all — client sends raw audio bytes
  },
});

// ── Google Speech client ──────────────────────────────────────────────────────
let speechClient;
try {
  speechClient = new SpeechClient();
} catch (e) {
  console.warn('⚠️  Google Speech credentials not configured. STT will return mock results.');
  console.warn('    Set GOOGLE_APPLICATION_CREDENTIALS in .env to enable real STT.');
}

// ── Language → STT config map ─────────────────────────────────────────────────
// Singapore-specific models and alternativeLanguageCodes for Singlish mixing
const langConfig = {
  'en-SG': {
    languageCode: 'en-SG',
    // Singlish often mixes Mandarin/Malay/Tamil words — add them as alternatives
    alternativeLanguageCodes: ['zh-SG', 'ms-MY', 'ta-SG'],
    model: 'latest_long',
    useEnhanced: true,
  },
  'zh-SG': {
    languageCode: 'zh',         // Google uses 'zh' for Mandarin (Traditional/Simplified)
    alternativeLanguageCodes: ['en-SG'],
    model: 'latest_long',
    useEnhanced: false,
  },
  'ms-MY': {
    languageCode: 'ms-MY',
    alternativeLanguageCodes: ['en-SG'],
    model: 'latest_long',
    useEnhanced: false,
  },
  'ta-SG': {
    languageCode: 'ta-IN',      // Google uses ta-IN; closest to Tamil Singapore
    alternativeLanguageCodes: ['en-SG'],
    model: 'latest_long',
    useEnhanced: false,
  },
};

// ── POST /stt ────────────────────────────────────────────────────────────────
// Body: multipart form — audio file + language field
router.post('/', upload.single('audio'), async (req, res) => {
  const audioPath = req.file?.path;

  try {
    const language = req.body.language || 'en-SG';
    const config   = langConfig[language] || langConfig['en-SG'];

    // ── Mock mode: if no Google credentials, return a placeholder ────────────
    if (!speechClient) {
      if (audioPath) fs.unlinkSync(audioPath);
      return res.json({
        transcript: '[STT not configured — set GOOGLE_APPLICATION_CREDENTIALS in .env]',
        language,
        confidence: 0,
      });
    }

    if (!audioPath) {
      return res.status(400).json({ error: 'No audio file received' });
    }

    // Read audio file
    const audioBytes = fs.readFileSync(audioPath).toString('base64');

    // Build Google STT request
    const request = {
      audio: { content: audioBytes },
      config: {
        encoding: 'LINEAR16',  // Match Flutter app recording format (Code.pcm16WAV)
        sampleRateHertz: 16000,
        languageCode: config.languageCode,
        alternativeLanguageCodes: config.alternativeLanguageCodes,
        model: config.model,
        useEnhanced: config.useEnhanced,
        enableAutomaticPunctuation: true,
        // Singlish phrases / local words — boost recognition
        speechContexts: language === 'en-SG' ? [{
          phrases: [
            'lah', 'lor', 'leh', 'meh', 'sia', 'shiok', 'alamak',
            'can', 'cannot', 'need help', 'toilet', 'medicine', 'makan',
            'take medicine', 'go toilet', 'help me', 'pain', 'dizzy',
            'need water', 'call doctor',
          ],
          boost: 15.0,
        }] : [],
      },
    };

    const [response] = await speechClient.recognize(request);
    const transcript = response.results
      .map(r => r.alternatives[0]?.transcript || '')
      .join(' ')
      .trim();

    const confidence = response.results[0]?.alternatives[0]?.confidence || 0;

    res.json({ transcript, language, confidence });

  } catch (err) {
    console.error('STT error:', err.message);
    res.status(500).json({ error: 'STT processing failed', detail: err.message });
  } finally {
    // Always clean up temp audio file
    if (audioPath && fs.existsSync(audioPath)) {
      fs.unlinkSync(audioPath);
    }
  }
});

module.exports = router;
