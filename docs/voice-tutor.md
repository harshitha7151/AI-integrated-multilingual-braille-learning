# Resonant Voice Tutor

## Current behavior

- The learning header is a labelled tutor gesture area. Swipe up there to open
  the tutor; it begins listening automatically. TalkBack users can invoke the
  **Talk to Resonant** custom accessibility action, leaving normal one-finger
  TalkBack navigation untouched. Inside the tutor, swipe up on the status area
  to listen again and swipe down to stop listening or speech. Typed questions
  submit with the keyboard's send action.
- Android speech recognition is a short, user-initiated session through
  `speech_to_text`. Runtime microphone permission is requested by the native
  plugin. This can use an online device service; offline recognition is not
  promised.
- Typed questions work if permission is denied, the recognizer is missing, or
  the transcript is empty. If the API connection fails, an on-device rule-based
  tutor still explains the six-dot layout, gives hints, and verifies supported
  uncontracted English letters and words with the deterministic engine. It
  clearly declines unsupported contractions and language mappings.
- Replies use the existing Flutter TTS service and can be replayed or stopped.
  State changes are exposed as a live semantic status; partial transcripts do
  not trigger repeated announcements.
- Voice capture and tutor speech are serialized. The “Listening. Speak now.”
  prompt completes while recognition is off (`awaitSpeakCompletion(true)`);
  the UI changes to `listening` only after the recognizer starts. Each capture
  has a generation token, and only
  one final result from that token can be submitted. Finalization invalidates
  late callbacks and cancels recognition before response TTS starts. Typed
  requests, replay, interruption, clearing and disposal also invalidate any
  outstanding recognition callbacks.
- Follow-up turns and current lesson title/prompt are sent to the configured
  tutor API. Conversation turns remain in memory only and can be cleared.
  Raw audio and learner IDs/progress records are not sent or saved.
- Each Tutor turn reads a fresh, structured `TutorScreenContext` built from the
  active Flutter state. It can read the current screen, question, visible
  choices, instructions, feedback, and exercise position aloud. Screen-reading
  and action commands are dispatched locally; only the compact current-screen
  context is added to a conversational `/ask` request. No screenshot analysis
  is performed, and credentials or account identity are excluded.
- The Tutor dialog remains open after local reading and learning actions so a
  learner can continue with follow-up commands. A language change closes the
  old-language Tutor session so the next session uses the newly selected
  language and voice.
- The text tutor/backend accepts English, Hindi, and Kannada selected-content
  languages. This is not proof of conversational quality or speech support: the
  installed recognition service, mixed-language transcription, response quality,
  and TTS pronunciation still need real-device validation.
- Exact single-letter and supported alphabetic-word answers are returned
  directly from the backend's deterministic English table. Word answers
  include the authoritative dot positions, capital indicators, and ICEB
  references, without adding unsupported model claims. Uppercase runs use the
  engine's capital-word indicator. Word support is uncontracted A-Z only;
  punctuation, numbers, and contractions are refused. This is not full UEB.
  Ollama and retrieved evidence still support conceptual tutoring.
- Conceptual answers use a local, traceable retrieval corpus for six-dot
  layout, supported basic letters, the app's current English limitations, and
  language availability. The Flutter response shows the returned references.
  This corpus is not a complete UEB rulebook. The LLM prompt forbids dot
  patterns, and explicit dot-number claims are filtered to a safe explanation.

## Translation boundary

English-word-to-Hindi/Kannada translation uses a replaceable
`TranslationProvider` interface with the configured local Ollama model as its
current adapter. The provider receives only the requested word and language
pair, and returns the original text, proposed translation, and provider
metadata. Translation is a model suggestion, not an authoritative language
mapping. Before any Braille cells are returned, the backend checks the target
script and runs the deterministic Bharati forward table; unsupported output is
refused. Provider failure is returned as an explicit unavailable response.
This does not implement a general canonical-English translation pipeline for
all Hindi/Kannada tutor conversations, and the quality of word translation has
not been validated by a language expert or on-device.

## Contextual command interpretation

