import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonant_braille/core/api_config.dart';
import 'package:resonant_braille/learning/learner_api.dart';
import 'package:resonant_braille/tutor/live_demo_client.dart';

void main() {
  setUp(ApiConfiguration.resetToBuildConfig);
  tearDown(ApiConfiguration.resetToBuildConfig);

  test('live demo configuration updates the shared backend origin', () {
    final liveDemo = LiveDemoClient();
    liveDemo.configureBaseUri(
      Uri.parse('http://192.168.1.42:8000/path?temporary=1#fragment'),
    );

    expect(ApiConfiguration.baseUri.toString(), 'http://192.168.1.42:8000');
    expect(liveDemo.baseUri, ApiConfiguration.baseUri);
  });

  test('clients created before configuration use the updated shared origin', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({
          'learner_id': '11111111-1111-1111-1111-111111111111',
          'name': 'Learner',
          'preferred_language': 'English',
        }),
        200,
      );
    });
    final learnerApi = LearnerApi(client: client);
    ApiConfiguration.configure(Uri.parse('https://resonant.test:9443/demo'));

    await learnerApi.restore(phoneOrEmail: 'learner@example.test', code: '012345');

    expect(requestedUri.origin, 'https://resonant.test:9443');
    expect(requestedUri.path, '/learners/restore');
  });

  test('invalid or credential-bearing backend URLs fail with a clear error', () {
    for (final invalid in [
      Uri.parse('ftp://resonant.test'),
      Uri.parse('http:///missing-host'),
      Uri.parse('https://user:password@resonant.test'),
    ]) {
      expect(
        () => ApiConfiguration.configure(invalid),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('without credentials'),
          ),
        ),
      );
    }
  });
}
