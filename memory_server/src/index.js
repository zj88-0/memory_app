require('dotenv').config();
const express = require('express');
const cors    = require('cors');
const path    = require('path');
const fs      = require('fs');

const sttRoutes     = require('./routes/stt');
const momentsRoutes = require('./routes/moments');

const app  = express();
const PORT = process.env.PORT || 3000;

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json({ limit: '20mb' }));
app.use(express.urlencoded({ extended: true, limit: '20mb' }));

// Serve uploaded moment images statically
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/stt',     sttRoutes);
app.use('/moments', momentsRoutes);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`ElderCare server running on http://0.0.0.0:${PORT}`);
  console.log(`STT endpoint  : POST /stt`);
  console.log(`Moments       : GET/POST /moments, DELETE /moments/:id`);
  console.log(`Health check  : GET /health`);
});

module.exports = app;
