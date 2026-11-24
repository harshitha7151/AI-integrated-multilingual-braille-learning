# Resonant Tutor intent taxonomy (experimental draft)

This taxonomy describes routing/support intent for Resonant's Tutor. It is a research annotation draft, not a production router contract. The classifier may suggest a category, but it must never determine Braille cells or override deterministic engine validation. Ambiguous or multi-intent questions should be annotated for clarification or multi-label review rather than forced into a mapping class.

| Intent | Meaning | Safe next action (proposal) |
|---|---|---|
| `mapping_request` | Requests the verified encoding of a specific character, number, or short supported text. | Deterministic language-specific Braille engine; safely decline unsupported targets. |
| `dot_pattern_explanation` | Asks what a verified cell's dots mean or how to select those dots. | Retrieve verified cell then explain its dot numbers and positions. |
| `lesson_explanation` | Asks for explanation of the current lesson or concept. | Retrieve the selected language/lesson content, then explain from that evidence. |
| `practice_hint` | Requests a hint for the active exercise without necessarily asking for the answer. | Use current exercise context; reveal only the requested hint level. |
| `mistake_explanation` | Asks why a submitted exercise was marked incorrect or how it differs. | Compare deterministic expected/submitted cells and explain the difference. |
| `navigation_help` | Asks how to move between lessons, sections, keyboard, or Tutor controls. | Give current platform/lesson instructions; do not invoke a gesture automatically. |
| `progress_help` | Asks what has been learned, what is next, or about saved progress. | Use authenticated learner progress; otherwise explain that private progress is unavailable. |
| `language_learning_question` | Asks about a language-specific script, Bharati Braille rule, vowel/consonant, sign, or combination. | Retrieve verified, language-scoped content; clarify unsupported rules. |
| `general_braille_question` | Asks a conceptual Braille question not tied to one target mapping. | Answer from relevant curated knowledge; use LLM only as an explainer. |
| `out_of_scope` | Unrelated, unsafe, or unsupported request that cannot be answered from approved content. | Briefly decline or redirect; do not fabricate an educational answer. |

Mapping and explanation can co-occur (e.g. “show A and explain why”). The production backend currently routes mapping requests deterministically and uses curated lexical evidence plus Ollama for some conceptual questions. No trained classifier is connected to that route. The taxonomy should only be revised with reviewed annotation guidelines and examples from consented, de-identified Tutor queries plus educator review.

## Initial dataset provenance

`resonant_tutor_intents_authored.csv` contains 80 short English examples, eight per category. These were authored for pipeline demonstration by the project assistant; they are **not real learner utterances**, do not represent learner diversity, and were not reviewed by Braille educators or Resonant learners. Split names are assigned per intent (five train, one validation, two test) to exercise code paths. The same author wrote all splits, so metrics only demonstrate that the code runs; they must not be presented as evidence of generalization. Do not merge these rows with CLINC150 or label them user data.
