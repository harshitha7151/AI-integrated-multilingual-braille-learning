import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tutor_screen_context.dart';

enum VoiceTutorState {
  idle,
  preparingListening,
  listening,
  thinking,
  speaking,
  error,
}

class TutorMessage {
  final String role;
  final String text;
  const TutorMessage(this.role, this.text);
}

class VerifiedBrailleExample {
  final String text;
  final List<int> cells;
  const VerifiedBrailleExample(this.text, this.cells);

  String get spoken => '$text: ${cells.map(_dotsForCell).join(', then ')}';

  static String _dotsForCell(int cell) {
    if (cell == 0) return 'blank cell';
    final dots = [
      for (var bit = 0; bit < 6; bit++)
        if ((cell & (1 << bit)) != 0) '${bit + 1}',
    ];
    return 'dots ${dots.join(', ')}';
  }
}

class TutorLetterExample {
  final String letter;
  final List<int> cells;
  final List<int> dots;
  final String capitalization;
  const TutorLetterExample({
    required this.letter,
    required this.cells,
    required this.dots,
    required this.capitalization,
  });

  String get spoken {
    const positions = {
      1: 'top-left',
      2: 'middle-left',
      3: 'bottom-left',
      4: 'top-right',
      5: 'middle-right',
      6: 'bottom-right',
    };
    final pattern = dots.isEmpty
        ? 'blank cell'
        : dots.map((dot) => 'dot $dot at ${positions[dot]}').join(' and ');
    return '$letter: $pattern';
  }
}

class TutorResponse {
  final String answer;
  final String source;
  final List<VerifiedBrailleExample> verifiedExamples;
  final List<TutorLetterExample> letterExamples;
  final List<TutorSource> sources;
  const TutorResponse(
    this.answer, {
    this.source = 'ollama',
    this.verifiedExamples = const [],
    this.letterExamples = const [],
    this.sources = const [],
  });
}

class TutorSource {
  final String title;
  final String url;
  const TutorSource({required this.title, required this.url});
}

abstract interface class SpeechRecognizer {
  Future<bool> initialize(ValueChanged<String> onError);
  Future<void> listen({
    required String locale,
    required Duration listenTimeout,
    required void Function(String, bool) onResult,
  });
  Future<void> stop();
  Future<void> cancel();
}

/// Optional capability implemented by speech adapters that can report the
/// locales exposed by the device recognition service.
abstract interface class SpeechRecognitionLocaleResolver {
  Future<String?> resolveAvailableLocale(String requestedLocale);
}

abstract interface class TutorGateway {
  Future<TutorResponse> ask({
    required String question,
    required String language,
    required List<TutorMessage> history,
    required String lessonContext,
    required List<VerifiedBrailleExample> verifiedExamples,
  });
}

abstract interface class TutorSpeechOutput {
  Future<void> speak(String text);
  Future<void> stop();
}

class VoiceTutorController extends ChangeNotifier {
  VoiceTutorController({
    required SpeechRecognizer speech,
    required TutorGateway gateway,
    required TutorSpeechOutput output,
    required this.lessonContext,
    this.language = 'English',
    this.lessonExamples = const [],
    this.locale = 'en-US',
    this.requestTimeout = const Duration(seconds: 26),
    this.listenTimeout = const Duration(seconds: 45),
    this.localCommandHandler,
    this.contextualCommandHandler,
    this.offlineTutorHandler,
    this.onLocalCommandComplete,
    this.onStatusAnnouncement,
    this.screenContextProvider,
    this.onDemoEvent,
  }) : _speech = speech,
       _gateway = gateway,
       _output = output;

  final SpeechRecognizer _speech;
  final TutorGateway _gateway;
  final TutorSpeechOutput _output;
  final String lessonContext;
  final String language;
  final List<VerifiedBrailleExample> lessonExamples;
  final String locale;
  final Duration requestTimeout;
  final Duration listenTimeout;
  final Future<String?> Function(String question)? localCommandHandler;
  final Future<String?> Function(
    String question,
    List<TutorMessage> recentTurns,
  )?
  contextualCommandHandler;
  final FutureOr<TutorResponse?> Function(
    String question,
    List<TutorMessage> history,
    String lessonContext,
    List<VerifiedBrailleExample> lessonExamples,
  )?
  offlineTutorHandler;
  final Future<void> Function()? onLocalCommandComplete;
  final Future<void> Function(String message)? onStatusAnnouncement;
  final TutorScreenContextProvider? screenContextProvider;
  final void Function(String type, Map<String, Object?> payload)? onDemoEvent;
  VoiceTutorState state = VoiceTutorState.idle;
  String transcript = '';
  String reply = '';
  String? errorMessage;
  List<VerifiedBrailleExample> verifiedExamples = const [];
  List<TutorLetterExample> letterExamples = const [];
  List<TutorSource> sources = const [];
  final List<TutorMessage> messages = [];
  bool _busy = false;
  bool _disposed = false;
  bool _acceptSpeechCallbacks = false;
  bool _finalSpeechReceived = false;
  int _speechGeneration = 0;
  int _requestGeneration = 0;

