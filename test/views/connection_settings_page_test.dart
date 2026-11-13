import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/services/credential_storage_service.dart';
import 'package:user_manager/views/connection_settings_page.dart';
import 'package:user_manager/views/connection_status_bar.dart';
import 'package:user_manager/views/create_role_admin_dialog.dart';

import '../fakes/fake_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('ConnectionSettingsPage Security & Remember Password Tests', () {
    testWidgets('renders Remember Password switch and defaults to true', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService(password: 'existing_pass');

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionSettingsPage(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.widgetWithText(SwitchListTile, 'Remember password');
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isTrue);
    });

    testWidgets('saving with Remember Password checked saves to secure storage and NOT to SharedPreferences db_pass', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService();
      final secureStorage = CredentialStorageService();

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionSettingsPage(
            dbService: fakeDb,
            credentialStorage: secureStorage,
            databaseServiceFactory: ({String host = '', int port = 5432, String database = 'postgres', String username = '', String password = '', SslMode sslMode = SslMode.disable}) =>
                FakeDatabaseService(
                  host: host,
                  port: port,
                  database: database,
                  username: username,
                  password: password,
                  sslMode: sslMode,
                  isSuperuserResult: false,
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter connection details
      final inputs = find.byType(TextFormField);
      await tester.enterText(inputs.at(0), '127.0.0.1'); // Host
      await tester.enterText(inputs.at(1), '5432');      // Port
      await tester.enterText(inputs.at(2), 'app_db');    // Database
      await tester.enterText(inputs.at(3), 'admin');     // User
      await tester.enterText(inputs.at(4), 'super_secure_pass'); // Pass

      // Tap Save & Connect
      final saveBtn = find.widgetWithText(ElevatedButton, 'Save & Connect');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify secure storage has password
      expect(await secureStorage.getPassword(), 'super_secure_pass');

      // Verify SharedPreferences has db_remember_pass, db_name, but NOT db_pass
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('db_remember_pass'), isTrue);
      expect(prefs.getString('db_name'), 'app_db');
      expect(fakeDb.database, 'app_db');
      expect(prefs.containsKey('db_pass'), isFalse);
    });

    testWidgets('saving with Remember Password unchecked deletes from secure storage and sets db_remember_pass to false', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService();
      final secureStorage = CredentialStorageService();
      await secureStorage.savePassword('old_secret');

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionSettingsPage(
            dbService: fakeDb,
            credentialStorage: secureStorage,
            databaseServiceFactory: ({String host = '', int port = 5432, String database = 'postgres', String username = '', String password = '', SslMode sslMode = SslMode.disable}) =>
                FakeDatabaseService(
                  host: host,
                  port: port,
                  database: database,
                  username: username,
                  password: password,
                  sslMode: sslMode,
                  isSuperuserResult: false,
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter connection details
      final inputs = find.byType(TextFormField);
      await tester.enterText(inputs.at(0), '127.0.0.1');
      await tester.enterText(inputs.at(1), '5432');
      await tester.enterText(inputs.at(2), 'postgres');
      await tester.enterText(inputs.at(3), 'admin');
      await tester.enterText(inputs.at(4), 'new_session_pass');

      // Toggle Remember Password OFF
      final switchFinder = find.widgetWithText(SwitchListTile, 'Remember password');
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isFalse);

      // Tap Save & Connect
      final saveBtn = find.widgetWithText(ElevatedButton, 'Save & Connect');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify password deleted from secure storage
      expect(await secureStorage.getPassword(), isNull);

      // Verify SharedPreferences db_remember_pass is false and db_pass is not set
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('db_remember_pass'), isFalse);
      expect(prefs.containsKey('db_pass'), isFalse);
    });

    testWidgets('fits completely within standard 800x600 desktop window without cutting off action buttons', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService();
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionSettingsPage(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no layout overflow exception
      expect(tester.takeException(), isNull);

      // Verify buttons are fully visible within 600px viewport height
      final saveBtn = find.widgetWithText(ElevatedButton, 'Save & Connect');
      final testBtn = find.widgetWithText(OutlinedButton, 'Test Connection');
      expect(saveBtn, findsOneWidget);
      expect(testBtn, findsOneWidget);

      final saveRect = tester.getRect(saveBtn);
      final testRect = tester.getRect(testBtn);

      // Both buttons must be completely above the bottom edge of the 600px window
      expect(saveRect.bottom, lessThanOrEqualTo(600.0));
      expect(testRect.bottom, lessThanOrEqualTo(600.0));
    });

    testWidgets('saves connection profile and allows one-tap switching and deletion of saved connections', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService();
      final secureStorage = CredentialStorageService();

      FakeDatabaseService factoryFn({
        String host = '',
        int port = 5432,
        String database = 'postgres',
        String username = '',
        String password = '',
        SslMode sslMode = SslMode.disable,
      }) =>
          FakeDatabaseService(
            host: host,
            port: port,
            database: database,
            username: username,
            password: password,
            sslMode: sslMode,
            isSuperuserResult: false,
          );

      // Save first connection (default port 5432 -> label omits :5432)
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: ConnectionSettingsPage(
            dbService: fakeDb,
            credentialStorage: secureStorage,
            databaseServiceFactory: factoryFn,
          ),
        ),
      );
      await tester.pumpAndSettle();

      var inputs = find.byType(TextFormField);
      await tester.enterText(inputs.at(0), 'db1.example.com');
      await tester.enterText(inputs.at(1), '5432');
      await tester.enterText(inputs.at(2), 'prod_db');
      await tester.enterText(inputs.at(3), 'alice');
      await tester.enterText(inputs.at(4), 'alice_secret');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save & Connect'));
      await tester.pumpAndSettle();

      // Re-open settings page and save a second connection with custom port 5416
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: ConnectionSettingsPage(
            dbService: fakeDb,
            credentialStorage: secureStorage,
            databaseServiceFactory: factoryFn,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First saved connection chip should be visible without :5432
      expect(find.widgetWithText(InputChip, 'alice@db1.example.com/prod_db'), findsOneWidget);

      inputs = find.byType(TextFormField);
      await tester.enterText(inputs.at(0), 'nuc.fritz.box');
      await tester.enterText(inputs.at(1), '5416');
      await tester.enterText(inputs.at(2), 'staging_db');
      await tester.enterText(inputs.at(3), 'bob');
      await tester.enterText(inputs.at(4), 'bob_secret');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save & Connect'));
      await tester.pumpAndSettle();

      // Re-open settings page; both chips should be visible
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: ConnectionSettingsPage(
            dbService: fakeDb,
            credentialStorage: secureStorage,
            databaseServiceFactory: factoryFn,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chip1 = find.widgetWithText(InputChip, 'alice@db1.example.com/prod_db');
      final chip2 = find.widgetWithText(InputChip, 'bob@nuc.fritz.box:5416/staging_db');
      expect(chip1, findsOneWidget);
      expect(chip2, findsOneWidget);

      // Tap chip1 to switch back to alice@db1.example.com/prod_db
      await tester.tap(chip1);
      await tester.pumpAndSettle();

      inputs = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(inputs.at(0)).controller!.text, 'db1.example.com');
      expect(tester.widget<TextFormField>(inputs.at(1)).controller!.text, '5432');
      expect(tester.widget<TextFormField>(inputs.at(2)).controller!.text, 'prod_db');
      expect(tester.widget<TextFormField>(inputs.at(3)).controller!.text, 'alice');
      expect(tester.widget<TextFormField>(inputs.at(4)).controller!.text, 'alice_secret');

      // Delete chip2 by tapping its delete icon
      final deleteIcon = find.descendant(of: chip2, matching: find.byTooltip('Remove saved connection'));
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, 'bob@nuc.fritz.box:5416/staging_db'), findsNothing);
      expect(
        await secureStorage.getPassword(
          connectionKey: 'nuc.fritz.box:5416:staging_db:bob',
          fallbackToDefault: false,
        ),
        isNull,
      );
    });
  });

  group('ConnectionStatusBar Target Display Tests', () {
    testWidgets('displays username@host/database when port is 5432 and includes :port when not 5432 without Connected to or with ssl text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ConnectionStatusBar(
              clusterName: '',
              host: 'db.example.com',
              port: 5432,
              database: 'analytics',
              username: 'dbroles',
              isSslEnabled: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('dbroles@db.example.com/analytics'), findsOneWidget);
      expect(find.textContaining('Connected to'), findsNothing);
      expect(find.textContaining('with ssl'), findsNothing);
      expect(find.byIcon(Icons.lock), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ConnectionStatusBar(
              clusterName: 'pg16_main',
              host: 'nuc.fritz.box',
              port: 5416,
              database: 'postgres',
              username: 'dbroles',
              isSslEnabled: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(
        find.text('pg16_main on dbroles@nuc.fritz.box:5416/postgres'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
    });

    testWidgets('scrolls as a continuous loop ticker on mobile when AWS RDS hostname overflows', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const longAwsHost = 'database-1.cx83j92ks82.eu-central-1.rds.amazonaws.com';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ConnectionStatusBar(
              clusterName: '',
              host: longAwsHost,
              port: 5432,
              database: 'postgres',
              username: 'dbroles',
              isSslEnabled: true,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expectedText = 'dbroles@$longAwsHost/postgres';
      final textFinder = find.text(expectedText);
      expect(textFinder, findsOneWidget);

      final initialTopLeft = tester.getTopLeft(textFinder);

      // Advance time by 500ms -> ticker should scroll left (x decreases)
      await tester.pump(const Duration(milliseconds: 500));
      final scrolledTopLeft = tester.getTopLeft(textFinder);
      expect(scrolledTopLeft.dx, lessThan(initialTopLeft.dx));
    });
  });

  group('CreateRoleAdminDialog Bootstrap ADMIN OPTION Checkbox Tests', () {
    testWidgets('defaults Grant ADMIN OPTION checkbox to checked and passes grantAdminOption: true', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateRoleAdminDialog(dbService: fakeDb),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final checkboxFinder = find.widgetWithText(
        CheckboxListTile,
        'Grant ADMIN OPTION on existing users and roles',
      );
      expect(checkboxFinder, findsOneWidget);

      final checkbox = tester.widget<CheckboxListTile>(checkboxFinder);
      expect(checkbox.value, isTrue);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Admin Password'),
        'admin_secret_123',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Setup Admin'));
      await tester.pumpAndSettle();

      expect(fakeDb.setupRoleAdminCalls, 1);
      expect(fakeDb.lastSetupAdminName, 'dbroles');
      expect(fakeDb.lastSetupAdminPass, 'admin_secret_123');
      expect(fakeDb.lastSetupGrantAdminOption, isTrue);
    });

    testWidgets('unchecking Grant ADMIN OPTION checkbox passes grantAdminOption: false', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateRoleAdminDialog(dbService: fakeDb),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final checkboxFinder = find.widgetWithText(
        CheckboxListTile,
        'Grant ADMIN OPTION on existing users and roles',
      );
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      final checkbox = tester.widget<CheckboxListTile>(checkboxFinder);
      expect(checkbox.value, isFalse);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Admin Password'),
        'admin_secret_123',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Setup Admin'));
      await tester.pumpAndSettle();

      expect(fakeDb.setupRoleAdminCalls, 1);
      expect(fakeDb.lastSetupGrantAdminOption, isFalse);
    });
  });
}

