# Pilot Deployment Guide: Resonant Braille

This guide outlines how to deploy and configure the backend service on a host, manage environment variables, execute database migrations, seed demo data, and compile the Flutter Android APK for a live pilot.

---

## 1. Backend Server Setup

### Requirements
- Python 3.11+
- PostgreSQL 14+
- Ollama (optional, if AI conversational tutor features are enabled)

### Environment Configuration
1. In `resonant_backend/`, copy the example file:
   ```bash
   cp .env.example .env
   ```
2. Configure the required environment variables in `.env` (or pass them via your systemd service, container, or cloud host):
   ```ini
   ENV=production
   RESONANT_DATABASE_URL=postgresql://db_user:strong_password@localhost:5432/resonant_prod
   RESONANT_JWT_SECRET=generate-a-random-secret-key-at-least-32-characters-long
   RESONANT_ALLOWED_ORIGINS=https://teacher.example.com,http://localhost:8000
   RESONANT_OLLAMA_URL=http://localhost:11434
   RESONANT_OLLAMA_MODEL=qwen2.5:0.5b
   RESONANT_AI_ENABLED=true
   ```
   > **Note:** `RESONANT_JWT_SECRET` is required; the backend will fail to start if it is missing or empty.

### Dependencies & Database Migrations
1. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```
2. Run database migrations to initialize tables and indexes:
   ```bash
   python migrate.py
   ```

### (Optional) Demo Data Seeding
For pilot demonstrations or rehearsal, you can populate 1 demo teacher and 6 learners with varied progress profiles (active, inactive, struggling):
```bash
python seed_demo_data.py
```
> **Safety Guard:** `seed_demo_data.py` will refuse to run if `ENV=production`.

### Start Backend Service
Run via Uvicorn (or behind Gunicorn/Nginx reverse proxy):
```bash
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```
Verify availability by checking:
```bash
curl http://localhost:8000/health
```

---

## 2. Flutter Client Build (Android APK)

The Flutter app uses one shared backend origin for learner, teacher, tutor,
progress, and live AIML clients. Set the build-time default with
`--dart-define=API_BASE_URL`; the optional pre-login AIML connection screen can
also update that origin for the current app session, and the change applies to
already-created default clients as well. Explicit per-client URI overrides are
reserved for tests and specialized embedding.

### Debug Run
```bash
flutter run -d <device-id> --dart-define=API_BASE_URL=https://api.yourdomain.com
```

### Production Release APK Build
Build a release APK pointed at your production host:
```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.yourdomain.com
```
The output APK will be placed at:
```
build/app/outputs/flutter-apk/app-release.apk
```

### Network Failure & Unreachable Host Handling
If the client cannot reach the backend server (e.g., pilot tablets with spotty Wi-Fi):
- Learner practice attempts are safely queued locally in durable offline JSON storage (`lesson-progress.json`) and automatically uploaded once connectivity is restored.
- On registration, account restore, or login errors, the app displays a clear visual banner and announces the failure audibly via TTS.

