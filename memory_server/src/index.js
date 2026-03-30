require('dotenv').config();
const express = require('express');
const cors    = require('cors');
const path    = require('path');
const fs      = require('fs');

const sttRoutes     = require('./routes/stt');
const momentsRoutes = require('./routes/moments');
const eventsRoutes  = require('./routes/events');   // ← NEW

const app  = express();
const PORT = process.env.PORT || 3000;

// ── Admin page ────────────────────────────────────────────────────────────────
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'events_admin.html'));
});

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json({ limit: '20mb' }));
app.use(express.urlencoded({ extended: true, limit: '20mb' }));

// Serve uploaded moment images statically
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/stt',     sttRoutes);
app.use('/moments', momentsRoutes);
app.use('/events',  eventsRoutes);   // ← NEW

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`ElderCare server running on http://0.0.0.0:${PORT}`);
  console.log(`Admin panel   : http://localhost:${PORT}/admin`);
  console.log(`STT endpoint  : POST /stt`);
  console.log(`Moments       : GET/POST /moments, DELETE /moments/:id`);
  console.log(`Events        : GET /events, GET /events/categories, POST /events/refresh`);
  console.log(`Health check  : GET /health`);
});

module.exports = app;
