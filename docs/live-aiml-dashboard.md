# Live mobile to laptop AIML demonstration

The demo path uses the existing FastAPI backend as a short lived relay:

```text
Resonant on Android → paired REST event endpoint → in-memory session → authenticated WebSocket → laptop dashboard
```

It does not write demonstration events or pairing tokens to PostgreSQL. Sessions expire after 60 minutes and can be ended from the dashboard. The dashboard token and phone token are separate. Event IDs make retries idempotent; events have monotonically increasing sequence numbers and the dashboard ignores replayed sequence numbers after reconnecting. The queue and retained history are bounded.

## Start the backend and dashboard

From PowerShell:

```powershell
cd C:\Users\namit\StudioProjects\resonant_braille\resonant_backend
$env:RESONANT_JWT_SECRET = "<a long random development secret>"
uvicorn main:app --host 0.0.0.0 --port 8000
```

Open `http://localhost:8000/aiml/dashboard` on the laptop and select **Start session**. The dashboard displays a temporary session ID and pairing code. The optional transcript-sharing choice is off by default. The separate **Run simulated example (local only)** control is explicitly simulated, never enters the live event stream, and is disabled while a live session is active.

## Pair the Android app

On the phone, open **Settings → Connect to laptop AIML dashboard**. Enter the session ID and pairing code. Enter the laptop's current Wi-Fi address in **Laptop backend address**, for example `http://192.168.1.25:8000`; the address shown in the field is only a prefill and may be changed. Both devices must be on the same trusted network, and Windows Firewall must allow inbound TCP port 8000. Select **Share anonymized live activity** before connecting. Text transcripts require a second, separate consent on the dashboard and phone. Raw audio is never sent.

To stop, choose **End** on the dashboard or **Disconnect** on the phone. Ending the session clears its in-memory event state and invalidates both tokens.

## Contextual intent telemetry

When deterministic command parsing cannot resolve a non-question utterance, the app can emit `tutor_intent_interpreted` or `tutor_intent_interpretation_failed` around the backend structured interpreter call. The 3D lab identifies this as a distinct configured-Ollama intent candidate stage; the local command resolver remains a separate deterministic stage and still validates execution. These events do not imply that the experimental CLINC150 classifier ran.

## What the dashboard represents

The existing FastAPI-served dashboard now includes a Three.js component map. The pinned Three.js ES module is loaded from jsDelivr; if the CDN or WebGL is unavailable, the semantic component buttons and written concept explorer remain usable, while the 3D canvas reports that it could not start. Event highlighting is driven only by received mobile events. The explanatory map itself is not a live inference trace.

- Flutter validates every live action locally. When the configured interpreter is reachable, it proposes a structured tool for natural requests; deterministic parsing is the offline fallback.
- Braille encoding and validation are deterministic engine operations.
- Production recommendations are the rule-based baseline; the research model does not control live recommendations.
- The TF-IDF Logistic Regression, Linear SVM, and calibrated SVM are separate English CLINC150 experiments. Their predictions and nonzero TF-IDF features run through the saved Python pipelines and are clearly marked experimental. They do not control Resonant navigation.
- Live dashboard/session endpoints require no learner login because they use an isolated pairing code and session-scoped capabilities. They carry no account ID. Use only on a trusted private LAN; this development server uses HTTP and is not suitable for an untrusted network or public deployment. A production deployment needs HTTPS/WSS, deployment-level access control/rate limiting, and origin policy review.

Current verification covers backend session authorization, event validation, duplicate handling, transcript filtering, and a FastAPI mobile-to-WebSocket event round trip. It does not yet constitute a physical Android-to-laptop browser demonstration. No Samsung device or browser end-to-end run is claimed.

## Cinematic 3D scene and pre-login pairing

The FastAPI-served page uses a Three.js scene with a layered polyhedral core, orbital rings, ambient particles, curved component paths, and differentiated geometry for nine project components, including a separate contextual interpreter component. Drag rotates, the wheel zooms, component selection focuses the camera, and Overview, Reset, Fullscreen, and reduced-motion controls are available. A Braille validation event animates its reported final-cell dots only when that event contains them. The scene falls back to semantic component controls if the CDN or WebGL is unavailable.

On a fresh install, **Connect to AIML Lab** is available from the initial role screen before sign-in. It uses the same in-memory mobile client carried into learner mode; the Settings connection page remains available after login. The offline command fallback has finite deterministic coverage in English, native Hindi/Kannada script, and selected Romanized forms. Online requests use the configured Ollama structured tool interpreter first; its multilingual quality remains unverified on live model/device data. Explicit voice navigation may leave an incomplete exercise without marking it complete; completion remains governed by the existing attempt persistence path.