Known navigation and assessment commands are parsed and validated locally first. If the deterministic parser cannot resolve a non-question request, Flutter may call the backend `POST /interpret` endpoint. The endpoint asks the configured Ollama model for a bounded JSON intent candidate; it does not execute app operations or determine Braille mappings. Flutter validates that candidate against the current screen and actual lesson/action controllers before applying it. Conceptual questions continue through `/ask`. Interpreter failures remain failures and fall back to the existing local tutor/parser path; they are not reported as successful actions.

The tested command set is finite and rule-based for local parsing (English plus selected Hindi/Kannada native-script and Romanized forms). The optional Ollama interpreter may broaden phrasing when configured, but live multilingual semantic quality has not been measured and is not guaranteed.

## Contextual tool selection and speech language

Every non-empty tutor turn is offered to `POST /interpret` first when the backend is reachable. Flutter sends a bounded structured snapshot of the active screen, current options/feedback, available action identifiers, non-sensitive progress/prerequisite flags, and up to six recent turns. The backend supplies only the capabilities the screen reports as available. Its model returns a candidate from the server action schema; the client also checks that candidate against the supplied capability list and then validates it through `TutorActionController` and the active lesson/assessment state. A tutor question routes on to `/ask`; an unavailable/failed interpreter falls back to the local parser and existing tutor behavior. The local parser is an offline fallback, not the normal online route.

Speech recognition has its own locale setting. **Follow learning language** explicitly passes English India (`en-IN`), Hindi India (`hi-IN`), or Kannada India (`kn-IN`); a separate explicit override can be selected. The Android adapter checks the speech service's reported locale list and chooses an exact or same-language regional locale. If the service reports no locale for that language, listening stops with a localized message and the app does not substitute English. Android's reported list may omit online-only locales; if no inventory is available, the requested locale is still passed explicitly and the platform error is surfaced. Speech recognition returns its recognized transcript unchanged; the Flutter tutor does not translate it into English. The locale list does not guarantee recognition quality, installed language packs, mixed-language/code-switching support, or online-service availability. This has not been verified on the Samsung phone.

## Configure a phone demonstration

The backend currently uses the existing Ollama integration. On Android, the
phone's `localhost` is not the development computer. Keep the phone connected
by USB and run `adb reverse tcp:8000 tcp:8000` after starting the API; the app's
existing local API address then reaches the computer. The repository
does not contain the `openai.json` mentioned in the latest project direction,
so OpenAI is not configured or claimed as the active tutor provider. No API
credential is embedded in Flutter. Until the agreed file is present and its
schema is confirmed, tutor requests continue to use the backend's configured
provider and safe deterministic fallback.

Start Ollama and the backend on the development computer. The backend
defaults to `qwen2.5:0.5b` at `http://localhost:11434`; use
`RESONANT_OLLAMA_MODEL` and `RESONANT_OLLAMA_URL` to change those settings.
The machine reported Ollama CLI 0.40.17 during this audit, but the local server
was not reachable, so its installed model inventory, latency, and multilingual
intent quality could not be checked. The configured Qwen 2.5 0.5B model has not
been shown suitable for reliable conversational tool selection; no model was
downloaded. Keep the model replaceable through these environment variables.
Then run:

```powershell
cd resonant_backend
uvicorn main:app --host 127.0.0.1 --port 8000
```

In another terminal, run `adb reverse tcp:8000 tcp:8000`. The Android build's
cleartext network policy allows only `localhost`; use HTTPS for a different
host. Build/run the app after configuration. No API credential is embedded in
the client.

## Verification and limits

The Flutter tests cover permission-unavailable typed fallback, empty speech,
transcription submission, response speaking, replay, interruption, clearing,
HTTP payloads, and accessible labels. Backend tests cover timeout fallback,
unsupported languages, verified mapping checks, refusal for forged patterns,
and model-output filtering. These use fakes/mocks; they do not prove the
Samsung's speech recognition quality, TTS pronunciation, actual microphone
permission flow, screen-reader focus order, or live Ollama connection. Backend
retrieval evaluation uses seven fixed query cases and does not assess generated
answer quality.

The prior checkpoint detected a Samsung SM A176B and installed an earlier APK;
that checkpoint did not verify microphone use or TalkBack. The revised
landscape keyboard and swipe-led flow require installation and physical-device
verification. Automated widget tests cannot prove TalkBack gesture behavior,
actual speech recognition, vibration strength, or TTS pronunciation on the
phone.
