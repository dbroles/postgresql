import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:user_manager/main.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/models/pg_membership.dart';
import 'package:user_manager/models/pg_user_group.dart';
import 'package:user_manager/services/database_service.dart';
import 'package:postgres/postgres.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Domain Models Test', () {
    test('PgRole.fromRow correctly parses catalog row', () {
      final row = [
        12345, // oid
        'test_user', // name
        false, // isSuperuser
        true, // inherit
        false, // createRole
        false, // createDb
        true, // canLogin
        false, // replication
        false, // bypassRls
        true, // isCurrent
        'Test user description', // description
        true, // isAdmin
        false, // canDrop
      ];

      final role = PgRole.fromRow(row);

      expect(role.oid, 12345);
      expect(role.name, 'test_user');
      expect(role.isSuperuser, false);
      expect(role.inherit, true);
      expect(role.createRole, false);
      expect(role.createDb, false);
      expect(role.canLogin, true);
      expect(role.replication, false);
      expect(role.bypassRls, false);
      expect(role.isCurrent, true);
      expect(role.description, 'Test user description');
      expect(role.isAdmin, true);
      expect(role.canDrop, false);
      expect(role.canManage, true);
    });

    test('PgMembership.fromRow correctly parses catalog row', () {
      final row = [
        100, // roleOid
        200, // memberOid
        'admin_user', // grantor
        true, // adminOption
        true, // inheritOption
        false, // setOption
      ];

      final membership = PgMembership.fromRow(row);

      expect(membership.roleOid, 100);
      expect(membership.memberOid, 200);
      expect(membership.grantor, 'admin_user');
      expect(membership.adminOption, true);
      expect(membership.inheritOption, true);
      expect(membership.setOption, false);
    });

    test('PgUserGroup.fromRow correctly parses query row with grantors', () {
      final row = [
        300, // oid
        'finance_group', // name
        'Finance dept', // description
        ['postgres', 'daniel'], // grantors
        true, // grantable
        false, // granted
      ];

      final group = PgUserGroup.fromRow(row);

      expect(group.oid, 300);
      expect(group.name, 'finance_group');
      expect(group.description, 'Finance dept');
      expect(group.grantors, ['postgres', 'daniel']);
      expect(group.grantable, true);
      expect(group.granted, false);
    });
  });
  group('DatabaseService Pool Configuration Test', () {
    test('DatabaseService defaults username to dbroles and allows custom username', () {
      final defaultService = DatabaseService();
      expect(defaultService.username, 'dbroles');
      defaultService.close();

      final customService = DatabaseService(username: 'custom_admin');
      expect(customService.username, 'custom_admin');
      customService.username = 'another_name';
      expect(customService.username, 'another_name');
      customService.close();
    });

    test('DatabaseService initializes with default pool parameters and properties', () {
      final service = DatabaseService(
        host: 'localhost',
        port: 5432,
        username: 'custom_admin',
        password: 'secret_password',
        sslMode: SslMode.disable,
      );

      expect(service.host, 'localhost');
      expect(service.port, 5432);
      expect(service.username, 'custom_admin');
      expect(service.password, 'secret_password');
      expect(service.sslMode, SslMode.disable);
      expect(service.database, 'postgres');

      // Modifying properties resets pool & caches
      service.host = '192.168.1.10';
      expect(service.host, '192.168.1.10');
      
      service.port = 5433;
      expect(service.port, 5433);

      service.username = 'new_user';
      expect(service.username, 'new_user');

      service.password = 'new_pass';
      expect(service.password, 'new_pass');

      service.sslMode = SslMode.require;
      expect(service.sslMode, SslMode.require);

      // clearCache should execute cleanly without error
      service.clearCache();

      service.close();
    });
  });

  group('App Smoke Test', () {
    testWidgets('App renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.byType(MyApp), findsOneWidget);
    });
  });
}
