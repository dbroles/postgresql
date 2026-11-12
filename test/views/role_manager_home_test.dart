import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/main.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/models/pg_user_group.dart';
import 'package:user_manager/views/connection_settings_page.dart';
import 'package:user_manager/views/connection_status_bar.dart';
import 'package:user_manager/views/create_user_dialog.dart';
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
      expect(fakeDb.canCurrentUserCreateRoleCalls, 1);
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

      // Verify ConnectionStatusBar shows cluster name and SSL lock icon
      expect(find.byType(ConnectionStatusBar), findsOneWidget);
      expect(find.byIcon(Icons.dns), findsOneWidget);
      expect(find.textContaining('prod_cluster_01'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
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

  group('Ungrantable Roles Are Permanently Hidden', () {
    testWidgets('permanently hides ungrantable roles and does not show visibility toggles in settings', (WidgetTester tester) async {
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

      // finance_restricted (canManage: false) is permanently hidden
      expect(find.textContaining('finance_restricted'), findsNothing);

      // Open settings menu and verify removed visibility switches are absent
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SwitchListTile, 'Show Ungrantable Roles'), findsNothing);
      expect(find.widgetWithText(SwitchListTile, 'Show System Roles'), findsNothing);
      expect(find.widgetWithText(SwitchListTile, 'Show Superusers'), findsNothing);
      expect(find.widgetWithText(SwitchListTile, 'Show Connected User'), findsNothing);
      expect(find.widgetWithText(SwitchListTile, 'Show Filters'), findsNothing);
      expect(find.widgetWithText(SwitchListTile, 'Show Descriptions'), findsOneWidget);
    });
  });

  group('Users Without Admin Option Are Permanently Hidden', () {
    testWidgets('permanently hides users without admin option and does not show toggle in settings', (WidgetTester tester) async {
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

      // charlie (isAdmin: false) is permanently hidden
      expect(find.text('charlie'), findsNothing);

      // Open settings menu and verify 'Show Users Without Admin' does not exist
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SwitchListTile, 'Show Users Without Admin'), findsNothing);
    });
  });

  group('Delete User Button Visibility on Desktop', () {
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
      expect(find.byTooltip('Delete User'), findsNothing);

      // Select deletable user 'alice'
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Delete button must be visible in AppBar on desktop
      expect(find.byTooltip('Delete User'), findsOneWidget);
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
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final rolesWithNonDeletable = [
        ...sampleRoles,
        PgRole(
          oid: 104,
          name: 'dave_createdb',
          canLogin: true,
          isSuperuser: false,
          inherit: true,
          createRole: false,
          createDb: true,
          replication: false,
          bypassRls: false,
          canManage: true,
          canDrop: true,
        ),
      ];
      final fakeDb = FakeDatabaseService(roles: rolesWithNonDeletable);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select visible non-deletable user 'dave_createdb' (has elevated createDb attribute)
      await tester.tap(find.text('dave_createdb'));
      await tester.pumpAndSettle();

      // Delete button must NOT be visible
      expect(find.byTooltip('Delete User'), findsNothing);
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
      await tester.tap(find.byTooltip('Delete User'));
      await tester.pumpAndSettle();

      //Confirmation dialog should be displayed
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Delete User'), findsOneWidget);
      expect(find.text('Are you sure you want to delete the user "alice"? This action cannot be undone.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('hides delete button when user has external grantor on an ungrantable role', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Role 202 ('finance_restricted') is NOT managed by test_user (canManage: false),
      // and was granted to alice (oid: 101) by another admin ('finance_admin').
      final fakeDb = FakeDatabaseService(
        username: 'test_user',
        roles: sampleRoles,
        memberships: [
          (
            roleOid: 202,
            memberOid: 101,
            grantor: 'finance_admin',
            adminOption: false,
            inheritOption: true,
            setOption: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Even though finance_restricted is hidden from the role list, SQL can_drop is false
      expect(find.byTooltip('Delete User'), findsNothing);
    });

    testWidgets('mobile RoleMembershipPage updates Delete User button visibility on pull-to-refresh', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        username: 'test_user',
        roles: List.of(sampleRoles),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Open alice on mobile -> Delete User is initially visible
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete User'), findsOneWidget);

      // Another admin grants a role to alice in the background -> canDrop becomes false
      fakeDb.mockMemberships = [
        (
          roleOid: 202,
          memberOid: 101,
          grantor: 'finance_admin',
          adminOption: false,
          inheritOption: true,
          setOption: true,
        ),
      ];

      // Pull to refresh on RoleMembershipPage
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      // Delete User button is now hidden
      expect(find.byTooltip('Delete User'), findsNothing);
    });
  });

  group('Superusers and Connected User Are Permanently Hidden', () {
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
        canManage: true,
        canDrop: false,
      ),
      PgRole(
        oid: 103,
        name: 'connected_agent',
        canLogin: true,
        isSuperuser: false,
        isCurrent: true,
        inherit: true,
        createRole: false,
        createDb: false,
        replication: false,
        bypassRls: false,
        canManage: true,
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

    testWidgets('permanently hides superusers, connected user, and non-admin users', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'connected_agent',
        'db_pass': '',
        'showDescriptions': true,
        'showFilters': false,
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

      // Alice (canManage: true, !isSuperuser, !isCurrent) is visible
      expect(find.text('alice'), findsOneWidget);
      // super_admin, connected_agent, and charlie_ungrantable are permanently hidden
      expect(find.text('super_admin'), findsNothing);
      expect(find.text('connected_agent'), findsNothing);
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

  group('Create Role FAB Visibility', () {
    testWidgets('FAB is visible when user has createrole rights', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: true,
        roles: [
          PgRole(oid: 10, name: 'alice', canLogin: true),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('FAB is hidden when user lacks createrole rights', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: false,
        roles: [
          PgRole(oid: 10, name: 'alice', canLogin: true),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('FAB disappears after refresh when createrole is revoked', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService(
        roles: [
          PgRole(oid: 10, name: 'admin_user', canLogin: true, isCurrent: true, createRole: true),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Superuser runs ALTER ROLE ... NOCREATEROLE
      fakeDb.mockRoles = [
        PgRole(oid: 10, name: 'admin_user', canLogin: true, isCurrent: true, createRole: false),
      ];

      final refreshButton = find.byTooltip('Refresh');
      expect(refreshButton, findsOneWidget);
      await tester.tap(refreshButton);
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('AppBar Search Toggle & Theme Mode Setting', () {
    testWidgets('AppBar Search button toggles search filters on and off', (tester) async {
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

      // Initially filters are hidden
      expect(find.widgetWithText(TextField, 'Filter users...'), findsNothing);
      expect(find.byTooltip('Search'), findsOneWidget);

      // Tap Search button in AppBar -> shows filters
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter users...'), findsOneWidget);
      expect(find.byTooltip('Hide Filters'), findsOneWidget);

      // Tap Hide Filters button in AppBar -> hides filters
      await tester.tap(find.byTooltip('Hide Filters'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter users...'), findsNothing);
      expect(find.byTooltip('Search'), findsOneWidget);
    });

    testWidgets('Theme SegmentedButton in Settings switches theme mode and persists to SharedPreferences', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        appThemeModeNotifier.value = ThemeMode.system;
      });

      final fakeDb = FakeDatabaseService(roles: sampleRoles);

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      expect(appThemeModeNotifier.value, ThemeMode.system);

      // Open settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Tap Dark segment
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themeMode'), 'dark');
      expect(appThemeModeNotifier.value, ThemeMode.dark);

      // Tap Light segment
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(prefs.getString('themeMode'), 'light');
      expect(appThemeModeNotifier.value, ThemeMode.light);
    });
  });

  group('CreateUserDialog Valid Until Date Picker', () {
    testWidgets('uses Material showDatePicker on Android/Windows/Linux, allows clearing and saving', (tester) async {
      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: true,
        roles: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: CreateUserDialog(dbService: fakeDb),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Valid Until field is visible and initially empty
      final validUntilField = find.widgetWithText(TextFormField, 'Valid Until');
      expect(validUntilField, findsOneWidget);

      // Tap Valid Until field to open Material DatePickerDialog
      await tester.tap(validUntilField);
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);

      // Confirm default date (today)
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final expectedToday = PgRole.formatDate(now);
      expect(find.text(expectedToday), findsOneWidget);

      // Clear button is now shown; tap it to clear the date
      final clearButton = find.byTooltip('Clear date');
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();
      expect(find.text(expectedToday), findsNothing);

      // Pick the date again and create the user
      await tester.tap(validUntilField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'dave');
      await tester.tap(find.text('Create User'));
      await tester.pumpAndSettle();

      expect(fakeDb.mockRoles.length, 1);
      expect(fakeDb.mockRoles.first.name, 'dave');
      expect(fakeDb.mockRoles.first.validUntilDateString, expectedToday);
    });

    testWidgets('uses CupertinoDatePicker on macOS and iOS', (tester) async {
      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: true,
        roles: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: CreateUserDialog(dbService: fakeDb),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final validUntilField = find.widgetWithText(TextFormField, 'Valid Until');
      await tester.tap(validUntilField);
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.widgetWithText(CupertinoButton, 'Done'), findsOneWidget);
      expect(find.widgetWithText(CupertinoButton, 'Cancel'), findsOneWidget);

      await tester.tap(find.widgetWithText(CupertinoButton, 'Done'));
      await tester.pumpAndSettle();

      final expectedToday = PgRole.formatDate(DateTime.now());
      expect(find.text(expectedToday), findsOneWidget);
    });

    testWidgets('pre-populates fields when initialUser is provided', (tester) async {
      final fakeDb = FakeDatabaseService();
      final existingUser = PgRole(
        oid: 500,
        name: 'contractor',
        description: 'Temp access',
        validUntil: DateTime(2028, 1, 15),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateUserDialog(
              dbService: fakeDb,
              initialUser: existingUser,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('contractor'), findsOneWidget);
      expect(find.text('Temp access'), findsOneWidget);
      expect(find.text('2028-01-15'), findsOneWidget);
    });

    testWidgets('Expire Now / +30 / +90 / +365 chips set target dates and Expire Now marks user expired', (tester) async {
      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: true,
        roles: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateUserDialog(dbService: fakeDb),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final plus30 = DateTime(today.year, today.month, today.day + 30);
      final plus90 = DateTime(today.year, today.month, today.day + 90);
      final plus365 = DateTime(today.year, today.month, today.day + 365);

      // Verify all 4 chips exist and are aligned on a single row
      expect(find.widgetWithText(ChoiceChip, 'Expire Now'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '+30'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '+90'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '+365'), findsOneWidget);

      final expireNowTop = tester.getTopLeft(find.widgetWithText(ChoiceChip, 'Expire Now')).dy;
      final plus30Top = tester.getTopLeft(find.widgetWithText(ChoiceChip, '+30')).dy;
      final plus90Top = tester.getTopLeft(find.widgetWithText(ChoiceChip, '+90')).dy;
      final plus365Top = tester.getTopLeft(find.widgetWithText(ChoiceChip, '+365')).dy;
      expect(expireNowTop, equals(plus30Top));
      expect(plus30Top, equals(plus90Top));
      expect(plus90Top, equals(plus365Top));

      // Tap +30
      await tester.tap(find.widgetWithText(ChoiceChip, '+30'));
      await tester.pumpAndSettle();
      expect(find.text(PgRole.formatDate(plus30)), findsOneWidget);

      // Tap +90
      await tester.tap(find.widgetWithText(ChoiceChip, '+90'));
      await tester.pumpAndSettle();
      expect(find.text(PgRole.formatDate(plus90)), findsOneWidget);

      // Tap +365
      await tester.tap(find.widgetWithText(ChoiceChip, '+365'));
      await tester.pumpAndSettle();
      expect(find.text(PgRole.formatDate(plus365)), findsOneWidget);

      // Tap Expire Now -> sets today (00:00:00), which is already expired
      await tester.tap(find.widgetWithText(ChoiceChip, 'Expire Now'));
      await tester.pumpAndSettle();
      expect(find.text(PgRole.formatDate(today)), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'locked_user');
      await tester.tap(find.text('Create User'));
      await tester.pumpAndSettle();

      expect(fakeDb.mockRoles.length, 1);
      final created = fakeDb.mockRoles.first;
      expect(created.name, 'locked_user');
      expect(created.validUntilDateString, PgRole.formatDate(today));
      expect(created.isValid, isFalse);
    });

    testWidgets('Password generator populates strong password and Copy Credentials copies formatted summary and URI', (tester) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final args = methodCall.arguments as Map<dynamic, dynamic>;
            copiedText = args['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final fakeDb = FakeDatabaseService(
        host: 'db.example.com',
        port: 5433,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateUserDialog(dbService: fakeDb),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'karen');

      // Tap Generate password button
      final generateBtn = find.byTooltip('Generate password');
      expect(generateBtn, findsOneWidget);
      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      // Verify password field is populated with a 16-char password and un-obscured
      final passField = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Password'),
          matching: find.byType(TextField),
        ),
      );
      final generatedPassword = passField.controller!.text;
      expect(generatedPassword.length, 16);
      expect(passField.obscureText, isFalse);

      // Select +30 days
      await tester.tap(find.widgetWithText(ChoiceChip, '+30'));
      await tester.pumpAndSettle();

      // Tap Copy Credentials
      final copyBtn = find.text('Copy Credentials');
      expect(copyBtn, findsOneWidget);
      await tester.ensureVisible(copyBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(copiedText, isNotNull);
      final lines = copiedText!.split('\n');
      // First line is YYYY-MM-DD HH:MM:SS
      expect(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(lines[0]), isTrue);
      expect(copiedText, contains('Host: db.example.com'));
      expect(copiedText, contains('Port: 5433'));
      expect(copiedText, contains('Username: karen'));
      expect(copiedText, contains('Password: $generatedPassword'));
      final now = DateTime.now();
      final plus30 = DateTime(now.year, now.month, now.day + 30);
      expect(copiedText, contains('Valid Until: ${PgRole.formatDate(plus30)}'));
      final encodedPass = Uri.encodeComponent(generatedPassword);
      expect(
        copiedText,
        contains('URI: postgresql://karen:$encodedPass@db.example.com:5433/postgres'),
      );
      expect(find.text('Onboarding credentials copied to clipboard.'), findsOneWidget);
    });
  });

  group('Edit User Button Visibility and Flow (Desktop & Mobile)', () {
    testWidgets('desktop: Edit User button is visible when CREATEROLE is true and updates user', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        username: 'test_admin',
        canCreateRoleResult: true,
        roles: List.of(sampleRoles),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no user selected -> no Edit User button
      expect(find.byTooltip('Edit User'), findsNothing);

      // Select alice (isAdmin: true) -> Edit User button is visible
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      final editButton = find.byTooltip('Edit User');
      expect(editButton, findsOneWidget);

      // Tap Edit User button to open CreateUserDialog in edit mode
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      expect(find.text('Edit User'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      // Update username and description
      await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'alice_updated');
      await tester.enterText(find.widgetWithText(TextFormField, 'Description'), 'Senior Dev User');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('User Manager - alice_updated'), findsOneWidget);
      expect(find.text('Senior Dev User'), findsWidgets);
    });

    testWidgets('desktop: Edit User button is hidden when connected user lacks CREATEROLE', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: false,
        roles: List.of(sampleRoles),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit User'), findsNothing);
    });

    testWidgets('mobile: Edit User button is visible on RoleMembershipPage when CREATEROLE and ADMIN are true', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
      });

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        username: 'test_admin',
        canCreateRoleResult: true,
        roles: List.of(sampleRoles),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      final editButton = find.byTooltip('Edit User');
      expect(editButton, findsOneWidget);

      await tester.tap(editButton);
      await tester.pumpAndSettle();
      expect(find.text('Edit User'), findsOneWidget);
    });
  });

  group('Duplicate User Action (AppBar, Desktop & Mobile)', () {
    testWidgets('CreateUserDialog in duplicate mode pre-fills values, shows roles, and grants on duplicate', (tester) async {
      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: true,
        roles: [
          PgRole(
            oid: 1,
            name: 'test_user',
            canLogin: true,
            isCurrent: true,
            createRole: true,
            createDb: false,
            replication: false,
            bypassRls: false,
          ),
        ],
      );

      final sourceUser = PgRole(
        oid: 101,
        name: 'alice',
        description: 'Developer Account',
        canLogin: true,
        inherit: true,
        createRole: true,
        createDb: true,
        replication: true,
        bypassRls: true,
        validUntil: DateTime(2027, 1, 1),
      );

      final groups = [
        PgUserGroup(
          oid: 201,
          name: 'developers',
          description: 'Dev role',
          grantors: [],
          grantable: true,
          granted: true,
        ),
        PgUserGroup(
          oid: 202,
          name: 'managers',
          description: 'Management role',
          grantors: [],
          grantable: false,
          granted: true,
        ),
        PgUserGroup(
          oid: 203,
          name: 'qa',
          description: 'QA role',
          grantors: [],
          grantable: true,
          granted: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreateUserDialog(
              dbService: fakeDb,
              initialUser: sourceUser,
              isDuplicate: true,
              rolesToCopy: groups,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Duplicate User'), findsWidgets);
      expect(find.text('alice_copy'), findsOneWidget);
      expect(find.text('Developer Account'), findsOneWidget);
      expect(find.text('2027-01-01'), findsOneWidget);

      // Only granted roles appear in "Copy Assigned Roles" (developers & managers, but not qa)
      expect(find.text('Copy Assigned Roles'), findsOneWidget);
      expect(find.text('developers'), findsOneWidget);
      expect(find.text('managers'), findsOneWidget);
      expect(find.text('qa'), findsNothing);

      // Tap Duplicate User button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Duplicate User'));
      await tester.pumpAndSettle();

      final newRole = fakeDb.mockRoles.firstWhere((r) => r.name == 'alice_copy');
      expect(newRole.name, 'alice_copy');
      expect(newRole.description, 'Developer Account');
      expect(newRole.isSuperuser, isFalse);
      expect(newRole.createRole, isTrue); // Connected user has createRole
      expect(newRole.createDb, isFalse); // Connected user lacks createDb -> not copied
      expect(newRole.replication, isFalse); // Connected user lacks replication -> not copied
      expect(newRole.bypassRls, isFalse); // Connected user lacks bypassRls -> not copied
      // developers was grantable and selected, so grantRole was called
      expect(fakeDb.grantedRoles.contains('alice_copy:developers'), isTrue);
    });

    testWidgets('desktop: Duplicate User button is visible when user is selected and CREATEROLE is true', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: true,
        roles: List.of(sampleRoles),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no user selected -> no Duplicate User button
      expect(find.byTooltip('Duplicate User'), findsNothing);

      // Select alice -> Duplicate User button is visible
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      final duplicateBtn = find.byTooltip('Duplicate User');
      expect(duplicateBtn, findsOneWidget);

      // Tap Duplicate User
      await tester.tap(duplicateBtn);
      await tester.pumpAndSettle();

      expect(find.text('Duplicate User'), findsWidgets);
      expect(find.text('alice_copy'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Duplicate User'));
      await tester.pumpAndSettle();

      // Newly duplicated user is selected and added
      expect(find.text('User Manager - alice_copy'), findsOneWidget);
      expect(find.text('alice_copy'), findsWidgets);
    });

    testWidgets('desktop: Duplicate User button is hidden when connected user lacks CREATEROLE', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: false,
        roles: List.of(sampleRoles),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Duplicate User'), findsNothing);
    });

    testWidgets('mobile: Duplicate User button is visible on RoleMembershipPage and duplicates user', (tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
      });

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: true,
        roles: List.of(sampleRoles),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      final duplicateBtn = find.byTooltip('Duplicate User');
      expect(duplicateBtn, findsOneWidget);

      await tester.tap(duplicateBtn);
      await tester.pumpAndSettle();

      expect(find.text('Duplicate User'), findsWidgets);
      expect(find.text('alice_copy'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Duplicate User'));
      await tester.pumpAndSettle();

      // Returns to list and shows new user
      expect(find.text('alice_copy'), findsOneWidget);
    });
  });
}


