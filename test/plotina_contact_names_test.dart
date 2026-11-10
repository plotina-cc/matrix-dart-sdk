// SPDX-FileCopyrightText: 2026 Plotina
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Regression test for the `plotina/contact-names` patch:
//
// The app may keep device-local names for contacts and install a single
// resolver on the client ([Client.localNameResolver]). It has to win in every
// place a name is read — [User.displayName], [User.calcDisplayname],
// [User.mention] and the room title computed from heroes — and it must be
// invisible when it has nothing to say, including when it is broken.

import 'package:matrix/matrix.dart';
import 'package:test/test.dart';

import 'fake_database.dart';

void main() {
  group('Plotina contact names: Client.localNameResolver', () {
    late Client client;
    late Room room;
    late User alice;
    late User bob;

    setUp(() async {
      client = Client(
        'plotina-contact-names-test',
        httpClient: FakeMatrixApi(),
        database: await getDatabase(),
      );
      room = Room(id: '!dm:server.abc', client: client);
      alice = User(
        '@alice:example.com',
        membership: 'join',
        displayName: 'Alice M',
        room: room,
      );
      bob = User(
        '@bob:example.com',
        membership: 'join',
        displayName: 'Bob',
        room: room,
      );
      room.setState(alice);
      room.setState(bob);
      await client.checkHomeserver(
        Uri.parse('https://fakeserver.notexisting'),
        checkWellKnown: false,
      );
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: 'test'),
        password: '1234',
      );
      await client.abortSync();
    });

    tearDown(() async {
      await client.logout();
    });

    test('without a resolver the SDK behaves exactly as before', () {
      expect(client.localNameResolver, isNull);
      expect(alice.displayName, 'Alice M');
      expect(alice.rawDisplayName, 'Alice M');
      expect(alice.calcDisplayname(), 'Alice M');
    });

    test('a resolver with nothing for this user keeps the real name', () {
      client.localNameResolver = (userId) => null;
      expect(bob.displayName, 'Bob');
      expect(bob.calcDisplayname(), 'Bob');
    });

    test('returns the local name for the user it knows', () {
      final names = {bob.id: 'Боб'};
      client.localNameResolver = (userId) => names[userId];

      expect(bob.displayName, 'Боб');
      expect(bob.calcDisplayname(), 'Боб');
      // A user the resolver knows nothing about is untouched.
      expect(alice.displayName, 'Alice M');
    });

    test('the raw member state name stays available and unmodified', () {
      client.localNameResolver = (_) => 'Локальное имя';
      expect(alice.displayName, 'Локальное имя');
      expect(alice.rawDisplayName, 'Alice M');
      // Nothing was written: the room state still carries the real name.
      expect(
        room.getState(EventTypes.RoomMember, alice.id)?.content['displayname'],
        'Alice M',
      );
    });

    test('empty and blank local names fall back to the real name', () {
      client.localNameResolver = (_) => '';
      expect(alice.displayName, 'Alice M');
      client.localNameResolver = (_) => '   ';
      expect(alice.displayName, 'Alice M');
      client.localNameResolver = (_) => '\n\t';
      expect(alice.calcDisplayname(), 'Alice M');
    });

    test('a local name is trimmed', () {
      client.localNameResolver = (_) => '  Денчик  ';
      expect(alice.displayName, 'Денчик');
    });

    test('a throwing resolver does not break name rendering', () {
      client.localNameResolver = (_) =>
          throw StateError('broken account data');
      expect(alice.displayName, 'Alice M');
      expect(alice.calcDisplayname(), 'Alice M');
      expect(alice.mention, '@[Alice M]');
    });

    test('mentions are built from the local name', () {
      expect(alice.mention, '@[Alice M]');
      // Only Alice is renamed — when both members would carry the same name
      // the SDK appends a hash to disambiguate, which is upstream behaviour.
      client.localNameResolver = (userId) =>
          userId == alice.id ? 'Алиса' : null;
      expect(alice.mention, '@[Алиса]');
      // A local name that is a single word needs no brackets.
      client.localNameResolver = (userId) =>
          userId == alice.id ? 'Alisa' : null;
      expect(alice.mention, '@Alisa');
      // A name that cannot be parsed back out of a plain-text body still falls
      // back to the mxid, exactly like an unparseable real name.
      client.localNameResolver = (userId) =>
          userId == alice.id ? 'Алиса: [test]' : null;
      expect(alice.mention, alice.id);
    });

    test('the room title computed from heroes uses the local name', () {
      room.summary.mHeroes = [alice.id];
      final plain = room.getLocalizedDisplayname();
      expect(plain, contains('Alice M'));

      client.localNameResolver = (userId) =>
          userId == alice.id ? 'Локальная Алиса' : null;
      final renamed = room.getLocalizedDisplayname();
      expect(renamed, contains('Локальная Алиса'));
      expect(renamed, isNot(contains('Alice M')));
    });

    test('clearing the resolver restores the real names', () {
      client.localNameResolver = (_) => 'Локальное имя';
      expect(alice.displayName, 'Локальное имя');
      client.localNameResolver = null;
      expect(alice.displayName, 'Alice M');
    });

    test('users without any displayname keep the localpart fallback', () {
      final nameless = User('@carol:example.com', room: room);
      expect(nameless.calcDisplayname(), 'Carol');
      client.localNameResolver = (userId) =>
          userId == nameless.id ? 'Каролина' : null;
      expect(nameless.calcDisplayname(), 'Каролина');
    });
  });
}
