import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';

const Object _droppedLiveValue = Object();

Object? _sanitizeLiveValue(Object? value, bool includeTranscripts, int depth) {
  if (depth > 3) return _droppedLiveValue;
  if (value == null || value is num || value is bool) return value;
  if (value is String) {
    return value.length > 500 ? value.substring(0, 500) : value;
  }
  if (value is List) {
    return [
      for (final item in value.take(32))
        if (_sanitizeLiveValue(item, includeTranscripts, depth + 1)
            case final sanitized when !identical(sanitized, _droppedLiveValue))
          sanitized,
    ];
  }
  if (value is Map) {
    final clean = <String, Object?>{};
    for (final entry in value.entries.take(32)) {
      if (entry.key is! String) continue;
      final key = entry.key as String;
      final normalized = key.toLowerCase();
      if (RegExp(
        r'password|secret|token|credential|learner[_-]?id|username|email|phone|audio|recording',
      ).hasMatch(normalized)) {
        continue;
      }
      if (!includeTranscripts &&
          const {
            'transcript',
            'question_text',
            'input_text',
            'response_text',
          }.contains(normalized)) {
        continue;
      }
      final sanitized = _sanitizeLiveValue(
        entry.value,
        includeTranscripts,
        depth + 1,
      );
      if (!identical(sanitized, _droppedLiveValue)) clean[key] = sanitized;
    }
    return clean;
  }
  return _droppedLiveValue;
}

/// Sends anonymized, session-scoped activity to the optional laptop demo.
/// Events stay in memory and retry with the same ID until acknowledged.
class LiveDemoClient {
  LiveDemoClient({http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _baseUriOverride = baseUri;

  final http.Client _client;
  Uri? _baseUriOverride;
  final Queue<Map<String, dynamic>> _pending = Queue();
  Timer? _retryTimer;
  String? _sessionId;
  String? _mobileToken;
  bool includeTranscripts = false;
  bool _sending = false;
  void Function()? onSessionExpired;

  bool get isConnected => _sessionId != null && _mobileToken != null;
  String? get sessionId => _sessionId;
  Uri get baseUri => _baseUriOverride ?? ApiConfiguration.baseUri;

  void configureBaseUri(Uri value) {
    if (isConnected) {
      throw StateError('Disconnect before changing the laptop server address.');
    }
    final normalized = ApiConfiguration.configure(value);
    _baseUriOverride = normalized;
  }

  Future<void> connect(String sessionId, String pairingCode) async {
    final response = await _client
        .post(
          baseUri.resolve('/demo/sessions/$sessionId/mobile'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'pairing_code': pairingCode.trim()}),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decode(response);
    _sessionId = body['session_id'] as String;
    _mobileToken = body['mobile_token'] as String;
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_flush()),
    );
    emit('mobile_connected');
  }

  void emit(
    String type, {
    Map<String, Object?> payload = const {},
    String? correlationId,
  }) {
    if (!isConnected) return;
    final safePayload = <String, Object?>{};
    for (final entry in payload.entries) {
      final key = entry.key.toLowerCase();
      if (RegExp(
        r'password|secret|token|credential|learner[_-]?id|username|email|phone|audio|recording',
      ).hasMatch(key)) {
        continue;
      }
      if (!includeTranscripts &&
          const {
            'transcript',
            'question_text',
            'input_text',
            'response_text',
          }.contains(key)) {
        continue;
      }
      final value = _sanitizeLiveValue(entry.value, includeTranscripts, 0);
      if (!identical(value, _droppedLiveValue)) safePayload[entry.key] = value;
    }
    if (_pending.length >= 250) _pending.removeFirst();
    _pending.add({
      'event_id': _uuidV4(),
      'event_type': type,
      if (correlationId != null) 'correlation_id': correlationId,
      'payload': safePayload,
    });
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_sending || !isConnected) return;
    _sending = true;
    try {
      while (_pending.isNotEmpty && isConnected) {
        final response = await _client
            .post(
              baseUri.resolve('/demo/sessions/$_sessionId/events'),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer $_mobileToken',
              },
              body: jsonEncode(_pending.first),
            )
            .timeout(const Duration(seconds: 10));
        _decode(response);
        _pending.removeFirst();
      }
    } catch (error) {
      if (error is LiveDemoException && error.statusCode == 401) {
        await disconnect();
        onSessionExpired?.call();
        return;
      }
      // Keep the same event ID queued; the timer or the next event retries it.
    } finally {
      _sending = false;
    }
  }

  Future<void> disconnect() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _pending.clear();
    _sessionId = null;
    _mobileToken = null;
    includeTranscripts = false;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LiveDemoException(
        body['detail'] as String? ??
            'Live demo request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class LiveDemoException implements Exception {
  const LiveDemoException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
