const express = require('express');
const fs = require('fs');
const path = require('path');
const { GoogleGenerativeAI } = require('@google/generative-ai');

const router = express.Router();

// ── File paths ────────────────────────────────────────────────────────────────
const DATA_DIR   = path.join(__dirname, '../../uploads');
const EVENTS_CSV = path.join(DATA_DIR, 'events.csv');
const META_FILE  = path.join(DATA_DIR, 'events_meta.json');

const CSV_HEADER = `id,title,category,startTime,endTime,location,imageUrl,eventUrl,description`;

// ── Categories ────────────────────────────────────────────────────────────────
const CATEGORIES = [
  'Exercise & Wellness',
  'Arts & Crafts',
  'Music & Entertainment',
  'Social & Community',
  'Learning & Education',
  'Nature & Gardening',
  'Food & Cooking',
  'Technology & Digital',
  'Religious & Spiritual',
  'Games & Recreation',
];

// ── CSV helpers ───────────────────────────────────────────────────────────────
function parseCSVRow(line) {
  const result = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      inQuotes = !inQuotes;
    } else if (ch === ',' && !inQuotes) {
      result.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  result.push(current.trim());
  return result;
}

function readEvents() {
  try {
    if (!fs.existsSync(EVENTS_CSV)) return [];
    const lines = fs.readFileSync(EVENTS_CSV, 'utf8').trim().split('\n');
    if (lines.length < 2) return [];
    const headers = lines[0].split(',').map(h => h.trim().replace(/^"|"$/g, ''));
    const events = [];
    for (let i = 1; i < lines.length; i++) {
      if (!lines[i].trim()) continue;
      const row = parseCSVRow(lines[i]);
      if (row.length < headers.length) continue;
      const obj = {};
      headers.forEach((h, idx) => { obj[h] = (row[idx] || '').replace(/^"|"$/g, ''); });
      // Filter out past events
      if (obj.endTime) {
        const endDate = new Date(obj.endTime);
        if (!isNaN(endDate) && endDate < new Date()) continue;
      }
      events.push(obj);
    }
    return events;
  } catch (e) {
    console.error('Error reading events CSV:', e.message);
    return [];
  }
}

/** Append new data rows to the CSV (never replaces, never duplicates header) */
function appendEvents(csvWithHeader) {
  fs.mkdirSync(DATA_DIR, { recursive: true });

  const newLines = csvWithHeader.trim().split('\n').filter(l => l.trim());
  // Drop the header row from the generated CSV
  const dataRows = newLines[0].toLowerCase().includes('id,title') ? newLines.slice(1) : newLines;

  if (!fs.existsSync(EVENTS_CSV)) {
    // First time — write header + rows
    fs.writeFileSync(EVENTS_CSV, [CSV_HEADER, ...dataRows].join('\n') + '\n', 'utf8');
    console.log(`📋 Events CSV created with ${dataRows.length} rows`);
  } else {
    // Append rows only
    fs.appendFileSync(EVENTS_CSV, '\n' + dataRows.join('\n') + '\n', 'utf8');
    console.log(`✅ Appended ${dataRows.length} new events to CSV`);
  }

  fs.writeFileSync(META_FILE, JSON.stringify({
    lastUpdated: new Date().toISOString(),
    generatedBy: 'gemini',
  }), 'utf8');
}

/** Write seed events if CSV is missing */
function ensureSeedExists() {
  if (fs.existsSync(EVENTS_CSV)) {
    console.log('✅ Loaded existing events CSV. (AI refresh is manual via /admin)');
    return;
  }
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(EVENTS_CSV, seedCSV(), 'utf8');
  console.log('📋 Seed events written — no CSV existed yet.');
}

