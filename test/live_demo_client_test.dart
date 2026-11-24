import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonant_braille/tutor/live_demo_client.dart';

void main() {
  test('pairs with session and removes transcript unless consented', () async {
    final eventSeen = Completer<Map<String, dynamic>>();
    var eventPosts = 0;
    final client = LiveDemoClient(
      baseUri: Uri.parse('http://127.0.0.1:8000'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/mobile')) {
          return http.Response(
            jsonEncode({
              'session_id': 'session-x',
              'mobile_token': 'mobile-secret',
            }),
            200,
          );
        }
        eventPosts++;
        final event = jsonDecode(request.body) as Map<String, dynamic>;
        if (event['event_type'] == 'tutor_input_received' &&
            !eventSeen.isCompleted) {
          eventSeen.complete(event);
        }
        return http.Response('{"accepted":true}', 200);
      }),
    );
    await client.connect('session-x', 'pairing-code-123');
    client.emit(
      'tutor_input_received',
      payload: {
        'transcript': 'How do I write A?',
        'language': 'English',
        'email': 'private@example.test',
      },
    );
    final sent = await eventSeen.future.timeout(const Duration(seconds: 2));
    expect(sent['payload'], {'language': 'English'});
    expect(sent, isNot(contains('mobile-secret')));
    expect(eventPosts, 2); // connection event and tutor request
    await client.disconnect();
  });

  test(
    'explicit transcript consent includes text but never credentials',
    () async {
      final events = <Map<String, dynamic>>[];
      final client = LiveDemoClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/mobile')) {
            return http.Response(
              jsonEncode({'session_id': 's', 'mobile_token': 'm'}),
              200,
            );
          }
          events.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"accepted":true}', 200);
        }),
      );
      await client.connect('s', 'pairing-code-123');
      client.includeTranscripts = true;
      client.emit(
        'tutor_input_received',
        payload: {
          'transcript': 'What is Braille?',
          'api_token': 'must-not-leak',
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events.last['payload'], {'transcript': 'What is Braille?'});
      await client.disconnect();
    },
  );

  test(
    'structured tutor context survives while nested private data is stripped',
    () async {
      final events = <Map<String, dynamic>>[];
      final client = LiveDemoClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/mobile')) {
            return http.Response(
              jsonEncode({'session_id': 's', 'mobile_token': 'm'}),
              200,
            );
          }
          events.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"accepted":true}', 200);
        }),
      );
      await client.connect('s', 'pairing-code-123');
      client.emit(
        'tutor_intent_interpreted',
        payload: {
          'input_text': 'private utterance',
          'context': {
            'screen': 'assessment',
            'options': ['A', 'B'],
            'token': 'must-not-leak',
          },
          'proposed_action': {'name': 'select_answer', 'option_index': 1},
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final payload = events.last['payload'] as Map<String, dynamic>;
      expect(payload, isNot(contains('input_text')));
      expect(payload['context'], {
        'screen': 'assessment',
        'options': ['A', 'B'],
      });
      expect(payload['proposed_action'], {
        'name': 'select_answer',
        'option_index': 1,
      });
      await client.disconnect();
    },
  );

  test('expired server authorization clears session and retry timer', () async {
    var expire = false;
    final expired = Completer<void>();
    final client = LiveDemoClient(
      baseUri: Uri.parse('http://127.0.0.1:8000'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/mobile')) {
          return http.Response(
            jsonEncode({'session_id': 's', 'mobile_token': 'm'}),
            200,
          );
        }
        if (expire) return http.Response('{"detail":"expired"}', 401);
        return http.Response('{"accepted":true}', 200);
      }),
    );
    await client.connect('s', 'pairing-code-123');
    client.onSessionExpired = expired.complete;
    expire = true;
    client.emit('lesson_opened');
    await expired.future.timeout(const Duration(seconds: 2));
    expect(client.isConnected, isFalse);
    await client.disconnect();
  });
}
