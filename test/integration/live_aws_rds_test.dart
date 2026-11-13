import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/services/database_service.dart';

Map<String, String> _loadDotEnv() {
  final env = <String, String>{};
  final file = File('.env');
  if (!file.existsSync()) return env;

  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eqIndex = line.indexOf('=');
    if (eqIndex <= 0) continue;
    final key = line.substring(0, eqIndex).trim();
    var value = line.substring(eqIndex + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    env[key] = value;
  }
  return env;
}

String? _getEnv(Map<String, String> dotEnv, String key) {
  return Platform.environment[key] ?? dotEnv[key];
}

Future<String?> _resolveRdsEndpoint(Map<String, String> dotEnv) async {
  final explicitHost = _getEnv(dotEnv, 'RDS_HOST');
  if (explicitHost != null && explicitHost.isNotEmpty) {
    return explicitHost;
  }

  final instanceId = _getEnv(dotEnv, 'INSTANCE_ID') ?? 'pg-usermanager-test';
  final region = _getEnv(dotEnv, 'AWS_REGION');
  final args = <String>[
    'rds',
    'describe-db-instances',
    if (region != null && region.isNotEmpty) ...['--region', region],
    '--db-instance-identifier',
    instanceId,
    '--query',
    'DBInstances[0].[DBInstanceStatus,Endpoint.Address]',
    '--output',
    'text',
  ];

  try {
    final result = await Process.run('aws', args).timeout(const Duration(seconds: 8));
    if (result.exitCode != 0) return null;
    final parts = result.stdout.toString().trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0] == 'available' && parts[1] != 'None') {
      return parts[1];
    }
  } catch (_) {
    // aws CLI unavailable, unauthenticated, or timed out
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Live AWS RDS PostgreSQL Integration Tests', () {
    late Map<String, String> dotEnv;
    String? rdsHost;
    late String dbName;
    late String dbrolesUser;
    late String dbrolesPass;
    bool isRdsReachable = false;

    setUpAll(() async {
      dotEnv = _loadDotEnv();
      dbName = _getEnv(dotEnv, 'DB_NAME') ?? 'postgres';
      final masterPass = _getEnv(dotEnv, 'MASTER_PASS') ?? '';
      dbrolesUser = _getEnv(dotEnv, 'DBROLES_USER') ?? 'dbroles';
      dbrolesPass = _getEnv(dotEnv, 'DBROLES_PASS') ?? masterPass;

      if (dbrolesPass.isEmpty) {
        return;
      }

      rdsHost = await _resolveRdsEndpoint(dotEnv);
      if (rdsHost == null || rdsHost!.isEmpty) {
        return;
      }

      try {
        final socket = await Socket.connect(
          rdsHost!,
          5432,
          timeout: const Duration(seconds: 3),
        );
        await socket.close();
        isRdsReachable = true;
      } catch (_) {
        isRdsReachable = false;
      }
    });

    test('connects over SSL, manages users/roles, evaluates canDrop, and scopes categories on AWS RDS', () async {
      if (!isRdsReachable || rdsHost == null) {
        // Gracefully skip when AWS RDS test instance is not running or credentials are absent
        return;
      }

      final suffix = DateTime.now().millisecondsSinceEpoch;
      final tempUserName = 'rds_test_user_$suffix';
      final tempRoleName = 'rds_test_role_$suffix';

      SharedPreferences.setMockInitialValues({
        'role_categories_$rdsHost:$dbrolesUser:$dbName':
            '{"$tempRoleName":"rds_test:1:1E88E5"}',
      });

      final db = DatabaseService(
        host: rdsHost!,
        port: 5432,
        database: dbName,
        username: dbrolesUser,
        password: dbrolesPass,
        sslMode: SslMode.require,
      );

      try {
        final connErr = await db.testConnection();
        expect(connErr, isNull, reason: 'Failed to connect to AWS RDS as $dbrolesUser: $connErr');

        expect(await db.fetchSslStatus(), isTrue);
        expect(await db.isCurrentUserSuperuser(), isFalse);
        expect(await db.canCurrentUserCreateRole(), isTrue);

        final current = await db.fetchCurrentUserRole(forceRefresh: true);
        expect(current, isNotNull);
        expect(current!.name, dbrolesUser);
        expect(current.createRole, isTrue);

        // Create a temporary non-login role and login user
        final createdGroup = await db.createRole(
          name: tempRoleName,
          description: 'Temporary RDS test role',
          canLogin: false,
        );
        expect(createdGroup.canLogin, isFalse);

        final createdUser = await db.createRole(
          name: tempUserName,
          description: 'Temporary RDS test user',
          password: 'RdsTestPass!2026',
          validUntil: DateTime.now().add(const Duration(days: 30)),
          canLogin: true,
        );
        expect(createdUser.canLogin, isTrue);
        expect(createdUser.isAdmin, isTrue);
        expect(createdUser.canDrop, isTrue);

        // Verify catalog & category mapping scoped to RDS host:login:database
        final catalog = await db.fetchGroupCatalog(forceRefresh: true);
        final catalogGroup = catalog.firstWhere((g) => g.name == tempRoleName);
        expect(catalogGroup.grantable, isTrue);
        expect(catalogGroup.categoryName, 'rds_test');
        expect(catalogGroup.categoryColorHex, '1E88E5');

        // Grant role, verify membership and canDrop remains true (self-granted)
        await db.grantRole(tempUserName, tempRoleName, userOid: createdUser.oid);
        final groupsAfterGrant = await db.fetchGroupsForUser(createdUser.oid, forceRefresh: true);
        final grantedGroup = groupsAfterGrant.firstWhere((g) => g.name == tempRoleName);
        expect(grantedGroup.granted, isTrue);
        expect(grantedGroup.grantors, isEmpty);

        final refreshedUsers = await db.fetchAllRoles(forceRefresh: true);
        final refreshedUser = refreshedUsers.firstWhere((r) => r.oid == createdUser.oid);
        expect(refreshedUser.canDrop, isTrue);

        // Update user description and expiration
        final updatedUser = await db.updateRole(
          oldName: tempUserName,
          name: tempUserName,
          description: 'Updated RDS test user',
          validUntil: null,
        );
        expect(updatedUser.description, 'Updated RDS test user');
        expect(updatedUser.validUntil, isNull);

        // Revoke role
        await db.revokeRole(tempUserName, tempRoleName, userOid: createdUser.oid);
        final groupsAfterRevoke = await db.fetchGroupsForUser(createdUser.oid, forceRefresh: true);
        expect(groupsAfterRevoke.firstWhere((g) => g.name == tempRoleName).granted, isFalse);
      } finally {
        try {
          await db.dropRole(tempUserName);
        } catch (_) {}
        try {
          await db.dropRole(tempRoleName);
        } catch (_) {}
        await db.close();
      }
    });
  });
}