// ── Gemini: generate 5 new events ────────────────────────────────────────────
async function generateEventsWithGemini(startIndex) {
  if (!process.env.GEMINI_API_KEY) {
    console.warn('⚠️  GEMINI_API_KEY not set in .env');
    return null;
  }

  try {
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

    // ── Free-tier model fallback chain ──────────────────────────────────────────
    // gemini-1.5-flash-8b  → 1000 req/day free (highest quota, try first)
    // gemini-1.5-flash     → 1500 req/day free
    // gemini-2.0-flash     → 200  req/day free (exhausts fastest)
    const MODELS = ['gemini-1.5-flash-8b', 'gemini-1.5-flash', 'gemini-2.0-flash'];

    const todayStr = new Date().toISOString().split('T')[0];
    const endDate  = new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0];

    const idPad = (n) => `evt_${String(n).padStart(3, '0')}`;

    const prompt =
`You are a Singapore event data generator for elderly citizens (60+).

Generate exactly 5 new Singapore events for elderly. Date range: ${todayStr} to ${endDate} (Singapore time UTC+8).

Return ONLY a CSV — no markdown, no code fences, no explanation.
Header row: id,title,category,startTime,endTime,location,imageUrl,eventUrl,description

FIELD RULES:
- id: ${idPad(startIndex)} to ${idPad(startIndex + 4)} (increment each row)
- title: specific event name (e.g. "Monday Morning Tai Chi at Bishan CC")
- category: exactly one of: ${CATEGORIES.join(' | ')}
- startTime / endTime: ISO 8601 with +08:00 offset, 2-hour duration, during daytime 8am–6pm
- location: a real Singapore community centre or park with full name (e.g. "Bishan Community Club, 51 Bishan St 13")
- imageUrl: use exactly this format https://images.unsplash.com/photo-<PHOTO_ID>?w=400
  Choose the correct photo ID for the category:
  Exercise & Wellness    → 1506126613408-eca07ce68773
  Arts & Crafts          → 1513364776537-544eb5916dbe
  Music & Entertainment  → 1493225457124-a3eb161ffa5f
  Social & Community     → 1529156069898-49953e39b3ac
  Learning & Education   → 1481627834876-b7833e8f5570
  Nature & Gardening     → 1416879595882-3373a0480b5b
  Food & Cooking         → 1466637574441-749b8f19452f
  Technology & Digital   → 1518770660439-464ac0c5e5e1
  Religious & Spiritual  → 1544427920-c49ccfef85a5
  Games & Recreation     → 1542751371-6533d-6ee-a-4e-4-a-3e-4-4-3a3e83851

- eventUrl: use a SPECIFIC deep-link page, not a homepage. Use these exact URL patterns per category:
  Exercise & Wellness    → https://www.activesgcircle.gov.sg/activities/group-exercise
  Arts & Crafts          → https://www.pa.gov.sg/engage/get-active/arts-and-culture
  Music & Entertainment  → https://www.pa.gov.sg/engage/get-active/arts-and-culture
  Social & Community     → https://www.pa.gov.sg/engage/get-active/active-ageing-centre
  Learning & Education   → https://www.nlb.gov.sg/main/whats-on/events-and-programmes
  Nature & Gardening     → https://www.nparks.gov.sg/gardening/community-in-bloom/community-gardens
  Food & Cooking         → https://www.healthhub.sg/live-healthy/nutrition
  Technology & Digital   → https://www.imda.gov.sg/how-we-can-help/seniors-go-digital
  Religious & Spiritual  → https://www.mccy.gov.sg/sectors/rh
  Games & Recreation     → https://www.pa.gov.sg/engage/get-active/active-ageing-centre

- description: exactly 1 sentence, warm and encouraging, max 15 words

Pick 5 DIFFERENT categories from the list above (no repeats in this batch).
All fields must be quoted with double-quotes in the CSV.`;

    // ── Try each model, skip on 429, fail on other errors ───────────────────────
    let text = null;
    let lastErr = null;

    for (const MODEL of MODELS) {
      try {
        console.log(`🤖 Trying model: ${MODEL}…`);
        const model  = genAI.getGenerativeModel({ model: MODEL });
        const result = await model.generateContent(prompt);
        text = result.response.text().trim()
          .replace(/^```[a-z]*\n?/i, '')
          .replace(/\n?```$/i, '')
          .trim();
        console.log(`✅ ${MODEL} succeeded`);
        break;
      } catch (e) {
        lastErr = e;
        const msg = String(e.message || e);
        if (msg.includes('429') || msg.toLowerCase().includes('quota') || msg.toLowerCase().includes('rate')) {
          console.warn(`⚠️  ${MODEL} quota/rate-limit hit — trying next model…`);
          continue;
        }
        // Not a quota error — stop immediately
        throw e;
      }
    }

    if (!text) {
      const retryMsg = lastErr?.message?.match(/retry in (\d+)/i);
      const wait = retryMsg ? ` Please retry in ${retryMsg[1]}s.` : '';
      throw new Error(`All Gemini models quota exceeded.${wait}`);
    }

    const lines = text.split('\n').filter(l => l.trim());
    if (lines.length < 2) {
      throw new Error(`Gemini returned too few lines (${lines.length}): ${text.substring(0, 200)}`);
    }

    console.log(`🤖 Gemini returned ${lines.length} line(s)`);
    return text;

  } catch (e) {
    console.error('Gemini event generation failed:', e.message || e);
    return null;
  }
}

