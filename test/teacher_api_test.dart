import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonant_braille/teacher/teacher_api.dart';

void main() {
  test('signup posts expected fields and surfaces backend configuration detail', () async {
    var requestCount = 0;
    final api = TeacherApi(
      baseUri: Uri.parse('http://localhost:8000'),
      client: MockClient((request) async {
        requestCount++;
        expect(request.method, 'POST');
        expect(request.url.path, '/teachers/signup');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['name'], 'Teacher');
        expect(payload['email'], 'teacher@example.test');
        expect(payload['password'], 'strong-password');
        return http.Response(
          jsonEncode({
            'detail':
                'Teacher signup is unavailable because passlib[bcrypt] is missing from the Python environment running Uvicorn.',
          }),
          503,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      api.signup(
        name: 'Teacher',
        email: 'teacher@example.test',
        password: 'strong-password',
      ),
      throwsA(
        isA<TeacherApiException>().having(
          (error) => error.message,
          'message',
          contains('passlib[bcrypt]'),
        ),
      ),
    );
    expect(requestCount, 1, reason: 'Login must not run after failed signup.');
  });

  test('successful signup obtains a session only after login succeeds', () async {
    var requestCount = 0;
    final api = TeacherApi(
      baseUri: Uri.parse('http://localhost:8000'),
      client: MockClient((request) async {
        requestCount++;
        if (request.url.path == '/teachers/signup') {
          expect(request.method, 'POST');
          return http.Response(
            jsonEncode({'teacher_id': 'teacher-1', 'name': 'Teacher'}),
            201,
          );
        }
        expect(request.url.path, '/teachers/login');
        return http.Response(
          jsonEncode({
            'teacher_id': 'teacher-1',
            'name': 'Teacher',
            'email': 'teacher@example.test',
            'organization': null,
            'token': 'test-token',
          }),
          200,
        );
      }),
    );

    final session = await api.signup(
      name: 'Teacher',
      email: 'teacher@example.test',
      password: 'strong-password',
    );

    expect(requestCount, 2);
    expect(session.teacherId, 'teacher-1');
    expect(session.token, 'test-token');
  });

  test('signup surfaces a safe schema migration failure from the backend', () async {
    final api = TeacherApi(
      baseUri: Uri.parse('http://localhost:8000'),
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'detail':
                  'Teacher database schema is missing or outdated. Apply pending backend migrations with `python migrate.py`, then retry.',
            }),
            503,
            headers: {'content-type': 'application/json'},
          )),
    );

    await expectLater(
      api.signup(
        name: 'Teacher',
        email: 'teacher@example.test',
        password: 'strong-password',
      ),
      throwsA(
        isA<TeacherApiException>().having(
          (error) => error.message,
          'message',
          contains('schema is missing or outdated'),
        ),
      ),
    );
  });
}
