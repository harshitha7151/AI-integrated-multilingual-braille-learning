# Multilingual intent experiment plan

## Decision and current status

There is no local, reviewed Resonant intent dataset in Hindi or Kannada. The existing authored Tutor set is English-only and assistant-authored. CLINC150 is English-only and domain-mismatched. A reproducible multilingual training run is therefore **not justified yet**; translating CLINC test rows or creating translated synthetic rows would not be independent evaluation data. No model or corpus was downloaded for this phase.

## External benchmark candidate

Amazon MASSIVE is the strongest screened candidate for pipeline feasibility: the authors describe a multilingual NLU corpus with aligned train/validation/test annotations and Hindi (`hi-IN`) and Kannada (`kn-IN`) locales, under CC BY 4.0 according to the official repository notice. Its examples localize general assistant utterances and include intent and slot tasks, not Braille tutoring. Results would be an external method benchmark only. Review the exact revision, source files, license notice and language-specific counts before acquisition. Sources: [Amazon Science dataset page](https://www.amazon.science/code-and-datasets/massive), [official MASSIVE repository](https://github.com/alexa/massive), [official dataset card](https://huggingface.co/datasets/AmazonScience/massive).

## Planned comparisons once acquisition is approved

1. Preserve official per-locale splits; report English, Hindi and Kannada separately before pooling.
2. Establish language-specific word TF-IDF + Logistic Regression and character TF-IDF + Logistic Regression. Character n-grams can capture script fragments and spelling variation without word tokenization, but are not a language-understanding guarantee.
3. Compare a pooled multilingual character model against separate per-language models only where labels are aligned and every locale has enough examples. Keep locale as an explicit feature or report the effect of omitting it.
4. Consider multilingual sentence embeddings only after selecting a documented model, runtime, license, local resource cost and evaluation protocol. Compare against these low-cost baselines on the same official split.
5. Report macro F1, per-class precision/recall, confusion patterns, language-specific coverage and calibrated uncertainty. Do not tune on test results.
6. Keep Resonant-specific intents and learner wording separate. Build those with consented data, bilingual annotation guidance, educator and blind/low-vision community review, mixed-script handling, and an explicit ambiguous/multi-intent label.

## Indic-script feature caution

The English benchmark vectorizer uses Unicode accent stripping. Do not reuse that setting for Devanagari or Kannada: combining marks can carry meaningful vowel/sign information. An Indic experiment should preserve original Unicode normalization consistently (for example NFC), use script-preserving character n-grams, and add tests confirming dependent signs remain in the normalized text. No accuracy claim should be made from synthetic smoke fixtures.

## Readiness gate

Before a multilingual result: approve the source license and data revision; record acquisition checksum; audit class/language counts and text normalization; keep official splits; test label alignment; document locale-specific errors; and clearly state that generic assistant-language results do not validate Braille instruction quality.