// ── Seed CSV (used only if no CSV file exists at all) ─────────────────────────
function seedCSV() {
  const today = new Date();
  const fmt   = (d) => d.toISOString().replace('Z', '+08:00');
  const day   = (n, h = 9) => {
    const d = new Date(today.getTime() + n * 86400000);
    d.setHours(h, 0, 0, 0);
    return d;
  };

  const rows = [
    [`evt_001`, `Morning Tai Chi at East Coast Park`, `Exercise & Wellness`,
      fmt(day(1, 7)), fmt(day(1, 9)), `East Coast Park, Marine Parade Road`,
      `https://images.unsplash.com/photo-1506126613408-eca07ce68773?w=400`,
      `https://www.activesgcircle.gov.sg/activities/group-exercise`,
      `Join a gentle seaside Tai Chi session perfect for all fitness levels.`],
    [`evt_002`, `Watercolour Painting Workshop`, `Arts & Crafts`,
      fmt(day(2, 10)), fmt(day(2, 12)), `Toa Payoh Community Club, 93 Toa Payoh Central`,
      `https://images.unsplash.com/photo-1513364776537-544eb5916dbe?w=400`,
      `https://www.pa.gov.sg/engage/get-active/arts-and-culture`,
      `Discover the joy of watercolour painting with a friendly instructor.`],
    [`evt_003`, `Seniors Sing-Along Session`, `Music & Entertainment`,
      fmt(day(3, 14)), fmt(day(3, 16)), `Bishan Community Club, 51 Bishan Street 13`,
      `https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400`,
      `https://www.pa.gov.sg/engage/get-active/arts-and-culture`,
      `Sing classic favourites together and enjoy a warm, joyful afternoon.`],
    [`evt_004`, `Coffee Morning & Chit-Chat`, `Social & Community`,
      fmt(day(4, 9)), fmt(day(4, 11)), `Tampines Hub, 1 Tampines Walk`,
      `https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=400`,
      `https://www.pa.gov.sg/engage/get-active/active-ageing-centre`,
      `Make new friends over kopi and enjoy lively conversation with neighbours.`],
    [`evt_005`, `Smartphone Tips for Seniors`, `Technology & Digital`,
      fmt(day(5, 10)), fmt(day(5, 12)), `Jurong Regional Library, 21 Jurong East Central 1`,
      `https://images.unsplash.com/photo-1518770660439-464ac0c5e5e1?w=400`,
      `https://www.imda.gov.sg/how-we-can-help/seniors-go-digital`,
      `Learn handy smartphone tips to stay connected with your loved ones.`],
    [`evt_006`, `Community Garden Planting Day`, `Nature & Gardening`,
      fmt(day(6, 8)), fmt(day(6, 10)), `Ang Mo Kio Town Garden West, Ang Mo Kio Ave 3`,
      `https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=400`,
      `https://www.nparks.gov.sg/gardening/community-in-bloom/community-gardens`,
      `Get your hands in the soil and grow vegetables with friendly neighbours.`],
    [`evt_007`, `Healthy Cooking: Low-Sugar Desserts`, `Food & Cooking`,
      fmt(day(7, 10)), fmt(day(7, 12)), `Queenstown Community Centre, 1 Queenstown Road`,
      `https://images.unsplash.com/photo-1466637574441-749b8f19452f?w=400`,
      `https://www.healthhub.sg/live-healthy/nutrition`,
      `Learn to make delicious, health-conscious desserts gentle on blood sugar.`],
    [`evt_008`, `Mahjong & Board Games Afternoon`, `Games & Recreation`,
      fmt(day(8, 14)), fmt(day(8, 16)), `Bedok Community Centre, 850 New Upper Changi Road`,
      `https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=400`,
      `https://www.pa.gov.sg/engage/get-active/active-ageing-centre`,
      `Enjoy a relaxing afternoon of mahjong and board games with neighbours.`],
    [`evt_009`, `Singapore History: Old Memories Talk`, `Learning & Education`,
      fmt(day(9, 10)), fmt(day(9, 12)), `National Library Building, 100 Victoria Street`,
      `https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=400`,
      `https://www.nlb.gov.sg/main/whats-on/events-and-programmes`,
      `Travel back in time with fascinating stories and rare photographs of old Singapore.`],
    [`evt_010`, `Chair Yoga for Seniors`, `Exercise & Wellness`,
      fmt(day(10, 9)), fmt(day(10, 11)), `Sengkang Sports Centre, 57 Anchorvale Road`,
      `https://images.unsplash.com/photo-1506126613408-eca07ce68773?w=400`,
      `https://www.activesgcircle.gov.sg/activities/group-exercise`,
      `Gentle seated yoga to improve flexibility and calm the mind — no experience needed.`],
  ];

  const csvRows = rows.map(r =>
    r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')
  );
  return [CSV_HEADER, ...csvRows].join('\n') + '\n';
}

