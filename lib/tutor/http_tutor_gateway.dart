import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'voice_tutor_controller.dart';

const _configuredTutorApiBase = String.fromEnvironment(
  'RESONANT_TUTOR_API_BASE',
);

/// Backend URL. Override with --dart-define=RESONANT_TUTOR_API_BASE=http://<PC-LAN-IP>:8000.
/// On web the page's own host is used (so a phone opening http://<PC-IP>:PORT
/// reaches the backend on that PC, not the phone's own "localhost").
String get tutorApiBaseUrl {
  if (_configuredTutorApiBase.isNotEmpty) return _configuredTutorApiBase;
  if (kIsWeb && Uri.base.host.isNotEmpty) {
    return Uri(scheme: Uri.base.scheme, host: Uri.base.host, port: 8000)
        .toString();
  }
  return 'http://localhost:8000';
}

class HttpTutorGateway implements TutorGateway {
  HttpTutorGateway({http.Client? client, Uri? baseUri})
    : _client = client,
      _baseUri = baseUri ?? Uri.parse(tutorApiBaseUrl);

  final http.Client? _client;
  final Uri _baseUri;

  @override
  Future<TutorResponse> ask({
    required String question,
    required List<TutorMessage> history,
    required String lessonContext,
    required List<VerifiedBrailleExample> verifiedExamples,
  }) async {
    final uri = _baseUri.resolve('/ask');
    final headers = const {'content-type': 'application/json'};
    final requestBody = jsonEncode({
      'question': question,
      'language': 'English',
      'lesson_context': lessonContext,
      'history': history
          .map((message) => {'role': message.role, 'content': message.text})
          .toList(),
      'verified_examples': verifiedExamples
          .map((example) => {'text': example.text, 'cells': example.cells})
          .toList(),
    });
    final request = _client != null
        ? _client.post(uri, headers: headers, body: requestBody)
        : http.post(uri, headers: headers, body: requestBody);
    final response = await request.timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TutorGatewayException(
        'Tutor service returned ${response.statusCode}.',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> ||
        body['answer'] is! String ||
        (body['answer'] as String).trim().isEmpty) {
      throw const FormatException('Tutor response was empty.');
    }
    final examples = <VerifiedBrailleExample>[];
    final rawExamples = body['verified_examples'];
    if (rawExamples is List) {
      for (final item in rawExamples.whereType<Map>()) {
        final text = item['text'];
        final cells = item['cells'];
        if (text is String &&
            cells is List &&
            cells.every((cell) => cell is int && cell >= 0 && cell <= 63)) {
          examples.add(VerifiedBrailleExample(text, List<int>.from(cells)));
        }
      }
    }
    final sources = <TutorSource>[];
    final rawSources = body['sources'];
    if (rawSources is List) {
      for (final item in rawSources.whereType<Map>()) {
        final title = item['title'];
        final url = item['url'];
        if (title is String && url is String) {
          sources.add(TutorSource(title: title, url: url));
        }
      }
    }
    final letterExamples = <TutorLetterExample>[];
    final rawLetters = body['letter_examples'];
    if (rawLetters is List) {
      for (final item in rawLetters.whereType<Map>()) {
        final letter = item['letter'];
        final cells = item['cells'];
        final dots = item['dots'];
        final capitalization = item['capitalization'];
        if (letter is String &&
            cells is List &&
            cells.every((cell) => cell is int && cell >= 0 && cell <= 63) &&
            dots is List &&
            dots.every((dot) => dot is int && dot >= 1 && dot <= 6) &&
            capitalization is String) {
          letterExamples.add(
            TutorLetterExample(
              letter: letter,
              cells: List<int>.from(cells),
              dots: List<int>.from(dots),
              capitalization: capitalization,
            ),
          );
        }
      }
    }
    return TutorResponse(
      body['answer'] as String,
      source: body['source'] as String? ?? 'unknown',
      verifiedExamples: examples,
      letterExamples: letterExamples,
      sources: sources,
    );
  }
}

class TutorGatewayException implements Exception {
  final String message;
  const TutorGatewayException(this.message);
  @override
  String toString() => message;
}
