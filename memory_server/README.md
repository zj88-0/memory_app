# ElderCare Server

Node.js + Express backend for:
1. **Speech-to-Text** (`POST /stt`) — Google Cloud STT with Singapore locale support
2. **Moments** (`GET/POST/DELETE /moments`) — Group photo/caption sharing
3. **Health** (`GET /health`) — Status check

## Setup

```bash
npm install
cp .env.example .env
# Edit .env and set your GOOGLE_APPLICATION_CREDENTIALS path
node src/index.js
# or for dev: npm run dev
```

## Google Cloud STT Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a project → Enable **Cloud Speech-to-Text API**
3. Create a Service Account → Download the JSON key
4. Put the key file in the server folder and update `.env`:
   ```
   GOOGLE_APPLICATION_CREDENTIALS=./my-key.json
   ```

## Without Google credentials

The server starts fine without credentials. STT returns a placeholder message so the rest of the app works. Real transcription only activates once `GOOGLE_APPLICATION_CREDENTIALS` is set.

## Supported Languages

| App Code | STT BCP-47 | Notes |
|----------|-----------|-------|
| `en`     | `en-SG`   | English Singapore + Singlish phrases boosted |
| `zh`     | `zh-SG`   | Mandarin Singapore |
| `ms`     | `ms-MY`   | Bahasa Melayu |
| `ta`     | `ta-SG`   | Tamil (uses `ta-IN` model) |

For `en-SG`, Singlish filler words (`lah`, `lor`, `leh`, `meh`, `sia`, `alamak` etc.) are added as speech context to improve recognition.

## API Reference

### POST /stt
Transcribe audio to text.

**Form fields:**
- `audio` (file) — audio file (.aac, .wav, .mp3)
- `language` (string) — BCP-47 code: `en-SG`, `zh-SG`, `ms-MY`, `ta-SG`

**Response:**
```json
{ "transcript": "I need help", "language": "en-SG", "confidence": 0.92 }
```

### GET /moments/:groupId
Fetch all moments for a group.

### POST /moments
Upload a new moment.

**Form fields:**
- `id`, `groupId`, `authorId`, `authorName`, `caption`, `createdAt`
- `image` (file, optional) — image file

### DELETE /moments/:momentId
Delete a moment and its image.

### GET /moments/image/:momentId
Serve the image for a moment.

## Flutter App Configuration

In `lib/services/stt_service.dart` and `lib/services/api_service.dart`:
```dart
static const String baseUrl = 'http://10.0.2.2:3000'; // Android emulator
// Change to your server IP for physical device:
// static const String baseUrl = 'http://192.168.1.x:3000';
```
