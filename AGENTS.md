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
- Display intermediate states: `queued`, `transcribing`, `diarizing`, `identifying`, `summarizing`, `extracting`, `done`, `error`

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
    api_client.dart             # JWT session, token refresh, authenticated Dio clients
    auth_service.dart           # login/signup against the backend `/auth`
    tls.dart                    # SecurityContext with the bundled internal CA
    local_scope.dart            # per-user prefixes for on-device storage
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

## Backend API contract

Implemented and tested on the backend (SciTech-backend, separate repo). This
is what the client actually calls (`lib/services/upload_service.dart`,
`status_service.dart`, `participant_service.dart`) — treat the code as the
source of truth over this doc if they ever drift.

```
POST /upload
  Content-Type: multipart/form-data
  Body: file=<wav 16kHz mono>, title?, participants=<JSON string, e.g. [{"id":"p1","name":"Leandro"}]>,
        expected_speaker_count?=<int>
  Response: 202 { "job_id": "uuid", "status": "queued" }

GET /status/{job_id}          (polling fallback — mandatory, see below)
  Response: { "job_id", "status", "progress"?, "error"?: {"code","message"}, "updated_at" }

WS   /ws/{job_id}             (real-time status)
  Today this is just a STUB: accepts the connection, sends the current
  status ONCE, then closes. Real push (backend Fase 8) isn't implemented
  yet — polling must keep working standalone, not as a secondary path.

GET /resultado/{job_id}
  200 with the canonical result below when status == "done"; 409 if not
  done yet or done-with-error; 404 if the job doesn't exist.
  Response: {
    "job_id": "uuid",
    "status": "done",
    "segments": [{
      "id": "seg_0001", "cluster": "SPEAKER_00", "participant_id": "p1" | null,
      "speaker": "Leandro" | null, "identified": true, "confidence": 0.82 | null,
      "start": 0.0, "end": 4.2, "text": "..."
    }],
    "questions": [{
      "id": "P1", "type": "explicit" | "implicit", "text": "...",
      "participant_id": "p1" | null, "speaker": "Leandro" | null, "time": 12.5 | null,
      "source_segment_ids": ["seg_0004"]
    }],
    "metadata": {"whisperx_model", "diarization_model", "voice_model", "llm_model", "generated_at", "stub"}
  }

POST /participants/{id}/voice-samples
  Content-Type: multipart/form-data
  Body: file=<wav>, name?
  Response: 200 { "participant_id", "sample_count", "model_version", "updated_at" }

GET /participants/{id}/voice-profile
  Response: 200 { "participant_id", "exists", "sample_count", "model_version", "updated_at" }
  (always 200, even if it doesn't exist — check "exists")

DELETE /participants/{id}/voice-profile
  Response: 204
```

Job states (exact strings, 8 total):
`queued`, `transcribing`, `diarizing`, `identifying`, `summarizing`, `extracting`, `done`, `error`.

Rules that matter for the client:
- `confidence` is always populated with the best score, even when
  `identified: false` (rejected by threshold/margin) — it is NOT itself a
  signal of identification, only the `identified` field is. Never infer
  identification from the presence of `confidence`.
- Implicit questions (`type: "implicit"`) always have `participant_id`,
  `speaker`, and `time` set to `null` — never invented client-side.
- The client never maps `cluster` (e.g. `SPEAKER_00`) to a participant by
  list position — only the backend-resolved `speaker`/`participant_id` are
  trusted identity.
- A real `error` status (or an unreachable backend) must surface as a real
  error in the UI — never silently replaced with a fabricated/demo result.
  The one exception is the explicit `SCITECH_DEMO_MODE` build flag (see
  `lib/services/offline_service.dart`), used only for offline demos.
- Voice samples are synced to the backend once, at participant
  registration/update (`ParticipantService.syncVoiceSample`) — never
  re-sent on every meeting upload.

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
- Do not turn a real backend error (or unreachable backend) into a fabricated/demo result — surface the real error to the user; the offline/demo fallback only activates behind an explicit build/demo flag, never automatically
