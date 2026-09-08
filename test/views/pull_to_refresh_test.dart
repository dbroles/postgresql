import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/models/pg_membership.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/views/role_management_widget.dart';
import 'package:user_manager/views/role_manager_home.dart';
import 'package:user_manager/views/role_membership_page.dart';
import 'package:user_manager/views/user_list_widget.dart';

import '../fakes/fake_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final initialRoles = [
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
      'showUngrantableRoles': true,
      'showUngrantableUsers': true,
      'showUsersWithoutAdminOption': true,
    });
  });

  group('Pull-to-refresh on mobile devices', () {
    testWidgets('dragging down on user list triggers refresh and updates users', (WidgetTester tester) async {
      // Set mobile resolution (< 600 width)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        roles: List.from(initialRoles),
        mockClusterName: 'test_cluster',
        mockSslStatus: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );

      await tester.pumpAndSettle();

      // Check initial users
      expect(find.byType(UserListWidget), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('charlie'), findsNothing);

      final initialFetchCalls = fakeDb.fetchAllRolesCalls;

      // Add a new user to the fake DB
      fakeDb.mockRoles.add(
        PgRole(
          oid: 103,
          name: 'charlie',
          canLogin: true,
          isSuperuser: false,
          description: 'New User',
          inherit: true,
          createRole: false,
          createDb: false,
          replication: false,
          bypassRls: false,
          canManage: true,
          canDrop: true,
        ),
      );

      // Verify RefreshIndicator exists
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Drag down on the user list to trigger pull-to-refresh
      await tester.drag(find.text('alice'), const Offset(0, 300));
      await tester.pump(); // Start the scroll animation
      await tester.pump(const Duration(seconds: 1)); // Hold
      await tester.pumpAndSettle(); // Complete refresh

      // Verify fetchAllRoles was called again
      expect(fakeDb.fetchAllRolesCalls, greaterThan(initialFetchCalls));

      // Verify new user appears in the list
      expect(find.text('charlie'), findsOneWidget);
    });

    testWidgets('dragging down on roles list in RoleMembershipPage triggers refresh and updates roles', (WidgetTester tester) async {
      // Set mobile resolution (< 600 width)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        roles: List.from(initialRoles),
        memberships: [
          PgMembership(
            roleOid: 201,
            memberOid: 101, // alice has developers
            grantor: 'test_admin',
            adminOption: false,
            inheritOption: true,
            setOption: false,
          ),
        ],
        mockClusterName: 'test_cluster',
        mockSslStatus: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on alice to navigate to RoleMembershipPage on mobile
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Verify on RoleMembershipPage
      expect(find.byType(RoleMembershipPage), findsOneWidget);
      expect(find.textContaining('developers'), findsOneWidget);
      expect(find.textContaining('analysts'), findsNothing);

      final initialRolesCalls = fakeDb.fetchAllRolesCalls;
      final initialGroupsCalls = fakeDb.fetchGroupsForUserCalls;

      // Add a new role 'analysts' to fake DB
      fakeDb.mockRoles.add(
        PgRole(
          oid: 202,
          name: 'analysts',
          canLogin: false,
          isSuperuser: false,
          description: 'Data Analysts',
          inherit: true,
          createRole: false,
          createDb: false,
          replication: false,
          bypassRls: false,
          canManage: true,
          canDrop: false,
        ),
      );

      // Verify RefreshIndicator is present in RoleManagementWidget
      expect(find.descendant(of: find.byType(RoleMembershipPage), matching: find.byType(RefreshIndicator)), findsOneWidget);

      // Drag down on the role list in RoleMembershipPage to trigger refresh
      await tester.drag(find.textContaining('developers'), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Verify fetch calls were made
      expect(fakeDb.fetchAllRolesCalls, greaterThan(initialRolesCalls));
      expect(fakeDb.fetchGroupsForUserCalls, greaterThan(initialGroupsCalls));

      // Verify the new role 'analysts' now appears in the list!
      expect(find.textContaining('analysts'), findsOneWidget);
    });

    testWidgets('UserListWidget with AlwaysScrollableScrollPhysics allows pull-to-refresh on empty list', (WidgetTester tester) async {
      bool refreshTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserListWidget(
              users: const [],
              onUserSelected: (_) {},
              searchController: TextEditingController(),
              searchQuery: '',
              showFilters: false,
              onAddPressed: () {},
              onRefresh: () async {
                refreshTriggered = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Drag down on the empty list area
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(refreshTriggered, isTrue);
    });

    testWidgets('RoleManagementWidget with AlwaysScrollableScrollPhysics allows pull-to-refresh on empty role list', (WidgetTester tester) async {
      bool refreshTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              user: initialRoles.first,
              groups: const [],
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: TextEditingController(),
              showSystemRoles: false,
              showDescriptions: false,
              showFilters: false,
              currentUsername: 'test_admin',
              onRefresh: () async {
                refreshTriggered = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Drag down on the empty list area
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(refreshTriggered, isTrue);
    });

    testWidgets('refresh button is hidden on mobile devices but visible on desktop even when narrow', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService(
        roles: List.from(initialRoles),
        mockClusterName: 'test_cluster',
        mockSslStatus: true,
      );

      // 1. Mobile platform (e.g. iOS or Android)
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Refresh button should NOT be in the AppBar on mobile devices
      expect(find.byIcon(Icons.refresh), findsNothing);

      // 2. Desktop platform (e.g. macOS) with narrow width
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Refresh button SHOULD be present on desktop even when narrow!
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // 3. Desktop platform with wide width
      tester.view.physicalSize = const Size(1000, 800);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Refresh button should be present on desktop wide as well
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('desktop supports pull-to-refresh via mouse drag with ScrollConfiguration', (WidgetTester tester) async {
      final fakeDb = FakeDatabaseService(
        roles: List.from(initialRoles),
        mockClusterName: 'test_cluster',
        mockSslStatus: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      final initialCalls = fakeDb.fetchAllRolesCalls;

      // Simulate mouse drag down
      await tester.drag(find.text('alice'), const Offset(0, 300), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(fakeDb.fetchAllRolesCalls, greaterThan(initialCalls));
    });

    testWidgets('desktop Refresh button preserves selected user and updates groups when grant is revoked externally', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialMemberships = [
        PgMembership(
          roleOid: 201, // developers
          memberOid: 101, // alice
          grantor: 'daniel',
          adminOption: false,
          inheritOption: true,
          setOption: true,
        ),
      ];

      final fakeDb = FakeDatabaseService(
        roles: List.from(initialRoles),
        memberships: List.from(initialMemberships),
        mockClusterName: 'test_cluster',
        mockSslStatus: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select alice
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Verify RoleManagementWidget is showing developers with grantor badge
      expect(find.byType(RoleManagementWidget), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);

      // External revocation: remove membership granted by daniel
      fakeDb.mockMemberships.clear();

      // Tap AppBar Refresh button
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      // User alice should still be selected
      expect(find.text('User Manager - alice'), findsOneWidget);

      // Grantor icon should now be gone because it was refreshed
      expect(find.byIcon(Icons.person_outline), findsNothing);
    });
  });
}
