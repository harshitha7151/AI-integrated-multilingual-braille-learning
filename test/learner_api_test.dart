import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonant_braille/learning/learner_account_store.dart';
import 'package:resonant_braille/learning/learner_api.dart';

void main() {
  test('preferred language update reaches the account API with learner proof', () async {
    late http.Request request;
    final client = MockClient((incoming) async {
      request = incoming;
      return http.Response(
        jsonEncode({
          'learner_id': 'learner-1',
          'preferred_language': 'Kannada',
        }),
        200,
      );
    });
    final api = LearnerApi(client: client, baseUri: Uri.parse('https://test'));

    await api.updatePreferredLanguage(
      learnerId: 'learner-1',
      learnerCode: '012345',
      preferredLanguage: 'Kannada',
    );

    expect(request.method, 'PATCH');
    expect(request.url.path, '/learners/learner-1/language');
    expect(jsonDecode(request.body), {
      'learner_code': '012345',
      'preferred_language': 'Kannada',
    });
    client.close();
  });

  test('learner account preference survives serialization and update', () {
    const account = LearnerAccount(
      learnerId: 'learner-1',
      learnerCode: '012345',
      name: 'Anu',
      preferredLanguage: 'Hindi',
    );

    final restored = LearnerAccount.fromJson(account.toJson());
    final updated = restored.withPreferredLanguage('Kannada');

    expect(restored.preferredLanguage, 'Hindi');
    expect(updated.preferredLanguage, 'Kannada');
    expect(updated.learnerCode, '012345');
  });
}
