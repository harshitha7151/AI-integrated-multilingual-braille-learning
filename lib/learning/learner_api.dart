import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import 'learner_account_store.dart';

/// Thin HTTP client for learner registration and account restore.
///
/// All public methods throw [LearnerApiException] on network or server errors.
class LearnerApi {
  LearnerApi({http.Client? client, Uri? baseUri, this.teacherToken})
      : _client = client ?? http.Client(),
        _baseUriOverride = baseUri;

  final http.Client _client;
  final Uri? _baseUriOverride;
  Uri get _baseUri => _baseUriOverride ?? ApiConfiguration.baseUri;

  /// Bearer token of the logged-in teacher. Required for registration.
  final String? teacherToken;

  Map<String, String> get _headers {
    final h = <String, String>{'content-type': 'application/json'};
    if (teacherToken != null) h['authorization'] = 'Bearer $teacherToken';
    return h;
  }
  static const _timeout = Duration(seconds: 15);

  /// Calls POST /learners/register.
  ///
  /// Returns [LearnerAccount] with [LearnerAccount.learnerCode] set to the
  /// one-time code returned by the backend.
  Future<LearnerAccount> register({
    required String name,
    String? phone,
    String? email,
    String? batch,
    String preferredLanguage = 'English',
    required bool consent,
  }) async {
    final body = jsonEncode({
      'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (batch != null && batch.isNotEmpty) 'batch': batch,
      'preferred_language': preferredLanguage,
      'consent': consent,
    });
    final response = await _client
        .post(_baseUri.resolve('/learners/register'),
            headers: _headers, body: body)
        .timeout(_timeout);
    _checkStatus(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return LearnerAccount(
      learnerId: json['learner_id'] as String,
      learnerCode: json['learner_code'] as String,
      name: json['name'] as String? ?? name,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      batch: json['batch'] as String?,
      preferredLanguage: json['preferred_language'] as String? ?? preferredLanguage,
    );
  }

  /// Calls POST /learners/restore.
  ///
  /// [phoneOrEmail] is the contact used at registration.
  /// [code] is the 6-digit learner code.
  Future<LearnerAccount> restore({
    required String phoneOrEmail,
    required String code,
    // learnerCode is the same as [code] — stored locally for future reference
  }) async {
    final body = jsonEncode({
      'phone_or_email': phoneOrEmail,
      'code': code,
    });
    final response = await _client
        .post(_baseUri.resolve('/learners/restore'),
            headers: _headers, body: body)
        .timeout(_timeout);
    _checkStatus(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return LearnerAccount(
      learnerId: json['learner_id'] as String,
      learnerCode: code,            // keep the entered code for local storage
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      batch: json['batch'] as String?,
      preferredLanguage: json['preferred_language'] as String? ?? 'English',
    );
  }

  /// Updates the persisted preference using the learner's restore code.
  /// The code is sent only over the configured API connection and is never
  /// logged by the backend.
  Future<void> updatePreferredLanguage({
    required String learnerId,
    required String learnerCode,
    required String preferredLanguage,
  }) async {
    final response = await _client
        .patch(
          _baseUri.resolve('/learners/$learnerId/language'),
          headers: _headers,
          body: jsonEncode({
            'learner_code': learnerCode,
            'preferred_language': preferredLanguage,
          }),
        )
        .timeout(_timeout);
    _checkStatus(response);
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode == 404) {
      throw const LearnerApiException(
          'No account found with those credentials.');
    }
    if (response.statusCode == 422) {
      String detail = 'Validation error.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] is String) {
          detail = body['detail'] as String;
        }
      } catch (_) {}
      throw LearnerApiException(detail);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LearnerApiException(
          'Server error ${response.statusCode}.');
    }
  }
}

class LearnerApiException implements Exception {
  final String message;
  const LearnerApiException(this.message);
  @override
  String toString() => message;
}

