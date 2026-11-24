# Resonant 2.0 implementation status

The consolidated current checkpoint is
[resonant-ecosystem-progress.md](resonant-ecosystem-progress.md). The table
below retains detailed earlier UI/device observations; “tested” refers only to
automated checks and does not imply user or device validation.

| Area | Status | Evidence / remaining work |
|---|---|---|
| Six-dot screen mapping | Implemented and automated-tested | App is locked to landscape. Per the latest reference, screen-left is dots 4, 5, 6 top-to-bottom and screen-right is dots 1, 2, 3. The pad is fixed in the available practice area without scroll containers, in touch and screen-reader modes. Physical dot targeting remains unverified. |
| Multi-touch chord collection | Partially implemented | Simultaneous pointers tested. Calibration, sensitivity, and full hand-position setup remain. |
| Drag and cancellation recovery | Implemented and automated-tested | Drag/cancel clears the active chord rather than committing it. |
| Accessible dot entry | Implemented and automated-tested; device verification partial | Six-dot semantic controls announce current selection, expose selected state, support deselection and speak deterministic single-cell decoding. TalkBack use has not been tested on Android. |
| Voice tutor and commands | Implemented; online route and offline fallback tested | Swipe up in the labelled header area to launch the tutor; TalkBack has Talk and Replay Welcome actions. USB `adb reverse` connects the phone to the local API. Verified English words, letters, layout questions and hints fall back to the deterministic local engine when the API is unreachable. General conversation still depends on the configured Ollama model. Compact landscape dialog is widget-tested. Phone microphone/TTS/TalkBack remain unverified. |
| Lesson 1 / onboarding | Implemented and automated-tested; welcome replays once after this upgrade | Ten spoken, persisted steps cover lesson flow and keyboard use. This build advances the onboarding version so existing installs see Welcome Step 1 once; saved lesson attempts remain intact. Swipe navigation works across the welcome content and letter lesson. Finishing Welcome resumes the first unfinished curriculum item. Physical TalkBack remains unverified. |
| English curriculum | Implemented as data and automated-tested; device journey partial | A–E through U–Z stages, five word lessons, verified phrases, and complete-sentence six-dot writing are ordered and prerequisite-gated. A personalized `My name is ...` sentence is widget-tested cell by cell. Later groups and writing chapters have not been played end-to-end on device. |
| Chapter 3 word learning | Implemented and automated-tested; full device journey unverified | Five ordered lessons cover CAT/BAT/MAT, SUN/DOG/HAT/PEN, keyboard writing, blind-first read-and-identify, and a five-word test requiring 4/5 first-try success. Attempts, hints, response times and mastery-round IDs use the existing offline store. A CAT write/correction/backspace test validates cells and records progress. The complete unlock journey has not been played on device. |
| Primary navigation / dashboard | Simplified; gesture flow automated-tested, device accessibility unverified | Returning learners first receive the revised Lesson 1, then resume their first unfinished course item. The large dashboard list, repeated global navigation row, and visible tutor button are removed. Swipe up in the labelled header area to open the tutor and start listening; TalkBack custom action is provided. App orientation is locked to landscape. Physical TalkBack and phone rotation remain unverified. |
| Responsive keyboard / visual design | Layout fixes implemented; widget-tested and visually checked on Samsung | Large white circular targets with blue dot numbers match the screenshot order: left 4/5/6, right 1/2/3. The pad fills the practice area without scrolling; status and actions use a compact footer. A clean landscape keyboard screenshot was captured from the Samsung. Enlarged-text/narrow-screen tests pass. Physical vibration feel and TalkBack use remain to be checked. |
| English Braille | Partially implemented | Uncontracted alphabet, digits, indicators, spaces, and selected punctuation only; not full UEB. |
| Hindi and Kannada Braille | Partially implemented and UI-connected for the validated subset | Separate forward Grade 1 tables with NIEPVD 2025 fixtures now drive language-specific character lessons, word assessments, authored phrase/sentence writing, resume state, and accessible navigation. Unsupported personalized names fall back to verified script content. Direct comparison with 2.1, full sign coverage, reverse translation, matra/conjunct and gunithakshara/ottakshara expansion remain. |
| Lesson progress and resume | Implemented locally and automated-tested; server assessment sync added | Letter and word events, assessment sessions, and pending adaptive decisions persist offline. App relaunch resumes per language, and authenticated assessment/decision lifecycle records reconcile with the backend. Full cross-device conflict handling remains unverified. |
| FastAPI/PostgreSQL persistence | Implemented and unit-tested; live database unverified | Versioned isolated schema, learner/teacher/account/progress/assessment/adaptive routes, deterministic services, and authorization checks pass the backend suite. Migrations `005` through `007`, real transactions, and end-to-end PostgreSQL authorization remain unverified. |
| AI tutor provider | Existing Ollama integration; OpenAI configuration blocked | The repository has no `openai.json`; current backend still uses Ollama and its verified retrieval/encoding flow. Do not describe OpenAI as configured until the agreed config file is available and its schema/provider behavior are verified. |
| Tutor Braille word answers | Implemented and backend/gateway-tested | Ollama supplies the teaching sentence; the backend supplies authoritative uncontracted A–Z word cells, per-letter dot positions, capital indicators and ICEB references. Timeout fallback retains the verified answer. Contractions, punctuation and numbers remain unsupported; this is not full UEB. |
| Adaptive recommendations | Hybrid interface implemented and automated-tested; currently deterministic cold-start | Assessments build point-in-time history features, persist prediction/question provenance, and can accept advice only from a qualified consented-data Resonant artifact. Flutter briefly prefers a synchronized backend decision, revalidates every question against curriculum and Braille mappings, caps duplicate remediation, enforces prerequisites, and keeps the durable offline decision. A separate explainable local rule ranks only eligible verified words from errors/attempts/hints. No qualified artifact exists, so current learner behavior remains explicit deterministic fallback. |
| Resonant next-attempt ML | Integration and qualification pipeline implemented; no production model | The task, exact feature schema, trusted loader, learner-grouped chronological runner, sample/learner/calibration/language gates, authorization-gated HMAC exporter, and human-review requirement are present. No authorized learner export was supplied, no model was trained/promoted, and no real Resonant performance is claimed. |
| Public educational ML experiment | Implemented, trained, and held-out evaluated | The corrected ASSISTments 2009-2010 experiment uses 346,860 genuine historical mathematics interactions, point-in-time features, and 844 held-out learner identities. Random Forest accuracy/macro F1/ROC-AUC are 0.6935/0.6753/0.7529. The optional API returns no learning action and is not a Braille or Resonant mastery model. |
| Offline synchronization | Implemented for current practice/assessment scope; live reconnect unverified | Offline event and adaptive-decision logs use unique submission IDs, backend reconciliation, lifecycle retry, and duplicate suppression. Real-device reconnect/conflict behavior still needs integration testing. |
| Teacher mode | Implemented in code and automated-tested; browser/live DB unverified | Teacher auth, scoped dashboard/detail queries, assessment decisions, remediation outcomes, mastery changes, model/fallback provenance, and adaptive-question provenance are present. Browser rendering and end-to-end PostgreSQL authorization remain unverified. |
| Android build | Implemented, built and installed | Latest debug APK built and installed on Samsung SM A176B. It launched successfully in landscape and showed Lesson 1, letter A. |
| Samsung device / TalkBack | Partially verified | Latest build launch and clean keyboard layout were captured on device. Physical dot entry accuracy, word chapter journey, TalkBack, speech and haptic behavior still need device testing. |