  /// True only after the recognizer has been started and callbacks are valid.
  bool get isListening =>
      state == VoiceTutorState.listening && _acceptSpeechCallbacks;

  void _emitDemo(String type, [Map<String, Object?> payload = const {}]) {
    try {
      onDemoEvent?.call(type, payload);
    } catch (_) {
      // Demo telemetry never blocks lesson or tutor functionality.
    }
  }

  String get statusText => switch (state) {
    VoiceTutorState.idle =>
      'Ready. Swipe up in the tutor area to speak, or type a question.',
    VoiceTutorState.preparingListening => 'Preparing voice input.',
    VoiceTutorState.listening => 'Listening. Speak now.',
    VoiceTutorState.thinking => 'Resonant is thinking.',
    VoiceTutorState.speaking => 'Resonant is speaking.',
    VoiceTutorState.error =>
      errorMessage ?? 'Voice input is unavailable. You can type instead.',
  };

  Future<void> startListening() async {
    if (_disposed ||
        _busy ||
        state == VoiceTutorState.listening ||
        state == VoiceTutorState.preparingListening ||
        state == VoiceTutorState.speaking) {
      return;
    }
    _busy = true;
    errorMessage = null;
    transcript = '';
    _finalSpeechReceived = false;
    _acceptSpeechCallbacks = false;
    final session = ++_speechGeneration;
    state = VoiceTutorState.preparingListening;
    notifyListeners();
    try {
      final available = await _speech.initialize((message) {
        if (_disposed || session != _speechGeneration) return;
        _speechGeneration++;
        _acceptSpeechCallbacks = false;
        unawaited(_speech.cancel());
        _setError(_speechErrorMessage(message));
      });
      if (_disposed || session != _speechGeneration) return;
      if (!available) {
        _setError(
          'Microphone permission or speech recognition is unavailable. Type your question instead.',
        );
        return;
      }
      var recognitionLocale = locale;
      if (recognitionLocale != 'system' &&
          _speech is SpeechRecognitionLocaleResolver) {
        final availableLocale =
            await (_speech as SpeechRecognitionLocaleResolver)
                .resolveAvailableLocale(recognitionLocale);
        if (_disposed || session != _speechGeneration) return;
        if (availableLocale == null) {
          _setError(_localeUnavailableMessage());
          return;
        }
        recognitionLocale = availableLocale;
      }
      // Speak only after the requested locale is confirmed. The microphone
      // remains off until this prompt completes.
      await _announceStatus('Listening. Speak now.');
      if (_disposed || session != _speechGeneration) return;
      await _speech.listen(
        locale: recognitionLocale,
        listenTimeout: listenTimeout,
        onResult: (text, isFinal) {
          if (_disposed ||
              session != _speechGeneration ||
              !_acceptSpeechCallbacks ||
              _finalSpeechReceived ||
              state != VoiceTutorState.listening) {
            return;
          }
          transcript = text;
          if (isFinal) {
            _finalSpeechReceived = true;
            _acceptSpeechCallbacks = false;
            if (text.trim().isEmpty) {
              _setError(
                'No speech was recognized. Please try again or type your question.',
              );
            } else {
              // Invalidate this recognizer session before processing or TTS.
              _speechGeneration++;
              state = VoiceTutorState.thinking;
              notifyListeners();
              unawaited(_speech.stop());
              _emitDemo('speech_recognition_completed', {
                'language': language,
                'transcript': text,
              });
              unawaited(send(text, inputMethod: 'speech'));
            }
          }
          notifyListeners();
        },
      );
      if (_disposed || session != _speechGeneration) return;
      _acceptSpeechCallbacks = true;
      state = VoiceTutorState.listening;
      notifyListeners();
      _emitDemo('speech_recognition_started', {'language': language});
    } catch (_) {
      _acceptSpeechCallbacks = false;
      _setError(
        'Speech input could not start in ${_languageName()} for this device. Check its speech service settings or type your question instead.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> stopListening() async {
    if (state != VoiceTutorState.listening) return;
    final finalText = transcript.trim();
    _acceptSpeechCallbacks = false;
    _speechGeneration++;
    state = VoiceTutorState.thinking;
    notifyListeners();
    try {
      await _speech.stop();
      if (finalText.isEmpty) {
        _setError(
          'No speech was recognized. Please try again or type your question.',
        );
      } else {
        _emitDemo('speech_recognition_completed', {
          'language': language,
          'transcript': finalText,
        });
        await send(finalText, inputMethod: 'speech');
      }
    } catch (_) {
      _setError(
        'Speech recognition stopped unexpectedly. Type your question instead.',
      );
    }
  }

  /// Silently pauses capture before application-owned TTS (such as reading an
  /// assessment). No transcript from this recognizer session is submitted.
  Future<void> pauseListeningForSpeech() async {
    if (state != VoiceTutorState.listening &&
        state != VoiceTutorState.preparingListening) {
      return;
    }
    _acceptSpeechCallbacks = false;
    _finalSpeechReceived = true;
    _speechGeneration++;
    transcript = '';
    try {
      await _speech.cancel();
    } catch (_) {
      // App-owned speech output must continue even if capture cleanup fails.
    }
    state = VoiceTutorState.idle;
    notifyListeners();
    _emitDemo('speech_recognition_cancelled', {'reason': 'tts_started'});
  }

  Future<void> send(String text, {String inputMethod = 'typed'}) async {
    if (_disposed) return;
    final question = text.trim();
    final normalized = question.toLowerCase().replaceAll(
      RegExp(r'[.!?]+$'),
      '',
    );
    if ({'stop speaking', 'stop talking'}.contains(normalized) &&
        state == VoiceTutorState.speaking) {
      await stopSpeaking();
      return;
    }
    if (question.isEmpty || _busy) {
      if (question.isEmpty) _setError('Enter or say a question first.');
      return;
    }
    _busy = true;
    _acceptSpeechCallbacks = false;
    _speechGeneration++;
    try {
      await _speech.cancel();
    } catch (_) {
      // Text and typed questions remain usable if speech cleanup fails.
    }
    try {
      await _output.stop();
    } catch (_) {
      // A failed stop must not leave the request stuck in the thinking state.
    }
    errorMessage = null;
    transcript = question;
    final previous = List<TutorMessage>.unmodifiable(messages);
    final requestGeneration = ++_requestGeneration;
    messages.add(TutorMessage('user', question));
    state = VoiceTutorState.thinking;
    notifyListeners();
    _emitDemo('tutor_input_received', {
      'language': language,
      'input_method': inputMethod,
      'transcript': question,
    });
    await _announceStatus(statusText);
    var requestLessonContext = lessonContext;
    try {
      requestLessonContext =
          screenContextProvider?.call().toTutorContext() ?? lessonContext;
    } catch (error) {
      debugPrint('AI Tutor screen context unavailable (${error.runtimeType}).');
    }
    try {
      final localAnswer = contextualCommandHandler != null
          ? await contextualCommandHandler!.call(question, previous)
          : await localCommandHandler?.call(question);
      if (localAnswer != null) {
        _emitDemo('tutor_action_response_ready', {
          'response_kind': 'local_command',
          'response_text': localAnswer,
        });
        reply = localAnswer;
        messages.add(TutorMessage('assistant', localAnswer));
        state = VoiceTutorState.speaking;
        notifyListeners();
        final generation = ++_speechGeneration;
        await _speech.cancel();
        _emitDemo('tts_started', {'response_kind': 'action'});
        await _output.speak(localAnswer);
        _emitDemo('tts_completed', {'response_kind': 'action'});
        if (generation == _speechGeneration &&
            state == VoiceTutorState.speaking) {
          state = VoiceTutorState.idle;
          notifyListeners();
          await onLocalCommandComplete?.call();
        }
        return;
      }
      _emitDemo('tutor_backend_request_started', {
        'language': language,
        'input_method': inputMethod,
      });
      final response = await _gateway
          .ask(
            question: question,
            language: language,
            history: previous,
            lessonContext: requestLessonContext,
            verifiedExamples: lessonExamples,
          )
          .timeout(requestTimeout);
      if (requestGeneration != _requestGeneration) return;
      _emitDemo('tutor_response_generated', {
        'source': response.source,
        'verified_example_count': response.verifiedExamples.length,
      });
      await _presentResponse(response, requestGeneration);
    } on TimeoutException {
      if (requestGeneration == _requestGeneration) {
        await _respondOfflineOrExplain(
          question,
          previous,
          requestGeneration,
          'The tutor took too long to respond.',
          requestLessonContext,
        );
      }
    } catch (error) {
      debugPrint('AI Tutor request failed (${error.runtimeType}).');
      if (requestGeneration == _requestGeneration) {
        await _respondOfflineOrExplain(
          question,
          previous,
          requestGeneration,
          'The online tutor could not connect.',
          requestLessonContext,
        );
      }
    } finally {
      if (requestGeneration == _requestGeneration) _busy = false;
    }
  }

  Future<void> _respondOfflineOrExplain(
    String question,
    List<TutorMessage> history,
    int requestGeneration,
    String reason,
    String requestLessonContext,
  ) async {
    if (language == 'English') {
      try {
        final response = await offlineTutorHandler?.call(
          question,
          history,
          requestLessonContext,
          lessonExamples,
        );
        if (response != null) {
          await _presentResponse(response, requestGeneration);
          return;
        }
      } catch (_) {
        // Keep typed input available even if the offline helper itself fails.
      }
    }
    if (requestGeneration == _requestGeneration) {
      final timedOut = reason.contains('too long');
      final message = switch (language) {
        'Hindi' =>
          timedOut
              ? 'ऑनलाइन ट्यूटर ने समय पर उत्तर नहीं दिया। हिंदी में उत्तर अभी उपलब्ध नहीं है। कृपया दोबारा कोशिश करें।'
              : 'ऑनलाइन ट्यूटर से संपर्क नहीं हो पाया। हिंदी में उत्तर अभी उपलब्ध नहीं है। कृपया दोबारा कोशिश करें।',
        'Kannada' =>
          timedOut
              ? 'ಆನ್‌ಲೈನ್ ಟ್ಯೂಟರ್ ಸಮಯಕ್ಕೆ ಉತ್ತರಿಸಲಿಲ್ಲ. ಕನ್ನಡ ಉತ್ತರ ಈಗ ಲಭ್ಯವಿಲ್ಲ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.'
              : 'ಆನ್‌ಲೈನ್ ಟ್ಯೂಟರ್ ಸಂಪರ್ಕವಾಗಲಿಲ್ಲ. ಕನ್ನಡ ಉತ್ತರ ಈಗ ಲಭ್ಯವಿಲ್ಲ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.',
        _ =>
          '$reason Offline help can still cover the six-dot layout and verified English letters and words. You can try again or type your question.',
      };
      _setError(message);
    }
  }

  Future<void> _presentResponse(
    TutorResponse response,
    int requestGeneration,
  ) async {
    if (_disposed || requestGeneration != _requestGeneration) return;
    reply = response.answer;
    verifiedExamples = response.verifiedExamples;
    letterExamples = response.letterExamples;
    sources = response.sources;
    messages.add(TutorMessage('assistant', response.answer));
    _emitDemo('tutor_response_ready', {
      'source': response.source,
      'response_text': response.answer,
      'verified_example_count': response.verifiedExamples.length,
    });
    if (response.source == 'unsupported_language') {
      errorMessage = response.answer;
      state = VoiceTutorState.error;
      notifyListeners();
      await _announceStatus(response.answer);
      return;
    }
    state = VoiceTutorState.speaking;
    notifyListeners();
    final spoken = [
      response.answer,
      ...response.verifiedExamples.map(
        (example) => 'Verified example. ${example.spoken}.',
      ),
    ].join(' ');
    final generation = ++_speechGeneration;
    try {
      _acceptSpeechCallbacks = false;
      await _speech.cancel();
      if (_disposed || generation != _speechGeneration) return;
      _emitDemo('tts_started', {'response_kind': 'tutor'});
      await _output.speak(spoken);
      _emitDemo('tts_completed', {'response_kind': 'tutor'});
    } catch (_) {
      if (requestGeneration == _requestGeneration) {
        errorMessage = switch (language) {
          'Hindi' =>
            'उत्तर मिल गया, लेकिन आवाज़ उपलब्ध नहीं है। उत्तर स्क्रीन पर पढ़ें या फिर से कोशिश करें।',
          'Kannada' =>
            'ಉತ್ತರ ಸಿಕ್ಕಿದೆ, ಆದರೆ ಧ್ವನಿ ಲಭ್ಯವಿಲ್ಲ. ಉತ್ತರವನ್ನು ಪರದೆಯಲ್ಲಿ ಓದಿ ಅಥವಾ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.',
          _ =>
            'The answer is available on screen, but speech playback failed. You can read it or try replaying it.',
        };
        state = VoiceTutorState.error;
        notifyListeners();
        await _announceStatus(errorMessage!);
      }
      return;
    }
    if (generation == _speechGeneration && state == VoiceTutorState.speaking) {
      state = VoiceTutorState.idle;
      notifyListeners();
    }
  }

  Future<void> replay() async {
    if (reply.isEmpty) return;
    _acceptSpeechCallbacks = false;
    _speechGeneration++;
    await _speech.cancel();
    await _output.stop();
    final spoken = [
      reply,
      ...verifiedExamples.map(
        (example) => 'Verified example. ${example.spoken}.',
      ),
    ].join(' ');
    final generation = ++_speechGeneration;
    state = VoiceTutorState.speaking;
    notifyListeners();
    _emitDemo('tts_started', {'response_kind': 'replay'});
    await _output.speak(spoken);
    _emitDemo('tts_completed', {'response_kind': 'replay'});
    if (generation == _speechGeneration && state == VoiceTutorState.speaking) {
      state = VoiceTutorState.idle;
      notifyListeners();
    }
  }

  Future<void> stopSpeaking() async {
    _speechGeneration++;
    _acceptSpeechCallbacks = false;
    await _speech.cancel();
    await _output.stop();
    if (state == VoiceTutorState.speaking) {
      state = VoiceTutorState.idle;
      notifyListeners();
    }
  }

  Future<void> clearConversation() async {
    _requestGeneration++;
    _busy = false;
    _acceptSpeechCallbacks = false;
    _speechGeneration++;
    await _speech.cancel();
    await _output.stop();
    _speechGeneration++;
    messages.clear();
    transcript = '';
    reply = '';
    verifiedExamples = const [];
    letterExamples = const [];
    sources = const [];
    errorMessage = null;
    state = VoiceTutorState.idle;
    notifyListeners();
  }

  void _setError(String message) {
    if (_disposed) return;
    errorMessage = message;
    state = VoiceTutorState.error;
    notifyListeners();
    unawaited(_announceStatus(message));
  }

  String _languageName() => switch (language.toLowerCase()) {
    'hindi' => 'Hindi',
    'kannada' => 'Kannada',
    _ => 'English',
  };

  String _localeUnavailableMessage() => switch (language.toLowerCase()) {
    'hindi' =>
      'इस डिवाइस की speech service में Hindi recognition उपलब्ध नहीं है। Hindi speech pack उपलब्ध हो तो उसे इंस्टॉल करें, या Speech recognition language सेटिंग बदलें। English पर अपने आप switch नहीं किया गया।',
    'kannada' =>
      'ಈ ಸಾಧನದ speech service ನಲ್ಲಿ Kannada recognition ಲಭ್ಯವಿಲ್ಲ. Kannada speech pack ಲಭ್ಯವಿದ್ದರೆ ಸ್ಥಾಪಿಸಿ ಅಥವಾ Speech recognition language ಸೆಟ್ಟಿಂಗ್ ಬದಲಾಯಿಸಿ. English ಗೆ ಸ್ವಯಂಚಾಲಿತವಾಗಿ ಬದಲಾಯಿಸಿಲ್ಲ.',
    _ =>
      'English speech recognition is not reported as available on this device. Install an English speech pack or choose a supported speech language. No language fallback was used.',
  };

  String _speechErrorMessage(String error) {
    final normalized = error.toLowerCase();
    if (normalized.contains('language_unavailable') ||
        normalized.contains('locale_unavailable') ||
        ((normalized.contains('language') || normalized.contains('locale')) &&
            normalized.contains('avail'))) {
      return _localeUnavailableMessage();
    }
    return 'Speech recognition failed: $error. Type your question instead.';
  }

  Future<void> _announceStatus(String message) async {
    try {
      await onStatusAnnouncement?.call(message);
    } catch (_) {
      // The state remains visible and typed input remains available.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _acceptSpeechCallbacks = false;
    _speechGeneration++;
    unawaited(_speech.cancel());
    unawaited(_output.stop());
    super.dispose();
  }
}
