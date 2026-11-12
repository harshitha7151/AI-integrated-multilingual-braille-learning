import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/learning/role_store.dart';

void main() {
  group('RoleStore', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('resonant-role-');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    RoleStore storeFor(Directory d) =>
        RoleStore(File('${d.path}${Platform.pathSeparator}role.json'));

    test('returns null when no file exists', () async {
      final store = storeFor(dir);
      expect(await store.savedRole(), isNull);
    });

    test('persists and reads back learner role', () async {
      final store = storeFor(dir);
      await store.saveRole(AppRole.learner);
      expect(await storeFor(dir).savedRole(), AppRole.learner);
    });

    test('persists and reads back teacher role', () async {
      final store = storeFor(dir);
      await store.saveRole(AppRole.teacher);
      expect(await storeFor(dir).savedRole(), AppRole.teacher);
    });

    test('clearRole removes the saved role', () async {
      final store = storeFor(dir);
      await store.saveRole(AppRole.learner);
      await store.clearRole();
      expect(await storeFor(dir).savedRole(), isNull);
    });

    test('overwriting teacher with learner works', () async {
      final store = storeFor(dir);
      await store.saveRole(AppRole.teacher);
      await store.saveRole(AppRole.learner);
      expect(await storeFor(dir).savedRole(), AppRole.learner);
    });

    test('returns null for corrupted JSON gracefully', () async {
      final store = storeFor(dir);
      await store.file.parent.create(recursive: true);
      await store.file.writeAsString('not valid json');
      expect(await store.savedRole(), isNull);
    });

    test('returns null when role key is unknown', () async {
      final store = storeFor(dir);
      await store.file.parent.create(recursive: true);
      await store.file.writeAsString('{"role":"admin"}');
      expect(await store.savedRole(), isNull);
    });
  });
}

