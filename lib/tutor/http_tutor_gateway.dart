import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import 'voice_tutor_controller.dart';

const tutorApiBaseUrl = apiBaseUrl;

class HttpTutorGateway implements TutorGateway {
  HttpTutorGateway({http.Client? client, Uri? baseUri})
    : _client = client,
      _baseUriOverride = baseUri;

  final http.Client? _client;
  final Uri? _baseUriOverride;
  Uri get _baseUri => _baseUriOverride ?? ApiConfiguration.baseUri;

  @override
  Future<TutorResponse> ask({
    required String question,
    required String language,
    required List<TutorMessage> history,
    required String lessonContext,
    required List<VerifiedBrailleExample> verifiedExamples,
  }) async {
    final uri = _baseUri.resolve('/ask');
    final headers = const {'content-type': 'application/json'};
    final requestBody = jsonEncode({
      'question': question,
      'language': language,
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
