import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Live PostgreSQL Fleet Matrix Tests (nuc.fritz.box: 16, 17, 18)', () {
    const host = 'nuc.fritz.box';
    const versions = [
      (version: 'PostgreSQL 16', port: 5416),
      (version: 'PostgreSQL 17', port: 5417),
      (version: 'PostgreSQL 18', port: 5418),
    ];

    bool isFleetReachable = false;

    setUpAll(() async {
      try {
        final socket = await Socket.connect(host, 5416, timeout: const Duration(seconds: 2));
        await socket.close();
        isFleetReachable = true;
      } catch (_) {
        isFleetReachable = false;
      }
    });

    for (final v in versions) {
      test('authenticates, inspects catalog, and persists categories per host:login:database on ${v.version} (port ${v.port})', () async {
        if (!isFleetReachable) {
          // Gracefully skip in remote CI environments where nuc.fritz.box LAN is not accessible
          return;
        }

        SharedPreferences.setMockInitialValues({
          'role_categories_$host:dbroles:postgres':
              '{"hr":"department:1:1E88E5","nld":"country:2:FB8C00"}',
        });

        final db = DatabaseService(
          host: host,
          port: v.port,
          username: 'dbroles',
          password: 'dbroles',
          sslMode: SslMode.disable,
        );

        try {
          // 1. Fetch current user role
          final current = await db.fetchCurrentUserRole(forceRefresh: true);
          expect(current, isNotNull);
          expect(current!.name, 'dbroles');
          expect(current.createRole, isTrue);

          // 2. Fetch Users (rolcanlogin = true)
          final users = await db.fetchAllRoles(forceRefresh: true);
          expect(users.isNotEmpty, isTrue);
          final userNames = users.map((r) => r.name).toSet();
          expect(userNames, containsAll(['dbroles', 'alice', 'bob', 'karen']));

          // 3. Fetch Groups / Roles (rolcanlogin = false)
          final groups = await db.fetchGroupCatalog(forceRefresh: true);
          expect(groups.isNotEmpty, isTrue);
          final groupNames = groups.map((g) => g.name).toSet();
          expect(groupNames, containsAll(['hr', 'finance', 'nld', 'bel', 'usa', 'legacy_role']));

          // 4. Check Category capability
          final canSetCategory = await db.canCurrentUserSetCategoryParameter(forceRefresh: true);
          expect(canSetCategory, isTrue);

          // 5. Fetch User Groups for Alice
          final alice = users.firstWhere((r) => r.name == 'alice');
          final aliceGroups = await db.fetchGroupsForUser(alice.oid, forceRefresh: true);
          expect(aliceGroups.isNotEmpty, isTrue);

          // In init-test-fixtures.sql, hr and nld were granted by 'postgres' (external grantor)
          final hrGroup = aliceGroups.firstWhere((g) => g.name == 'hr');
          expect(hrGroup.grantors, contains('postgres'));
          expect(hrGroup.categoryName, 'department');
          expect(hrGroup.categoryColorHex, '1E88E5');

          final nldGroup = aliceGroups.firstWhere((g) => g.name == 'nld');
          expect(nldGroup.grantors, contains('postgres'));
          expect(nldGroup.categoryName, 'country');
          expect(nldGroup.categoryColorHex, 'FB8C00');

          // 6. Test Grant / Revoke by dbroles
          await db.grantRole('alice', 'hr', userOid: alice.oid);
          final afterGrant = await db.fetchGroupsForUser(alice.oid, forceRefresh: true);
          final hrAfterGrant = afterGrant.firstWhere((g) => g.name == 'hr');
          expect(hrAfterGrant.granted, isTrue); // Now granted by dbroles!

          await db.revokeRole('alice', 'hr', userOid: alice.oid);
          final afterRevoke = await db.fetchGroupsForUser(alice.oid, forceRefresh: true);
          final hrAfterRevoke = afterRevoke.firstWhere((g) => g.name == 'hr');
          expect(hrAfterRevoke.granted, isFalse);

          // 7. Test Category Update via SharedPreferences per host:login:database
          await db.setRoleCategory('legacy_role', 'testing:9:34BB22');
          final updatedRoles = await db.fetchGroupsForUser(alice.oid, forceRefresh: true);
          final updatedLegacy = updatedRoles.firstWhere((g) => g.name == 'legacy_role');
          expect(updatedLegacy.categoryName, 'testing');
          expect(updatedLegacy.categoryColorHex, '34BB22');

          // Reset legacy_role category
          await db.setRoleCategory('legacy_role', null);
        } finally {
          await db.close();
        }
      });
    }
  });
}
