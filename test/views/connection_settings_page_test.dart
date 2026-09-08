import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/services/credential_storage_service.dart';
import 'package:user_manager/views/connection_settings_page.dart';

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
            databaseServiceFactory: ({String host = '', int port = 5432, String username = '', String password = '', SslMode sslMode = SslMode.disable}) =>
                FakeDatabaseService(
                  host: host,
                  port: port,
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
      await tester.enterText(inputs.at(2), 'admin');     // User
      await tester.enterText(inputs.at(3), 'super_secure_pass'); // Pass

      // Tap Save & Connect
      final saveBtn = find.widgetWithText(ElevatedButton, 'Save & Connect');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify secure storage has password
      expect(await secureStorage.getPassword(), 'super_secure_pass');

      // Verify SharedPreferences has db_remember_pass but NOT db_pass
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('db_remember_pass'), isTrue);
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
            databaseServiceFactory: ({String host = '', int port = 5432, String username = '', String password = '', SslMode sslMode = SslMode.disable}) =>
                FakeDatabaseService(
                  host: host,
                  port: port,
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
      await tester.enterText(inputs.at(2), 'admin');
      await tester.enterText(inputs.at(3), 'new_session_pass');

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
  });
}

