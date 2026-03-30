const express  = require('express');
const multer   = require('multer');
const path     = require('path');
const fs       = require('fs');
const { v4: uuidv4 } = require('uuid');

const router = express.Router();

// ── Persistent JSON store ──────────────────────────────────────────────────────
// File-based persistence so data survives restarts.
// Swap readStore/writeStore for MongoDB queries in production.
const STORE_FILE = path.join(__dirname, '../../uploads/moments.json');

function readStore() {
  try {
    if (!fs.existsSync(STORE_FILE)) return [];
    return JSON.parse(fs.readFileSync(STORE_FILE, 'utf8'));
  } catch { return []; }
}

function writeStore(moments) {
  fs.mkdirSync(path.dirname(STORE_FILE), { recursive: true });
  fs.writeFileSync(STORE_FILE, JSON.stringify(moments, null, 2));
}

// ── Multer: Fix #2 — save images to uploads/moments/ with stable filenames ────
const MOMENTS_DIR = path.join(__dirname, '../../uploads/moments');

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    fs.mkdirSync(MOMENTS_DIR, { recursive: true });
    cb(null, MOMENTS_DIR);
  },
  filename: (req, file, cb) => {
    // Use the moment id from the body so we can reconstruct the URL later
    const id  = req.body.id || uuidv4();
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${id}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: parseInt(process.env.MAX_FILE_SIZE) || 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    console.log('📸 Uploading file:', file.originalname, 'mimetype:', file.mimetype);
    // Allow standard images AND generic binary streams (often caused by phone image pickers lacking .jpg extensions)
    if (file.mimetype.startsWith('image/') || file.mimetype === 'application/octet-stream') {
      cb(null, true);
    } else {
      console.log('❌ Rejected file with mimetype:', file.mimetype);
      cb(new Error('Only image files are allowed'));
    }
  },
});

// ── GET /moments/:groupId ─────────────────────────────────────────────────────
router.get('/:groupId', (req, res) => {
  const all = readStore();
  const group = all
    .filter(m => m.groupId === req.params.groupId)
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  res.json(group);
});

// ── GET /moments/image/:momentId — serve image file ───────────────────────────
router.get('/image/:momentId', (req, res) => {
  const files = fs.existsSync(MOMENTS_DIR) ? fs.readdirSync(MOMENTS_DIR) : [];
  const file  = files.find(f => f.startsWith(req.params.momentId));
  if (file) {
    res.sendFile(path.join(MOMENTS_DIR, file));
  } else {
    res.status(404).json({ error: 'Image not found' });
  }
});

// ── POST /moments — Fix #2: save image to disk, persist metadata to JSON ──────
router.post('/', upload.single('image'), (req, res) => {
  const {
    id          = uuidv4(),
    groupId, authorId,
    authorName  = 'Unknown',
    caption     = '',
    createdAt   = new Date().toISOString(),
  } = req.body;

  if (!groupId) return res.status(400).json({ error: 'groupId is required' });

  // Build image URL that client can use to fetch the image
  let imageUrl = null;
  if (req.file) {
    imageUrl = `/moments/image/${id}`;
  }

  const moment = { id, groupId, authorId, authorName, caption, imageUrl, createdAt };

  const all = readStore();
  // Prevent duplicates (client may retry)
  if (!all.find(m => m.id === id)) {
    all.push(moment);
    writeStore(all);
    console.log(`📸 Moment saved: ${id} from ${authorName} (group ${groupId})`);
  }

  res.status(201).json(moment);
});

// ── DELETE /moments/:momentId ──────────────────────────────────────────────────
router.delete('/:momentId', (req, res) => {
  const { momentId } = req.params;
  let all = readStore();
  const moment = all.find(m => m.id === momentId);

  if (!moment) return res.status(404).json({ error: 'Not found' });

  // Delete image file
  const files = fs.existsSync(MOMENTS_DIR) ? fs.readdirSync(MOMENTS_DIR) : [];
  const imgFile = files.find(f => f.startsWith(momentId));
  if (imgFile) {
    try { fs.unlinkSync(path.join(MOMENTS_DIR, imgFile)); } catch {}
  }

  all = all.filter(m => m.id !== momentId);
  writeStore(all);
  console.log(`🗑  Moment deleted: ${momentId}`);
  res.json({ success: true });
});

// ── POST /moments/:momentId/comments ─────────────────────────────────────────
router.post('/:momentId/comments', express.json(), (req, res) => {
  const { momentId } = req.params;
  const {
    id = uuidv4(),
    authorId,
    authorName = 'Unknown',
    text,
    createdAt = new Date().toISOString()
  } = req.body;

  if (!authorId || !text) {
    return res.status(400).json({ error: 'authorId and text are required' });
  }

  const all = readStore();
  const moment = all.find(m => m.id === momentId);

  if (!moment) {
    return res.status(404).json({ error: 'Moment not found' });
  }

  if (!moment.comments) moment.comments = [];
  
  const newComment = { id, authorId, authorName, text, createdAt };
  
  if (!moment.comments.find(c => c.id === id)) {
    moment.comments.push(newComment);
    writeStore(all);
    console.log(`💬 Comment added to Moment ${momentId} from ${authorName}`);
  }

  res.status(201).json(moment);
});

module.exports = router;
