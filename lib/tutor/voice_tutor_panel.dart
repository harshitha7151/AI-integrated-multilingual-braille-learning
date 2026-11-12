import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'speech_to_text_recognizer.dart';
import 'http_tutor_gateway.dart';
import 'local_braille_tutor.dart';
import 'voice_tutor_controller.dart';

class FlutterTtsSpeechOutput implements TutorSpeechOutput {
  FlutterTtsSpeechOutput(this.tts, {this.enabled = true});
  final FlutterTts tts;
  final bool enabled;
  @override
  Future<void> speak(String text) async {
    if (!enabled) return;
    await tts.stop();
    await tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await tts.stop();
  }
}

class VoiceTutorPanel extends StatefulWidget {
  const VoiceTutorPanel({
    super.key,
    required this.controller,
    this.hapticsEnabled = false,
    this.startListeningOnOpen = false,
  });
  final VoiceTutorController controller;
  final bool hapticsEnabled;
  final bool startListeningOnOpen;

  @override
  State<VoiceTutorPanel> createState() => _VoiceTutorPanelState();
}

class _VoiceTutorPanelState extends State<VoiceTutorPanel> {
  final TextEditingController _input = TextEditingController();
  VoiceTutorState _lastState = VoiceTutorState.idle;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
    if (widget.startListeningOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.startListening();
      });
    }
  }

  void _controllerChanged() {
    final state = widget.controller.state;
    if (widget.hapticsEnabled && state != _lastState) {
      switch (state) {
        case VoiceTutorState.listening:
          HapticFeedback.selectionClick();
        case VoiceTutorState.thinking:
          if (_lastState == VoiceTutorState.listening) {
            HapticFeedback.lightImpact();
          }
        case VoiceTutorState.speaking:
          HapticFeedback.mediumImpact();
        case VoiceTutorState.error:
          HapticFeedback.vibrate();
        case VoiceTutorState.idle:
          break;
      }
    }
    _lastState = state;
    final transcript = widget.controller.transcript;
    if (_input.text != transcript && transcript.isNotEmpty) {
      _input.value = TextEditingValue(
        text: transcript,
        selection: TextSelection.collapsed(offset: transcript.length),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _input.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final thinking = controller.state == VoiceTutorState.thinking;
    final listening = controller.state == VoiceTutorState.listening;
    final speaking = controller.state == VoiceTutorState.speaking;
    final compact = MediaQuery.sizeOf(context).height < 500;
    // With the on-screen keyboard open there is little room: drop secondary text.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Dialog(
      insetPadding: EdgeInsets.all(keyboardOpen ? 4 : (compact ? 10 : 20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: compact ? MediaQuery.sizeOf(context).height * 0.94 : 620,
        ),
        child: Padding(
          padding: EdgeInsets.all(keyboardOpen ? 6 : (compact ? 12 : 20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Talk to Resonant',
                style: TextStyle(
                  fontSize: keyboardOpen ? 16 : (compact ? 20 : 24),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: keyboardOpen ? 0 : 4),
              Semantics(
                container: true,
                liveRegion: true,
                label: controller.statusText,
                customSemanticsActions: {
                  if (listening)
                    CustomSemanticsAction(label: 'Stop listening'):
                        controller.stopListening,
                  if (speaking)
                    CustomSemanticsAction(label: 'Stop speaking'):
                        controller.stopSpeaking,
                  if (!listening && !thinking)
                    CustomSemanticsAction(label: 'Listen again'):
                        controller.startListening,
                },
                child: GestureDetector(
                  key: const ValueKey('tutor-state-gesture'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -250 &&
                        !listening &&
                        !thinking) {
                      controller.startListening();
                    }
                    if ((details.primaryVelocity ?? 0) > 250 && listening) {
                      controller.stopListening();
                    }
                    if ((details.primaryVelocity ?? 0) > 250 && speaking) {
                      controller.stopSpeaking();
                    }
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: keyboardOpen ? 4 : 12,
                    ),
                    child: Text(
                      '${controller.statusText} ${listening || speaking ? 'Swipe down to stop.' : 'Swipe up to listen again.'}',
                      key: const ValueKey('tutor-state'),
                    ),
                  ),
                ),
              ),
              if (!keyboardOpen) ...[
                SizedBox(height: compact ? 2 : 8),
                Text(
                  compact
                      ? 'English tutor. Hindi and Kannada voice are not yet verified.'
                      : 'English voice tutor is enabled. Hindi and Kannada voice support is not yet verified.',
                  style: compact ? const TextStyle(fontSize: 12) : null,
                ),
              ],
              if (!compact && !keyboardOpen) ...[
                const SizedBox(height: 6),
                const Text(
                  'Speech recognition may use your phone’s online service. Raw audio and this conversation are not saved.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
              SizedBox(height: compact ? 4 : 10),
              Expanded(
                child: Semantics(
                  label: 'Tutor conversation',
                  child: ListView(
                    key: const ValueKey('tutor-conversation'),
                    children: [
                      for (final message in controller.messages)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Semantics(
                            container: true,
                            label: message.role == 'user'
                                ? 'You said: ${message.text}'
                                : 'Resonant replied: ${message.text}',
                            child: ExcludeSemantics(
                              child: Text(
                                '${message.role == 'user' ? 'You' : 'Resonant'}: ${message.text}',
                              ),
                            ),
                          ),
                        ),
                      for (final example in controller.verifiedExamples)
                        Semantics(
                          container: true,
                          label:
                              'Verified Braille example for ${example.text}: ${example.spoken}',
                          child: ExcludeSemantics(
                            child: Text(
                              'Verified engine example: ${example.text} — ${example.spoken}',
                            ),
                          ),
                        ),
                      for (final example in controller.letterExamples)
                        Semantics(
                          container: true,
                          label:
                              'Verified letter cell ${example.spoken}. Capitalization: ${example.capitalization}.',
                          child: ExcludeSemantics(
                            child: Text(
                              'Verified letter: ${example.spoken} (${example.capitalization})',
                            ),
                          ),
                        ),
                      for (final source in controller.sources)
                        Semantics(
                          container: true,
                          label:
                              'Tutor reference: ${source.title}. ${source.url}',
                          child: ExcludeSemantics(
                            child: Text(
                              'Reference: ${source.title} (${source.url})',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Semantics(
                customSemanticsActions: {
                  CustomSemanticsAction(label: 'Send typed question'): () =>
                      controller.send(_input.text),
                },
                child: TextField(
                  key: const ValueKey('tutor-typed-question'),
                  controller: _input,
                  minLines: 1,
                  maxLines: keyboardOpen ? 1 : (compact ? 2 : 3),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) => controller.send(value),
                  decoration: InputDecoration(
                    labelText: compact
                        ? 'Type a question'
                        : 'Type a question, then press the keyboard send key',
                    hintText:
                        'Ask about Braille, your lesson, or a verified example',
                    isDense: keyboardOpen,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(height: keyboardOpen ? 4 : 10),
              if (controller.reply.isNotEmpty && !keyboardOpen)
                Semantics(
                  label: 'Tutor reply. ${controller.reply}',
                  customSemanticsActions: {
                    CustomSemanticsAction(label: 'Replay tutor reply'):
                        controller.replay,
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (details) {
                      if ((details.primaryVelocity ?? 0) < -250) {
                        controller.replay();
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Swipe up on the tutor reply to hear it again.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

VoiceTutorController createVoiceTutorController({
  required FlutterTts tts,
  required SpeechToTextRecognizer speech,
  required String lessonContext,
  List<VerifiedBrailleExample> lessonExamples = const [],
  bool audioEnabled = true,
  Future<String?> Function(String question)? localCommandHandler,
  Future<void> Function()? onLocalCommandComplete,
  Future<void> Function(String message)? onStatusAnnouncement,
}) => VoiceTutorController(
  speech: speech,
  gateway: HttpTutorGateway(),
  output: FlutterTtsSpeechOutput(tts, enabled: audioEnabled),
  lessonContext: lessonContext,
  lessonExamples: lessonExamples,
  localCommandHandler: localCommandHandler,
  offlineTutorHandler: (question, history, context, examples) =>
      LocalBrailleTutor.answer(
        question: question,
        history: history,
        lessonContext: context,
        lessonExamples: examples,
      ),
  onLocalCommandComplete: onLocalCommandComplete,
  onStatusAnnouncement: onStatusAnnouncement,
);
