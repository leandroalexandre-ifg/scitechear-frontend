# SciTech Ear — Flutter App

## Project overview

Client-side Flutter app for recording meeting audio, uploading to a backend, and displaying transcription and extracted questions. The backend (FastAPI + Whisper + pyannote + Ollama) handles all heavy processing — this app is intentionally a thin client.

**Current focus: Flutter app. Backend comes later.**

Full architecture writeup (system diagram, layer responsibilities, backend contract, open recommendations): [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md) (Portuguese).

## Architecture

```
Flutter app (this repo)
  └── Records WAV 16 kHz mono
  └── Uploads to backend via HTTP multipart
  └── Polls job status
  └── Displays transcript (with speaker labels) + extracted questions

Backend (separate repo — not implemented yet)
  └── FastAPI
  └── Whisper  → transcription
  └── pyannote → diarization (speaker identification)
  └── Ollama   → question extraction from transcript
```

## Key requirements

### Recording
- Format: **WAV, 16 kHz, mono** (required by Whisper)
- Must record in the background with the screen locked
- **Android: foreground service is mandatory** — without it, Android kills the audio thread when the screen locks
- iOS: audio session category must be set to allow background recording

### Upload & status polling
- Single HTTP multipart POST with the WAV file
- Backend returns a `job_id`; app polls `GET /jobs/{job_id}` until status is `done`
- Display intermediate states: `queued`, `transcribing`, `diarizing`, `extracting`, `done`, `error`

### Results screen
- Transcript with speaker labels (Speaker 1, Speaker 2, …)
- List of questions extracted by Ollama
- Timestamps for each segment

## Tech stack decisions

| Concern | Choice | Reason |
|---|---|---|
| Audio recording | `record` package | Supports WAV/PCM, background-capable, cross-platform |
| Foreground service (Android) | `flutter_background` + `wakelock_plus` | Keeps recording alive with the screen locked |
| HTTP client | `dio` | Multipart upload + polling |
| Real-time status | `web_socket_channel` | WebSocket first, polling fallback every 3s |
| State management | None — manual constructor injection | Simple enough at current scale; revisit (Provider/Riverpod) if it grows |
| Permissions | `permission_handler` | Microphone + notification (required for foreground service) |

## Android foreground service — critical notes

- `AndroidManifest.xml` must declare the service with `android:foreground ServiceType="microphone"`
- `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MICROPHONE` permissions are required
- A persistent notification must be shown while recording (system requirement)
- Test on a physical device or emulator with screen lock — emulator may not reproduce the kill behavior

## File structure (actual)

```
lib/
  main.dart                     # bootstrap: init auth, decide initial screen
  config.dart                   # backend HTTP/WS base URLs
  core/theme/                   # colors + dark theme
  models/
    user.dart                   # AppUser
    participant.dart            # Participant + voice sample
    meeting.dart                # Meeting (title, history)
    meeting_result.dart         # TranscriptSegment, Question, MeetingResult
  services/
    auth_service.dart           # login/signup (local mock)
    audio_service.dart          # WAV recording via `record`
    background_service.dart     # foreground service (Android) + wakelock
    upload_service.dart         # multipart upload
    status_service.dart         # WebSocket + polling + result fetch
    meeting_service.dart        # meeting history/persistence
    participant_service.dart    # participant management
    offline_service.dart        # offline demo fallback when backend unreachable
  screens/
    auth_screen.dart
    home_screen.dart
    meeting_setup_screen.dart
    participants_screen.dart
    recording_screen.dart
    processing_screen.dart
    result_screen.dart
  widgets/                      # glass card, gradient button, avatar, etc.
```

No `features/` layer, no Riverpod — see `docs/ARQUITETURA.md` §3 for why and §7 for when to revisit.

## Backend API contract (draft — backend not built yet)

Routes are in Portuguese; this is what the client actually calls (`lib/services/upload_service.dart`, `status_service.dart`) — treat the code as the source of truth over any older English draft.

```
POST /upload
  Content-Type: multipart/form-data
  Body: file=<wav>, title?, participant_names[]=, voice_samples[]=<wav>
  Response: { "job_id": "uuid" }

GET /status/{job_id}          (polling fallback)
WS   /ws/{job_id}             (real-time status)
  Response: { "status": "queued|transcribing|diarizing|extracting|done|error" }

GET /resultado/{job_id}
  Response: {
    "job_id": "uuid",
    "status": "done",
    "segments": [{ "speaker": "SPEAKER_00", "start": 0.0, "end": 4.2, "text": "..." }],
    "questions": [{ "speaker": "SPEAKER_01", "time": 12.5, "text": "..." }]
  }
```

## Development workflow

```bash
# Run on connected device (prefer physical Android for foreground service testing)
flutter run

# Analyze
flutter analyze

# Tests
flutter test
```

## What NOT to do

- Do not add desktop/web targets to the build — they are scaffolded but not a goal
- Do not process audio on device — all ML runs on the backend
- Do not store recordings permanently on device — upload and discard
- Do not add authentication for now — single-user, local network deployment
