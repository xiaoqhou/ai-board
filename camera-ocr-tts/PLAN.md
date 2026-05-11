# Camera OCR → TTS Web App — Design & Implementation Plan

## 1. Goal

A mobile-first single-page web app that:
1. Captures a photo via the device camera
2. Extracts text from the image using client-side OCR (Tesseract.js)
3. Splits extracted text into sentences
4. Converts each sentence to speech using the Web Speech API
5. Plays sentences sequentially (one after another)

Zero backend, zero build step — a single HTML file that works in modern mobile browsers.

## 2. Tech Stack

| Layer | Choice | Rationale |
|---|---|---|
| **Camera** | `getUserMedia()` + `<video>` → `<canvas>` snapshot | Native browser API; no libraries needed |
| **OCR** | Tesseract.js v5 (CDN, ESM via jsDelivr) | Free, client-side, no API key; the `@next` bundle supports modern JS |
| **Sentence splitting** | Simple regex / Intl.Segmenter | Lightweight; Intl.Segmenter is built into modern browsers |
| **TTS** | Web Speech API (`SpeechSynthesisUtterance`) | Built into all modern browsers; no dependencies |
| **UI framework** | Vanilla HTML + CSS (Flexbox/Grid) + vanilla JS | No build step, single file |
| **Deployment** | Static file host (GitHub Pages, Vercel, etc.) | No server needed |

### Why not …?

- **Google Cloud Vision / AWS Textract**: Require API keys and backend proxy — violates "no backend" requirement.
- **react-native-camera / Capacitor**: Overkill for a single-file web app.
- **AWS Polly / Google Cloud TTS**: Require network and keys — Web Speech API is free and offline-capable.

## 3. Architecture (Text Diagram)

```
┌─────────────────────────────────────────────────────────┐
│                    Single HTML File                      │
│                                                          │
│  ┌──────────┐    ┌──────────┐    ┌───────────────────┐  │
│  │ Camera   │───▶│ Canvas   │───▶│ Tesseract.js OCR  │  │
│  │ (video)  │    │ snapshot │    │ (worker via CDN)  │  │
│  └──────────┘    └──────────┘    └────────┬──────────┘  │
│                                            │             │
│                                            ▼             │
│                                   ┌──────────────────┐   │
│                                   │ Sentence Splitter │   │
│                                   │ (regex/Segmenter)│   │
│                                   └────────┬─────────┘   │
│                                            │             │
│                                            ▼             │
│                                   ┌──────────────────┐   │
│                                   │  TTS Queue       │   │
│                                   │  (sequential     │   │
│                                   │   SpeechSynth)   │   │
│                                   └──────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │  UI Layer: capture btn │ progress │ text preview │    │
│  └──────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

**Data flow (end-to-end):**

1. User taps "Capture" → camera stream opens via `getUserMedia`
2. User taps "Snap" → frame frozen to `<canvas>`, stream stopped
3. Canvas blob sent to Tesseract.js → OCR worker extracts text
4. Raw text split into sentences by `Intl.Segmenter` (fallback: regex)
5. Sentences queued → each fed to `SpeechSynthesisUtterance`
6. `onend` callback dequeues and speaks next sentence
7. User can pause/skip/restart at any time

## 4. UI Design (Mobile-First)

### Layout (portrait-first, 375px – 430px width)

```
┌──────────────────────────────┐
│        🔤 Camera OCR → TTS   │  ← App title (small, centered)
├──────────────────────────────┤
│                              │
│   ┌──────────────────────┐   │
│   │   Camera Preview /   │   │  ← <video> or <img> area
│   │   Image Display      │   │     (16:9 or 4:3 ratio)
│   │                      │   │
│   └──────────────────────┘   │
│                              │
│   [ 📸 Capture Photo ]       │  ← Primary action button
│   [ 🔊 Speak Aloud ]         │  → Secondary (disabled until OCR done)
│                              │
│   ── Extracted Text ──       │
│   ┌──────────────────────┐   │
│   │ The quick brown fox  │   │  ← Scrollable text preview
│   │ jumps over the lazy  │   │
│   │ dog.                 │   │
│   └──────────────────────┘   │
│                              │
│   ■■■■■■■□□□  45%           │  ← Progress bar for TTS playback
└──────────────────────────────┘
```

### Key UI states

| State | Video area | Button | Text area |
|---|---|---|---|
| **Initial** | Empty / placeholder | "Capture Photo" | Hidden |
| **Camera live** | Video feed | "Snap Photo" | Hidden |
| **OCR in progress** | Frozen image | Disabled, spinner | "Processing…" |
| **OCR done** | Frozen image | "Speak Aloud" active | Shows text |
| **Speaking** | Frozen image | "Pause" / "Stop" | Highlights current sentence |
| **Done** | Frozen image | "Speak Aloud" | All text dimmed |

### Mobile-first CSS approach

- `<meta name="viewport">` with `width=device-width, initial-scale=1`
- Full-height layout using `100svh` (small viewport height)
- Touch-friendly buttons ≥ 48 px tap target
- Input prevention: disable pinch-zoom on camera view
- Dark/light theme support via `prefers-color-scheme`

## 5. Key Implementation Details

### 5.1 Camera (`getUserMedia`)

```js
// Constraints for mobile back camera
const constraints = {
  video: {
    facingMode: 'environment',  // back camera
    width: { ideal: 1920 },
    height: { ideal: 1080 },
  },
  audio: false,
};

