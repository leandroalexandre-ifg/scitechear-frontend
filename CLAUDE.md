# Meeting Recorder — Flutter App

## Project overview

Client-side Flutter app for recording meeting audio, uploading to a backend, and displaying transcription and extracted questions. The backend (FastAPI + Whisper + pyannote + Ollama) handles all heavy processing — this app is intentionally a thin client.

**Current focus: Flutter app. Backend comes later.**

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
| Foreground service (Android) | `flutter_foreground_task` | Manages Android foreground service lifecycle |
| HTTP client | `dio` or `http` | Multipart upload + polling |
| State management | TBD (Riverpod preferred) | Simple enough for Provider too |
| Permissions | `permission_handler` | Microphone + notification (required for foreground service) |

## Android foreground service — critical notes

- `AndroidManifest.xml` must declare the service with `android:foreground ServiceType="microphone"`
- `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MICROPHONE` permissions are required
- A persistent notification must be shown while recording (system requirement)
- Test on a physical device or emulator with screen lock — emulator may not reproduce the kill behavior

## File structure (planned)

```
lib/
  main.dart
  app.dart                  # MaterialApp + routing
  features/
    recording/
      recording_page.dart
      recording_controller.dart
      audio_recorder_service.dart   # wraps `record` package
      foreground_service_helper.dart
    upload/
      upload_service.dart           # multipart POST + polling
    results/
      results_page.dart
      transcript_view.dart
      questions_view.dart
  models/
    job.dart                # JobStatus enum + Job model
    transcript.dart         # Segment, Speaker
  shared/
    api_client.dart         # base URL, headers, error handling
```

## Backend API contract (draft — backend not built yet)

```
POST /jobs
  Content-Type: multipart/form-data
  Body: file=<wav bytes>
  Response 202: { "job_id": "uuid" }

GET /jobs/{job_id}
  Response 200: {
    "job_id": "uuid",
    "status": "queued|transcribing|diarizing|extracting|done|error",
    "transcript": [{ "speaker": "Speaker 1", "start": 0.0, "end": 3.2, "text": "..." }],
    "questions": ["...", "..."],
    "error": null
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