// ── Startup: ensure CSV exists (NO auto-refresh — manual only) ────────────────
ensureSeedExists();

// ── GET /events ───────────────────────────────────────────────────────────────
router.get('/', (req, res) => {
  const events = readEvents();
  const cats   = req.query.categories ? req.query.categories.split(',') : null;
  const result = cats
    ? events.filter(e => cats.some(c =>
        e.category?.toLowerCase().includes(c.toLowerCase())))
    : events;
  res.json(result);
});

// ── GET /events/categories ────────────────────────────────────────────────────
router.get('/categories', (req, res) => {
  res.json(CATEGORIES);
});

// ── GET /events/meta — last updated timestamp ─────────────────────────────────
router.get('/meta', (req, res) => {
  try {
    if (!fs.existsSync(META_FILE)) return res.json({ lastUpdated: null });
    res.json(JSON.parse(fs.readFileSync(META_FILE, 'utf8')));
  } catch (_) {
    res.json({ lastUpdated: null });
  }
});

// ── POST /events/refresh — append 5 new AI events ────────────────────────────
router.post('/refresh', async (req, res) => {
  console.log('🔄 Add events triggered — calling Gemini…');

  // Find highest existing evt_ id so new ones don't clash
  const existing  = readEvents();
  let maxIdNum    = 0;
  existing.forEach(e => {
    if (e.id && e.id.startsWith('evt_')) {
      const num = parseInt(e.id.replace('evt_', ''), 10);
      if (!isNaN(num) && num > maxIdNum) maxIdNum = num;
    }
  });
  const startIndex = maxIdNum + 1;

  const csv = await generateEventsWithGemini(startIndex);
  if (csv) {
    appendEvents(csv);
    const total = readEvents().length;
    res.json({
      success: true,
      message: `5 new events added by Gemini (${total} total upcoming)`,
      count: total,
    });
  } else {
    res.status(500).json({
      success: false,
      message: 'Gemini unavailable — check GEMINI_API_KEY in .env and try again.',
    });
  }
});

module.exports = router;