const stream = await navigator.mediaDevices.getUserMedia(constraints);
video.srcObject = stream;
```

- Display `<video>` with `playsInline` + `autoplay` (required for iOS Safari)
- On "Snap": draw video frame to off-screen `<canvas>`, call `canvas.toBlob()`, stop all tracks
- Graceful fallback: `<input type="file" accept="image/*" capture="environment">`

### 5.2 OCR (Tesseract.js)

```js
import Tesseract from 'https://cdn.jsdelivr.net/npm/tesseract.js@5/+esm';

const result = await Tesseract.recognize(imageBlob, 'eng', {
  logger: (m) => { /* update progress */ },
});
const text = result.data.text;
```

- Use the ESM CDN build (no bundler needed)
- The worker downloads ~5 MB of language data on first run (cacheable)
- Show a progress bar during OCR
- Tesseract.js v5 uses a single web worker internally
- Accept both `<canvas>` blob and `<input type="file">` as image sources

### 5.3 Sentence Splitting

```js
function splitSentences(text) {
  // Prefer Intl.Segmenter (Chrome, Safari 16.4+, Firefox nightly)
  if (typeof Intl !== 'undefined' && Intl.Segmenter) {
    const segmenter = new Intl.Segmenter('en', { granularity: 'sentence' });
    return [...segmenter.segment(text)].map(s => s.segment);
  }
  // Fallback regex — handles ., !, ? with non-whitespace boundary
  return text.match(/[^.!?\s][^.!?]*[.!?]+/g) || [text];
}
```

- Filter out empty/whitespace-only segments
- Trim each sentence
- Cap at a reasonable limit (e.g., 50 sentences) to avoid TTS queue overload

### 5.4 TTS Queue (Web Speech API)

```js
function speakSentences(sentences) {
  const queue = [...sentences];
  let index = 0;

  function speakNext() {
    if (index >= queue.length) return;

    const utterance = new SpeechSynthesisUtterance(queue[index]);
    utterance.lang = 'en-US';
    utterance.rate = 1.0;

    utterance.onend = () => {
      index++;
      speakNext();
    };

    utterance.onerror = () => {
      index++;
      speakNext();  // skip errored sentence, continue
    };

    speechSynthesis.speak(utterance);
    updateUI({ currentIndex: index, total: queue.length });
  }

  speakNext();
}
```

Key considerations:
- On iOS Safari, `speechSynthesis` requires a user gesture to start (already satisfied by button tap)
- `speechSynthesis.cancel()` for stop/reset
- Track `SpeechSynthesis.pending`/`speaking` to avoid overlapping utterances
- Highlight the currently speaking sentence in the text preview

### 5.5 Edge Cases & Error Handling

| Scenario | Handling |
|---|---|
| Camera permission denied | Show fallback file input with `capture` attribute |
| Tesseract.js worker fails to download | Retry once, show descriptive error |
| OCR returns empty text | Show "No text found" message, enable re-capture |
| TTS not supported | Detect `window.speechSynthesis`, show fallback text copy button |
| iOS Safari restrictions | `playsinline` on video, gesture-initiated TTS, avoid autoplay |
| Very long text | Truncate / warn before TTS (e.g., >100 sentences) |
| Network offline during OCR | Language data must be cached from prior run; show error if first run |
| User navigates away / background tab | `visibilitychange` → pause TTS, resume on return |
| Slow OCR (>10s) | Progress bar + cancel button |

## 6. File Structure

```
camera-ocr-tts/
├── PLAN.md              # This file — design & implementation plan
└── index.html           # Single-file web app (to be implemented)
```

That's it — one file for the app, one for the plan.

## 7. Step-by-Step Implementation Plan

### Step 1: HTML Shell & CSS
- Create `index.html` with DOCTYPE, viewport meta, manifest link
- Write all CSS inline (or in a `<style>` block)
- Mobile-first layout: camera viewport, button bar, text preview, progress
- Dark theme support via `prefers-color-scheme`

### Step 2: Camera
- `getUserMedia('environment')` → `<video>`
- "Capture" button → draw to `<canvas>`, get blob, stop stream
- Fallback: file input for desktop/devices without camera

### Step 3: OCR Integration
- Load Tesseract.js v5 from CDN (dynamic `<script type="module">`)
- Show progress during OCR
- Extract and display raw text

### Step 4: Sentence Splitting
- `splitSentences()` utility using Intl.Segmenter + regex fallback
- Filter empty strings, trim
- Display sentences in preview with index markers

### Step 5: TTS Queue
- Sequential `SpeechSynthesisUtterance` with `onend` chain
- Play/Pause/Stop controls
- Highlight active sentence in UI
- Progress bar

### Step 6: Polish & Edge Cases
- Graceful degradation for unsupported browsers
- Error toasts (non-blocking)
- Loading spinners
- "Copy text" fallback if TTS unavailable
- `visibilitychange` handling

### Step 7: Manual Testing
- Test on iOS Safari, Android Chrome, desktop Chrome
- Test with: printed document, handwritten notes, screen with menu text, blank page
- Test offline (after first load)

## 8. Files to Create

| # | File | Purpose |
|---|---|---|
| 1 | `camera-ocr-tts/PLAN.md` | This plan |
| 2 | `camera-ocr-tts/index.html` | The complete web app |

## 9. Validation Checklist

- [ ] Camera opens on mobile (both front and back `facingMode`)
- [ ] Photo captures correctly (orientation preserved)
- [ ] Fallback file input works on desktop
- [ ] Tesseract.js loads from CDN without CORS errors
- [ ] OCR progress shown to user
- [ ] Extracted text displayed in preview
- [ ] Sentences split correctly (including edge cases: empty text, single word, no punctuation)
- [ ] TTS plays each sentence sequentially without overlap
- [ ] Pause/Stop controls work
- [ ] Active sentence highlighted in preview
- [ ] Progress bar advances correctly
- [ ] "Copy text" fallback works when TTS unavailable
- [ ] Error shown when camera permission denied
- [ ] Error shown when OCR returns empty
- [ ] `visibilitychange` pauses/resumes TTS
- [ ] Works in iOS Safari (gesture-initiated TTS, `playsinline`)
- [ ] Works in Android Chrome
- [ ] Works in desktop Chrome (via file input)
- [ ] No console errors
- [ ] Single file, no build step, no backend

## 10. Open Questions

1. **Tesseract.js language data size**: The `eng` data is ~5 MB. Should we show a "downloading language data…" step on first run? Can we pre-cache via service worker?
2. **iOS TTS voice quality**: iOS `speechSynthesis` only offers system voices (quality varies). Should we offer a voice selector dropdown?
3. **PDF / multi-page support**: Out of scope for v1, but could be a future enhancement.
4. **Language detection**: Should we auto-detect the OCR language or always default to English?
5. **Accessibility**: Should the app itself work with screen readers? (ironically meta)
6. **Orientation lock**: Should we lock to portrait mode via `screen.orientation.lock`? Currently leaning no — let the user rotate.
7. **Image preprocessing**: Should we apply contrast/brightness adjustments before OCR to improve accuracy? Tesseract.js recommends preprocessing for blurry/low-light images.
