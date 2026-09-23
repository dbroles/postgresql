import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/models/pg_user_group.dart';
import 'package:user_manager/views/connection_settings_page.dart';
import 'package:user_manager/views/connection_status_bar.dart';
import 'package:user_manager/views/role_management_widget.dart';
import 'package:user_manager/views/role_manager_home.dart';
import 'package:user_manager/views/role_membership_page.dart';

import '../fakes/fake_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleUser = PgRole(
    oid: 101,
    name: 'alice',
    canLogin: true,
    isSuperuser: true,
    description: 'Lead Admin',
    inherit: true,
    createRole: true,
    createDb: true,
    replication: false,
    bypassRls: true,
    canManage: true,
    canDrop: false,
  );

  final sampleGroups = [
    PgUserGroup(
      oid: 201,
      name: 'developers',
      granted: true,
      grantable: true,
      grantors: [],
    ),
    PgUserGroup(
      oid: 202,
      name: 'analysts',
      granted: false,
      grantable: true,
      grantors: [],
    ),
    PgUserGroup(
      oid: 203,
      name: 'reporters',
      granted: false,
      grantable: true,
      grantors: [],
    ),
  ];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('UX Optimizations: Attribute Balls (No Hover Tooltips)', () {
    testWidgets('attribute balls do not render hover tooltips', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              user: sampleUser,
              groups: sampleGroups,
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: TextEditingController(),
              showSystemRoles: false,
              showDescriptions: true,
              showFilters: false,
              currentUsername: 'alice',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the abbreviation balls are present
      expect(find.text('S'), findsOneWidget);
      expect(find.text('I'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('P'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);

      // Verify NO Tooltip ancestor exists for any attribute ball
      expect(find.ancestor(of: find.text('S'), matching: find.byType(Tooltip)), findsNothing);
      expect(find.ancestor(of: find.text('B'), matching: find.byType(Tooltip)), findsNothing);
    });
  });

  group('UX Optimizations: Segmented Role Filter Chips', () {
    testWidgets('filters roles by All, Assigned, and Available', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              user: sampleUser,
              groups: sampleGroups,
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: TextEditingController(),
              showSystemRoles: false,
              showDescriptions: true,
              showFilters: false,
              currentUsername: 'alice',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify choice chips with counts
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Assigned (1)'), findsOneWidget);
      expect(find.text('Available (2)'), findsOneWidget);

      // Initially All (3) is selected, so developers, analysts, reporters are visible
      expect(find.text('developers'), findsOneWidget);
      expect(find.text('analysts'), findsOneWidget);
      expect(find.text('reporters'), findsOneWidget);

      // Tap Assigned (1)
      await tester.tap(find.text('Assigned (1)'));
      await tester.pumpAndSettle();

      expect(find.text('developers'), findsOneWidget);
      expect(find.text('analysts'), findsNothing);
      expect(find.text('reporters'), findsNothing);

      // Tap Available (2)
      await tester.tap(find.text('Available (2)'));
      await tester.pumpAndSettle();

      expect(find.text('developers'), findsNothing);
      expect(find.text('analysts'), findsOneWidget);
      expect(find.text('reporters'), findsOneWidget);

      // Tap All (3) again
      await tester.tap(find.text('All (3)'));
      await tester.pumpAndSettle();

      expect(find.text('developers'), findsOneWidget);
      expect(find.text('analysts'), findsOneWidget);
      expect(find.text('reporters'), findsOneWidget);
    });
  });

  group('UX Optimizations: Interactive ConnectionStatusBar', () {
    testWidgets('tapping ConnectionStatusBar navigates to ConnectionSettingsPage', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'dbroles',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': false,
      });

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockClusterName: 'cluster_test',
        mockSslStatus: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );

      await tester.pumpAndSettle();

      // Verify status bar exists and is interactive
      expect(find.byType(ConnectionStatusBar), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // Tap status bar
      await tester.tap(find.byType(ConnectionStatusBar));
      await tester.pumpAndSettle();

      // Should have opened ConnectionSettingsPage
      expect(find.byType(ConnectionSettingsPage), findsOneWidget);
    });

    testWidgets('ConnectionStatusBar respects bottom safe area insets', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 34, left: 10, right: 10),
            ),
            child: Scaffold(
              bottomNavigationBar: ConnectionStatusBar(
                host: 'db.example.com',
                isSslEnabled: true,
              ),
            ),
          ),
        ),
      );

      expect(find.descendant(
        of: find.byType(ConnectionStatusBar),
        matching: find.byType(SafeArea),
      ), findsOneWidget);

      final safeAreaFinder = find.descendant(
        of: find.byType(ConnectionStatusBar),
        matching: find.byType(SafeArea),
      );
      final safeAreaWidget = tester.widget<SafeArea>(safeAreaFinder);
      expect(safeAreaWidget.top, isFalse);
      expect(safeAreaWidget.bottom, isTrue);
    });

    testWidgets('ConnectionStatusBar SSL icon uses theme primary color when enabled and amber when disabled', (WidgetTester tester) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF88AA00)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            bottomNavigationBar: ConnectionStatusBar(
              host: 'db.example.com',
              isSslEnabled: true,
            ),
          ),
        ),
      );

      final lockIcon = tester.widget<Icon>(find.byIcon(Icons.lock));
      expect(lockIcon.color, theme.colorScheme.primary);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            bottomNavigationBar: ConnectionStatusBar(
              host: 'db.example.com',
              isSslEnabled: false,
            ),
          ),
        ),
      );

      final lockOpenIcon = tester.widget<Icon>(find.byIcon(Icons.lock_open));
      expect(lockOpenIcon.color, Colors.amber.shade700);
    });
  });

  group('UX Optimizations: Keyboard Shortcuts', () {
    testWidgets('Escape hides filters if visible, and Cmd+F displays filters with active cursor', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'dbroles',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': true,
        'showDescriptions': true,
        'showFilters': true,
      });

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockClusterName: 'cluster_test',
        mockSslStatus: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );

      await tester.pumpAndSettle();

      // Filters are initially visible
      final searchFieldFinder = find.widgetWithText(TextField, 'Filter users...');
      expect(searchFieldFinder, findsOneWidget);

      // Enter search text
      await tester.enterText(searchFieldFinder, 'test_query');
      await tester.pumpAndSettle();
      expect(find.text('test_query'), findsOneWidget);

      // Pressing Escape should hide the filters completely
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Filters should now be hidden
      expect(find.widgetWithText(TextField, 'Filter users...'), findsNothing);

      // Pressing Cmd+F should display filters and activate cursor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      // Filters should now be visible again
      expect(find.widgetWithText(TextField, 'Filter users...'), findsOneWidget);

      // Verify the search field has focus (active cursor)
      final textField = tester.widget<TextField>(find.widgetWithText(TextField, 'Filter users...'));
      expect(textField.focusNode?.hasFocus, isTrue);
    });

    testWidgets('Cmd+F and Esc work repeatedly, including when a user is selected (wide layout)', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'dbroles',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': true,
        'showDescriptions': true,
        'showFilters': false,
      });

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockUserGroups: {sampleUser.oid: sampleGroups},
        mockClusterName: 'cluster_test',
        mockSslStatus: false,
      );

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Initially filters hidden
      expect(find.widgetWithText(TextField, 'Filter users...'), findsNothing);

      // 1. Press Cmd+F -> shows filters & activates cursor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter users...'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Filter users...')).focusNode?.hasFocus, isTrue);

      // 2. Press Esc -> hides filters
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Filter users...'), findsNothing);

      // 3. Select a user in the list
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Right pane is now showing role management for alice
      expect(find.text('alice'), findsWidgets);

      // 4. Press Cmd+F while user is selected -> shows filters and activates cursor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter users...'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Filter roles...'), findsOneWidget);
      // User search field has focus
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Filter users...')).focusNode?.hasFocus, isTrue);

      // 5. Press Cmd+F again while user is selected -> toggles focus to role search field
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Filter roles...')).focusNode?.hasFocus, isTrue);

      // 6. Press Esc while focused on role search -> hides filters
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter users...'), findsNothing);
      expect(find.widgetWithText(TextField, 'Filter roles...'), findsNothing);

      // 7. Press Cmd+F AGAIN -> shows filters again repeatedly
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter users...'), findsOneWidget);

      // 8. Press Esc AGAIN -> hides filters repeatedly
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter users...'), findsNothing);
    });

    testWidgets('Cmd+F and Esc work in RoleMembershipPage (narrow layout)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final roleSearchController = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleMembershipPage(
              user: sampleUser,
              groups: sampleGroups,
              onToggleRole: (_, _) async {},
              roleSearchController: roleSearchController,
              showSystemRoles: false,
              showDescriptions: true,
              showFilters: false,
              currentUsername: 'alice',
              isDeletable: false,
              onDeletePressed: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially filters hidden
      expect(find.widgetWithText(TextField, 'Filter roles...'), findsNothing);

      // 1. Press Cmd+F in RoleMembershipPage -> shows filters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter roles...'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Filter roles...')).focusNode?.hasFocus, isTrue);

      // 2. Press Esc -> hides filters
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter roles...'), findsNothing);

      // 3. Press Cmd+F again -> shows filters again
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Filter roles...'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Filter roles...')).focusNode?.hasFocus, isTrue);
    });
  });

  group('UX Optimizations: Filter by Description', () {
    testWidgets('RoleManagementWidget filters roles by description when showDescriptions is true', (WidgetTester tester) async {
      final roleSearchController = TextEditingController();
      final groups = [
        PgUserGroup(
          oid: 301,
          name: 'grp_finance',
          description: 'Accounting and Financial Reports',
          granted: false,
          grantable: true,
          grantors: [],
        ),
        PgUserGroup(
          oid: 302,
          name: 'grp_eng',
          description: 'Software Engineering Team',
          granted: false,
          grantable: true,
          grantors: [],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              user: sampleUser,
              groups: groups,
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: roleSearchController,
              showSystemRoles: false,
              showDescriptions: true,
              showFilters: true,
              currentUsername: 'alice',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both initially visible
      expect(find.textContaining('grp_finance'), findsOneWidget);
      expect(find.textContaining('grp_eng'), findsOneWidget);

      // Search by description keyword 'accounting'
      roleSearchController.text = 'accounting';
      await tester.pumpAndSettle();

      expect(find.textContaining('grp_finance'), findsOneWidget);
      expect(find.textContaining('grp_eng'), findsNothing);
    });

    testWidgets('RoleManagementWidget does NOT filter by description when showDescriptions is false', (WidgetTester tester) async {
      final roleSearchController = TextEditingController();
      final groups = [
        PgUserGroup(
          oid: 301,
          name: 'grp_finance',
          description: 'Accounting and Financial Reports',
          granted: false,
          grantable: true,
          grantors: [],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              user: sampleUser,
              groups: groups,
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: roleSearchController,
              showSystemRoles: false,
              showDescriptions: false,
              showFilters: true,
              currentUsername: 'alice',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('grp_finance'), findsOneWidget);

      // Search by description keyword 'accounting' when descriptions are disabled
      roleSearchController.text = 'accounting';
      await tester.pumpAndSettle();

      expect(find.textContaining('grp_finance'), findsNothing);
    });

    testWidgets('RoleManagerHome filters users by description when showDescriptions is true', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'showDescriptions': true,
        'showFilters': true,
      });

      final fakeDb = FakeDatabaseService(
        roles: [
          PgRole(
            oid: 101,
            name: 'usr_sec',
            description: 'Security Auditor',
            canLogin: true,
            isAdmin: true,
            canDrop: true,
          ),
          PgRole(
            oid: 102,
            name: 'usr_ops',
            description: 'Cloud Operations',
            canLogin: true,
            isAdmin: true,
            canDrop: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('usr_sec'), findsOneWidget);
      expect(find.text('usr_ops'), findsOneWidget);

      // Filter by description
      await tester.enterText(find.widgetWithText(TextField, 'Filter users...'), 'security');
      await tester.pumpAndSettle();

      expect(find.text('usr_sec'), findsOneWidget);
      expect(find.text('usr_ops'), findsNothing);
    });

    testWidgets('RoleManagerHome does NOT filter users by description when showDescriptions is false', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'showDescriptions': false,
        'showFilters': true,
      });

      final fakeDb = FakeDatabaseService(
        roles: [
          PgRole(
            oid: 101,
            name: 'usr_sec',
            description: 'Security Auditor',
            canLogin: true,
            isAdmin: true,
            canDrop: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('usr_sec'), findsOneWidget);

      // Filter by description when showDescriptions is false
      await tester.enterText(find.widgetWithText(TextField, 'Filter users...'), 'security');
      await tester.pumpAndSettle();

      expect(find.text('usr_sec'), findsNothing);
    });
  });
}