## Automated checks run

- Direct Flutter SDK `analyze --no-pub` — passed with no issues.
- Direct Flutter SDK serial test run — passed (143 tests).
- `python -m pytest resonant_backend/tests -q` — passed (129 tests plus 39
  subtests) with an ephemeral test-only JWT secret.
- `python -m pytest aiml/tests -q` — passed (42 tests).
- Pytest plugin autoload was disabled to isolate project tests from unrelated
  user-site plugins. Production still requires a real `RESONANT_JWT_SECRET`.
- APK/browser/live-device builds were not rerun in the adaptive checkpoint.
- ML demo training — ran with seed `20261101`; metrics are synthetic-only and
  documented in [ml-synthetic-demo.json](ml-synthetic-demo.json).
- Public ASSISTments experiment — ran with seed `20261122`; genuine measured
  outputs and limitations are under
  `../aiml/reports/assistments_2009_2010/`. The ignored trained artifact is
  reproducible from the verified ignored raw CSV.

## Important references and limitations

- English engine scope and official Bharati reference findings:
  [braille-standards.md](braille-standards.md).
- Deterministic adaptation, synthetic-demo limits, and the isolated public-data
  outcome experiment:
  [adaptive-learning.md](adaptive-learning.md).
- Governed production integration, qualification requirements, question
  validation, and current cold-start limitation:
  [resonant-ml-integration-audit.md](resonant-ml-integration-audit.md).
- The tutor retrieval corpus is deliberately small and only supports verified
  English single letters, six-dot layout, project capability scope, and the
  current language limitations. It is not a searchable or complete UEB text.
- The ordered stages, word banks, mastery rule, and resume behavior are in
  [curriculum.md](curriculum.md).
- Database schema and real learner records remain uninspected because no
  `RESONANT_DATABASE_URL` is configured in this environment. The new migration
  uses a separate `resonant` schema to preserve any existing default-schema
  tables; see [database-and-api.md](database-and-api.md). Learner routes still
  need authentication before deployment.

