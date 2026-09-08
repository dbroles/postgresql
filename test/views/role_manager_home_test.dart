import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/models/pg_user_group.dart';
import 'package:user_manager/views/connection_settings_page.dart';
import 'package:user_manager/views/connection_status_bar.dart';
import 'package:user_manager/views/role_manager_home.dart';
import 'package:user_manager/views/user_list_widget.dart';

import '../fakes/fake_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleRoles = [
    PgRole(
      oid: 101,
      name: 'alice',
      canLogin: true,
      isSuperuser: false,
      description: 'Dev User',
      inherit: true,
      createRole: false,
      createDb: false,
      replication: false,
      bypassRls: false,
      canManage: true,
      canDrop: true,
    ),
    PgRole(
      oid: 102,
      name: 'bob',
      canLogin: true,
      isSuperuser: false,
      description: 'QA User',
      inherit: true,
      createRole: false,
      createDb: false,
      replication: false,
      bypassRls: false,
      canManage: true,
      canDrop: true,
    ),
    PgRole(
      oid: 103,
      name: 'charlie',
      canLogin: true,
      isSuperuser: false,
      description: 'External User',
      inherit: true,
      createRole: false,
      createDb: false,
      replication: false,
      bypassRls: false,
      canManage: false,
      canDrop: false,
    ),
    PgRole(
      oid: 201,
      name: 'developers',
      canLogin: false,
      isSuperuser: false,
      description: 'Developers Group',
      inherit: true,
      createRole: false,
      createDb: false,
      replication: false,
      bypassRls: false,
      canManage: true,
      canDrop: false,
    ),
    PgRole(
      oid: 202,
      name: 'finance_restricted',
      canLogin: false,
      isSuperuser: false,
      description: 'Restricted Group',
      inherit: true,
      createRole: false,
      createDb: false,
      replication: false,
      bypassRls: false,
      canManage: false,
      canDrop: false,
    ),
  ];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'db_host': 'localhost',
      'db_port': 5432,
      'db_user': 'test_admin',
      'db_pass': '',
      'showSystemRoles': false,
      'showSuperusers': false,
      'showDescriptions': true,
      'showFilters': false,
      'showRolesAsUsers': false,
      'showConnectedUser': false,
      'showUngrantableRoles': false,
      'showUngrantableUsers': false,
      'showUsersWithoutAdminOption': false,
    });
  });

  group('RoleManagerHome Initial Loading & Success State', () {
    testWidgets('loads and renders users, groups, status bar, and selection prompt', (WidgetTester tester) async {
      // Set desktop-like resolution to test wide layout
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        roles: sampleRoles,
        mockClusterName: 'prod_cluster_01',
        mockSslStatus: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );

      // Initially, CircularProgressIndicator is displayed while loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Settle async loading
      await tester.pumpAndSettle();

      // Database queries were executed
      expect(fakeDb.testConnectionCalls, 1);
      expect(fakeDb.isCurrentUserSuperuserCalls, 1);
      expect(fakeDb.fetchAllRolesCalls, 1);
      expect(fakeDb.fetchClusterNameCalls, 1);
      expect(fakeDb.fetchSslStatusCalls, 1);

      // Verify UserListWidget is populated with users
      expect(find.byType(UserListWidget), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);

      // Groups are separated and not shown in the user list
      expect(find.text('developers'), findsNothing);

      // Verify wide layout prompt
      expect(find.text('Select a user to manage roles'), findsOneWidget);

      // Verify ConnectionStatusBar shows cluster name and SSL
      expect(find.byType(ConnectionStatusBar), findsOneWidget);
      expect(find.byIcon(Icons.dns), findsOneWidget);
      expect(find.textContaining('prod_cluster_01'), findsOneWidget);
      expect(find.textContaining('with ssl'), findsOneWidget);
    });
  });

  group('RoleManagerHome Error & Connection Failure Handling', () {
    testWidgets('navigates to ConnectionSettingsPage on connection failure', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService(
        testConnectionResult: 'Connection timeout: host unreachable',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );

      await tester.pumpAndSettle();

      expect(fakeDb.testConnectionCalls, 1);
      // When connection fails, ConnectionSettingsPage is automatically pushed
      expect(find.byType(ConnectionSettingsPage), findsOneWidget);
      expect(find.text('Connection Settings'), findsOneWidget);
    });

    testWidgets('shows warning SnackBar and opens settings when superuser is detected', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService(
        roles: sampleRoles,
        isSuperuserResult: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );

      await tester.pumpAndSettle();

      expect(fakeDb.testConnectionCalls, 1);
      expect(fakeDb.isCurrentUserSuperuserCalls, 1);

      // SnackBar warning is presented
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text('Superuser connection detected. Please setup a Role Admin.'),
        findsOneWidget,
      );

      // And navigates to settings
      expect(find.byType(ConnectionSettingsPage), findsOneWidget);
    });

    testWidgets('displays error message and Retry button when role fetch fails', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService(
        roles: sampleRoles,
      );
      fakeDb.throwOnFetchAllRoles = Exception('Catalog query failed');

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );

      // Settle route navigation to ConnectionSettingsPage that opened upon error
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionSettingsPage), findsOneWidget);

      // Pop ConnectionSettingsPage to return to the home screen
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // Home screen should now display the error view with retry button
      expect(find.textContaining('Error: Exception: Catalog query failed'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);

      // Reset error so retry succeeds
      fakeDb.throwOnFetchAllRoles = null;
      await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
      await tester.pumpAndSettle();

      // After retry, users are loaded successfully
      expect(find.byType(UserListWidget), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
    });
  });

  group('Show / Hide Ungrantable Roles Setting', () {
    testWidgets('hides ungrantable roles by default and shows them when toggled in settings', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(roles: sampleRoles);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select Alice
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // developers (canManage: true) is visible
      expect(find.textContaining('developers'), findsOneWidget);

      // finance_restricted (canManage: false) is hidden by default
      expect(find.textContaining('finance_restricted'), findsNothing);

      // Open settings menu
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Verify the switch tile exists and is initially OFF
      final switchFinder = find.widgetWithText(SwitchListTile, 'Show Ungrantable Roles');
      expect(switchFinder, findsOneWidget);
      SwitchListTile switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isFalse);

      // Toggle switch ON
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Switch should now be ON
      switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isTrue);

      // Verify SharedPreferences was updated
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('showUngrantableRoles'), isTrue);

      // Close settings modal by tapping outside or popping
      final NavigatorState navigator = tester.state(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      // finance_restricted is now visible and disabled
      expect(find.textContaining('finance_restricted'), findsOneWidget);
      final checkboxFinder = find.byWidgetPredicate(
        (widget) => widget is CheckboxListTile && widget.title != null && (tester.widget<CheckboxListTile>(find.byWidget(widget)).title?.toString().contains('finance_restricted') ?? false),
      );
      expect(checkboxFinder, findsOneWidget);
      final checkboxWidget = tester.widget<CheckboxListTile>(checkboxFinder);
      expect(checkboxWidget.enabled, isFalse);

      // Re-open settings and toggle it back OFF
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'Show Ungrantable Roles'));
      await tester.pumpAndSettle();
      expect(prefs.getBool('showUngrantableRoles'), isFalse);

      // Close modal
      final NavigatorState navigator2 = tester.state(find.byType(Navigator).last);
      navigator2.pop();
      await tester.pumpAndSettle();

      // finance_restricted is hidden again
      expect(find.textContaining('finance_restricted'), findsNothing);
      expect(find.textContaining('developers'), findsOneWidget);
    });

    testWidgets('shows ungrantable roles if initial setting is true', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': true,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(roles: sampleRoles);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select Alice
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Both developers and finance_restricted should be visible immediately
      expect(find.textContaining('developers'), findsOneWidget);
      expect(find.textContaining('finance_restricted'), findsOneWidget);
    });
  });

  group('Show / Hide Users Without Admin Option Setting', () {
    testWidgets('hides users without admin option by default and shows them when toggled in settings', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(roles: sampleRoles);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // alice and bob (isAdmin: true) are visible in UserListWidget
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);

      // charlie (isAdmin: false) is hidden by default
      expect(find.text('charlie'), findsNothing);

      // Open settings menu
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Verify the switch tile exists and is initially OFF
      final switchFinder = find.widgetWithText(SwitchListTile, 'Show Users Without Admin Option');
      expect(switchFinder, findsOneWidget);
      SwitchListTile switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isFalse);

      // Toggle switch ON
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Switch should now be ON
      switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isTrue);

      // Verify SharedPreferences was updated
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('showUsersWithoutAdminOption'), isTrue);

      // Close settings modal
      final NavigatorState navigator = tester.state(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      // charlie is now visible in the user list
      expect(find.text('charlie'), findsOneWidget);

      // Re-open settings and toggle it back OFF
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'Show Users Without Admin Option'));
      await tester.pumpAndSettle();
      expect(prefs.getBool('showUsersWithoutAdminOption'), isFalse);

      // Close modal
      final NavigatorState navigator2 = tester.state(find.byType(Navigator).last);
      navigator2.pop();
      await tester.pumpAndSettle();

      // charlie is hidden again
      expect(find.text('charlie'), findsNothing);
      expect(find.text('alice'), findsOneWidget);
    });

    testWidgets('shows users without admin option if initial setting is true', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': false,
        'showUsersWithoutAdminOption': true,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(roles: sampleRoles);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // All users including charlie should be visible immediately
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('charlie'), findsOneWidget);
    });

    testWidgets('respects legacy showUngrantableUsers if showUsersWithoutAdminOption is not set', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': false,
        'showUngrantableUsers': true,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(roles: sampleRoles);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Charlie should be visible due to legacy fallback
      expect(find.text('charlie'), findsOneWidget);
    });
  });

  group('Delete Role Button Visibility on Desktop', () {
    testWidgets('shows delete button in AppBar on desktop when deletable user is selected', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': false,
        'showUsersWithoutAdminOption': true,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(roles: sampleRoles);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no user selected -> no delete button
      expect(find.byTooltip('Delete Role'), findsNothing);

      // Select deletable user 'alice'
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Delete button must be visible in AppBar on desktop
      expect(find.byTooltip('Delete Role'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('does not show delete button on desktop when non-deletable user is selected', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': false,
        'showUsersWithoutAdminOption': true,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(roles: sampleRoles);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select non-deletable user 'charlie' (canDrop: false)
      await tester.tap(find.text('charlie'));
      await tester.pumpAndSettle();

      // Delete button must NOT be visible
      expect(find.byTooltip('Delete Role'), findsNothing);
    });

    testWidgets('tapping delete button on desktop opens confirmation dialog', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': false,
        'showUsersWithoutAdminOption': true,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(roles: sampleRoles);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select 'alice'
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Tap Delete button
      await tester.tap(find.byTooltip('Delete Role'));
      await tester.pumpAndSettle();

      // Confirmation dialog should be displayed
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Delete Role'), findsOneWidget);
      expect(find.text('Are you sure you want to delete the role "alice"? This action cannot be undone.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('Show Superusers and Connected User regardless of Show Ungrantable Users', () {
    final customRoles = [
      PgRole(
        oid: 101,
        name: 'alice',
        canLogin: true,
        isSuperuser: false,
        inherit: true,
        createRole: false,
        createDb: false,
        replication: false,
        bypassRls: false,
        canManage: true,
        canDrop: true,
      ),
      PgRole(
        oid: 102,
        name: 'super_admin',
        canLogin: true,
        isSuperuser: true,
        inherit: true,
        createRole: true,
        createDb: true,
        replication: false,
        bypassRls: false,
        canManage: false,
        canDrop: false,
      ),
      PgRole(
        oid: 103,
        name: 'connected_agent',
        canLogin: true,
        isSuperuser: false,
        inherit: true,
        createRole: false,
        createDb: false,
        replication: false,
        bypassRls: false,
        canManage: false,
        canDrop: false,
      ),
      PgRole(
        oid: 104,
        name: 'charlie_ungrantable',
        canLogin: true,
        isSuperuser: false,
        inherit: true,
        createRole: false,
        createDb: false,
        replication: false,
        bypassRls: false,
        canManage: false,
        canDrop: false,
      ),
    ];

    testWidgets('shows superusers when showSuperusers is true even if showUsersWithoutAdminOption is false', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'connected_agent',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': true,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': false,
        'showUsersWithoutAdminOption': false,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        username: 'connected_agent',
        roles: customRoles,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Alice (canManage: true) is visible
      expect(find.text('alice'), findsOneWidget);
      // super_admin (isSuperuser: true, canManage: false) is visible because showSuperusers is true
      expect(find.text('super_admin'), findsOneWidget);
      // charlie_ungrantable (canManage: false) is hidden because showUsersWithoutAdminOption is false
      expect(find.text('charlie_ungrantable'), findsNothing);
      // connected_agent is hidden because showConnectedUser is false
      expect(find.text('connected_agent'), findsNothing);
    });

    testWidgets('shows connected user when showConnectedUser is true even if showUsersWithoutAdminOption is false', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'connected_agent',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': true,
        'showUngrantableRoles': false,
        'showUsersWithoutAdminOption': false,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        username: 'connected_agent',
        roles: customRoles,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Alice is visible
      expect(find.text('alice'), findsOneWidget);
      // connected_agent (canManage: false) is visible because showConnectedUser is true
      expect(find.text('connected_agent'), findsOneWidget);
      // super_admin is hidden because showSuperusers is false
      expect(find.text('super_admin'), findsNothing);
      // charlie_ungrantable is hidden because showUsersWithoutAdminOption is false
      expect(find.text('charlie_ungrantable'), findsNothing);
    });

    testWidgets('toggling showSuperusers in settings reveals superusers while showUsersWithoutAdminOption is false', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'connected_agent',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': false,
        'showUsersWithoutAdminOption': false,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        username: 'connected_agent',
        roles: customRoles,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Initially super_admin is not visible
      expect(find.text('super_admin'), findsNothing);

      // Open settings menu
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Toggle 'Show Superusers' switch
      final superusersSwitchFinder = find.widgetWithText(SwitchListTile, 'Show Superusers');
      await tester.ensureVisible(superusersSwitchFinder);
      await tester.tap(superusersSwitchFinder);
      await tester.pumpAndSettle();

      // Close settings modal
      final NavigatorState navigator = tester.state(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      // super_admin is now visible while charlie_ungrantable remains hidden
      expect(find.text('super_admin'), findsOneWidget);
      expect(find.text('charlie_ungrantable'), findsNothing);
    });

    testWidgets('toggling showConnectedUser in settings reveals connected user while showUsersWithoutAdminOption is false', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'connected_agent',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': false,
        'showUsersWithoutAdminOption': false,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        username: 'connected_agent',
        roles: customRoles,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Initially connected_agent is not visible
      expect(find.text('connected_agent'), findsNothing);

      // Open settings menu
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Toggle 'Show Connected User' switch
      final connectedUserSwitchFinder = find.widgetWithText(SwitchListTile, 'Show Connected User');
      await tester.ensureVisible(connectedUserSwitchFinder);
      await tester.tap(connectedUserSwitchFinder);
      await tester.pumpAndSettle();

      // Close settings modal
      final NavigatorState navigator = tester.state(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      // connected_agent is now visible while charlie_ungrantable remains hidden
      expect(find.text('connected_agent'), findsOneWidget);
      expect(find.text('charlie_ungrantable'), findsNothing);
    });
  });

  group('Unified Group Row and External Grantor Chips', () {
    testWidgets('shows grantor chips for other grantors on group row and manages current user grant independently', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'dbroles',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': true,
        'showUsersWithoutAdminOption': true,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final aliceRole = PgRole(
        oid: 101,
        name: 'alice',
        canLogin: true,
        isSuperuser: false,
        inherit: true,
        createRole: false,
        createDb: false,
        replication: false,
        bypassRls: false,
        canManage: true,
        canDrop: true,
      );

      final fakeDb = FakeDatabaseService(
        username: 'dbroles',
        roles: [aliceRole],
        mockUserGroups: {
          101: [
            PgUserGroup(
              oid: 301,
              name: 'nl',
              description: 'Netherlands team',
              grantors: ['postgres', 'daniel'],
              grantable: true,
              granted: false,
            ),
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select alice
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Only one row for 'nl' should exist
      expect(find.textContaining('nl'), findsOneWidget);

      // Compact grantor icon should be visible for external grantors after description
      final peopleIconFinder = find.byIcon(Icons.people_outline);
      expect(peopleIconFinder, findsOneWidget);

      // Tooltip should contain all grantors
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: peopleIconFinder, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, contains('Granted by:'));
      expect(tooltip.message, contains('• postgres'));
      expect(tooltip.message, contains('• daniel'));

      // Tapping icon opens grantor detail dialog
      await tester.tap(peopleIconFinder);
      await tester.pumpAndSettle();
      expect(find.text('Role "nl"'), findsOneWidget);
      expect(find.text('Granted by:'), findsOneWidget);
      expect(find.text('postgres'), findsOneWidget);
      expect(find.text('daniel'), findsOneWidget);

      // Close the dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Checkbox is enabled because grantable is true, and initially unchecked because granted is false
      final checkboxFinder = find.byType(CheckboxListTile);
      expect(checkboxFinder, findsOneWidget);
      CheckboxListTile checkbox = tester.widget<CheckboxListTile>(checkboxFinder);
      expect(checkbox.enabled, isTrue);
      expect(checkbox.value, isFalse);

      // Tap checkbox to grant role as dbroles
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      // Checkbox should now be checked, and grantRole called
      checkbox = tester.widget<CheckboxListTile>(checkboxFinder);
      expect(checkbox.value, isTrue);
      expect(fakeDb.grantedRoles, contains('alice:nl'));

      // Icon for other grantors still exists
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
    });

    testWidgets('shows single grantor badge without counter and opens dialog', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'dbroles',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
        'showRolesAsUsers': false,
        'showConnectedUser': false,
        'showUngrantableRoles': true,
        'showUsersWithoutAdminOption': true,
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final aliceRole = PgRole(
        oid: 101,
        name: 'alice',
        canLogin: true,
        isSuperuser: false,
        inherit: true,
        createRole: false,
        createDb: false,
        replication: false,
        bypassRls: false,
        canManage: true,
        canDrop: true,
      );

      final fakeDb = FakeDatabaseService(
        username: 'dbroles',
        roles: [aliceRole],
        mockUserGroups: {
          101: [
            PgUserGroup(
              oid: 301,
              name: 'nl',
              description: 'Netherlands team',
              grantors: ['postgres'],
              grantable: true,
              granted: false,
            ),
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Compact single grantor icon should show person icon
      final personIconFinder = find.byIcon(Icons.person_outline);
      expect(personIconFinder, findsOneWidget);

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: personIconFinder, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, contains('Granted by:'));
      expect(tooltip.message, contains('• postgres'));

      // Tapping icon opens detail dialog
      await tester.tap(personIconFinder);
      await tester.pumpAndSettle();
      expect(find.text('Role "nl"'), findsOneWidget);
      expect(find.text('Granted by:'), findsOneWidget);
      expect(find.text('postgres'), findsWidgets);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });
  });
}


