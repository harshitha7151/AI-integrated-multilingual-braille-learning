import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import 'teacher_session_store.dart';

/// HTTP client for teacher sign-up, login, and dashboard data.
class TeacherApi {
  TeacherApi({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUriOverride = baseUri;

  final http.Client _client;
  final Uri? _baseUriOverride;
  Uri get _baseUri => _baseUriOverride ?? ApiConfiguration.baseUri;

  static const _headers = {'content-type': 'application/json'};
  static const _timeout = Duration(seconds: 15);

  Future<TeacherSession> signup({
    required String name,
    required String email,
    required String password,
    String? organization,
  }) async {
    final body = jsonEncode({
      'name': name,
      'email': email,
      'password': password,
      if (organization != null && organization.isNotEmpty)
        'organization': organization,
    });
    final res = await _client
        .post(_baseUri.resolve('/teachers/signup'),
            headers: _headers, body: body)
        .timeout(_timeout);
    _check(res);
    // Signup does not return a token; call login afterwards.
    // Log in immediately to get the token.
    return login(email: email, password: password);
  }

  Future<TeacherSession> login({
    required String email,
    required String password,
  }) async {
    final body = jsonEncode({'email': email, 'password': password});
    final res = await _client
        .post(_baseUri.resolve('/teachers/login'),
            headers: _headers, body: body)
        .timeout(_timeout);
    _check(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return TeacherSession(
      teacherId: json['teacher_id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      organization: json['organization'] as String?,
      token: json['token'] as String,
    );
  }

  Future<void> requestPasswordReset(String email) async {
    final body = jsonEncode({'email': email});
    final res = await _client
        .post(_baseUri.resolve('/teachers/forgot-password'),
            headers: _headers, body: body)
        .timeout(_timeout);
    _check(res);
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final body = jsonEncode({'token': token, 'new_password': newPassword});
    final res = await _client
        .post(_baseUri.resolve('/teachers/reset-password'),
            headers: _headers, body: body)
        .timeout(_timeout);
    _check(res);
  }

  void _check(http.Response res) {
    if (res.statusCode == 409) throw const TeacherApiException('Email already registered.');
    if (res.statusCode == 401) throw const TeacherApiException('Invalid email or password.');
    if (res.statusCode == 429) throw const TeacherApiException('Too many login attempts. Please wait a few minutes.');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String detail = 'Server error ${res.statusCode}.';
      try {
        final b = jsonDecode(res.body);
        if (b is Map && b['detail'] is String) detail = b['detail'] as String;
      } catch (_) {}
      throw TeacherApiException(detail);
    }
  }
}

class TeacherApiException implements Exception {
  final String message;
  const TeacherApiException(this.message);
  @override
  String toString() => message;
}
