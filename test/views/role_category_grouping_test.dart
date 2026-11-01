import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/models/pg_user_group.dart';
import 'package:user_manager/views/role_management_widget.dart';
import 'package:user_manager/views/role_manager_home.dart';

import '../fakes/fake_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleUser = PgRole(
    oid: 101,
    name: 'alice',
    canLogin: true,
    isSuperuser: false,
    description: 'Dev User',
    canManage: true,
    canDrop: true,
  );

  // Ordered as returned by PostgreSQL: LOWER(category) ASC NULLS LAST, LOWER(name) ASC
  final categorizedGroups = [
    PgUserGroup(
      oid: 201,
      name: 'adm',
      category: 'department',
      granted: true,
      grantable: true,
      grantors: [],
    ),
    PgUserGroup(
      oid: 202,
      name: 'hr',
      category: 'department',
      granted: false,
      grantable: true,
      grantors: [],
    ),
    PgUserGroup(
      oid: 203,
      name: 'mktg',
      category: 'department',
      granted: false,
      grantable: true,
      grantors: [],
    ),
    PgUserGroup(
      oid: 204,
      name: 'bel',
      category: 'policy',
      granted: false,
      grantable: true,
      grantors: [],
    ),
    PgUserGroup(
      oid: 205,
      name: 'nld',
      category: 'policy',
      granted: true,
      grantable: true,
      grantors: [],
    ),
    PgUserGroup(
      oid: 206,
      name: 'usa',
      category: 'policy',
      granted: false,
      grantable: true,
      grantors: [],
    ),
    PgUserGroup(
      oid: 207,
      name: 'legacy_role',
      category: null,
      granted: false,
      grantable: true,
      grantors: [],
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
      'showFilters': true,
    });
  });

  group('PgUserGroup Model Category Support', () {
    test('fromRow parses category from column index 6 and trims whitespace', () {
      final rowWithCategory = [201, 'nld', 'Netherlands policy', <String>[], true, false, ' policy '];
      final group = PgUserGroup.fromRow(rowWithCategory);
      expect(group.category, 'policy');

      final rowWithEmptyCategory = [202, 'bel', null, <String>[], true, false, '   '];
      final groupEmpty = PgUserGroup.fromRow(rowWithEmptyCategory);
      expect(groupEmpty.category, isNull);

      final rowWithoutCategoryCol = [203, 'usa', null, <String>[], true, false];
      final groupLegacy = PgUserGroup.fromRow(rowWithoutCategoryCol);
      expect(groupLegacy.category, isNull);
    });

    test('copyWith updates and clears category', () {
      final group = PgUserGroup(
        oid: 1,
        name: 'hr',
        grantors: [],
        grantable: true,
        granted: false,
        category: 'department',
      );

      final updated = group.copyWith(category: 'org_unit');
      expect(updated.category, 'org_unit');

      final cleared = updated.copyWith(clearCategory: true);
      expect(cleared.category, isNull);
    });
  });

  group('Collapsible Category Sections in RoleManagementWidget', () {
    testWidgets('renders category headers with counts and collapses/expands on tap', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              user: sampleUser,
              groups: categorizedGroups,
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: TextEditingController(),
              showSystemRoles: false,
              showDescriptions: true,
              showFilters: false,
              currentUsername: 'test_admin',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify category headers are shown
      expect(find.byKey(const ValueKey('category_header_department')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_header_policy')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_header___ungrouped__')), findsOneWidget);

      expect(find.text('department'), findsOneWidget);
      expect(find.text('policy'), findsOneWidget);
      expect(find.text('Ungrouped'), findsOneWidget);

      // Verify assigned/total counts in headers (1/3 for department, 1/3 for policy, 0/1 for Ungrouped)
      expect(find.text('1 / 3'), findsNWidgets(2));
      expect(find.text('0 / 1'), findsOneWidget);

      // Roles inside 'department' are initially visible
      expect(find.textContaining('adm'), findsOneWidget);
      expect(find.textContaining('hr'), findsOneWidget);
      expect(find.textContaining('mktg'), findsOneWidget);

      // Collapse 'department' section
      await tester.tap(find.byKey(const ValueKey('category_header_department')));
      await tester.pumpAndSettle();

      expect(find.textContaining('adm'), findsNothing);
      expect(find.textContaining('hr'), findsNothing);
      expect(find.textContaining('mktg'), findsNothing);
      // 'policy' roles remain visible
      expect(find.textContaining('nld'), findsOneWidget);

      // Expand 'department' section again
      await tester.tap(find.byKey(const ValueKey('category_header_department')));
      await tester.pumpAndSettle();

      expect(find.textContaining('adm'), findsOneWidget);
      expect(find.textContaining('hr'), findsOneWidget);
      expect(find.textContaining('mktg'), findsOneWidget);
    });

    testWidgets('search filter matches category name as well as role name', (WidgetTester tester) async {
      final searchController = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              user: sampleUser,
              groups: categorizedGroups,
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: searchController,
              showSystemRoles: false,
              showDescriptions: true,
              showFilters: true,
              currentUsername: 'test_admin',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      searchController.text = 'policy';
      await tester.pumpAndSettle();

      expect(find.textContaining('bel'), findsOneWidget);
      expect(find.textContaining('nld'), findsOneWidget);
      expect(find.textContaining('usa'), findsOneWidget);
      expect(find.textContaining('hr'), findsNothing);
      expect(find.textContaining('legacy_role'), findsNothing);
    });

    testWidgets('edits role category via EditRoleCategoryDialog and updates grouping', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': true,
        'showEditCategoryButton': true,
      });

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockUserGroups: {sampleUser.oid: categorizedGroups},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select user 'alice'
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Tap the 'Set category' button on the ungrouped 'legacy_role'
      final setCategoryButton = find.byTooltip('Set category');
      expect(setCategoryButton, findsOneWidget);
      await tester.tap(setCategoryButton);
      await tester.pumpAndSettle();

      // Dialog should open with existing categories as ChoiceChips
      expect(find.text('Category for "legacy_role"'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'department'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'policy'), findsOneWidget);

      // Select 'policy' suggestion chip and save
      await tester.tap(find.widgetWithText(ChoiceChip, 'policy'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      // Verify FakeDatabaseService recorded the category change
      expect(fakeDb.roleCategories['legacy_role'], 'policy');
      // 'Ungrouped' header should no longer appear since all roles now have categories
      expect(find.text('Ungrouped'), findsNothing);
    });

    testWidgets('hides category edit buttons and settings toggle when user lacks dbroles.category SET privilege', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockUserGroups: {sampleUser.oid: categorizedGroups},
        canSetCategoryParameterResult: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select user 'alice'
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // Category headers are still visible
      expect(find.text('department'), findsOneWidget);
      expect(find.text('policy'), findsOneWidget);

      // Edit category buttons must NOT be visible
      expect(find.byTooltip('Set category'), findsNothing);
      expect(find.byIcon(Icons.label), findsNothing);
      expect(find.byIcon(Icons.label_outline), findsNothing);

      // Open Settings modal -> 'Show Category Edit' switch should NOT be shown
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SwitchListTile, 'Show Category Edit'), findsNothing);
    });

    testWidgets('Show Category Edit defaults to false and toggles button visibility when privilege is granted', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockUserGroups: {sampleUser.oid: categorizedGroups},
        canSetCategoryParameterResult: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Select user 'alice'
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      // By default (false), edit buttons are hidden
      expect(find.byTooltip('Set category'), findsNothing);
      expect(find.byIcon(Icons.label), findsNothing);
      expect(find.byIcon(Icons.label_outline), findsNothing);

      // Open Settings modal -> toggle 'Show Category Edit' ON
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      final toggleFinder = find.widgetWithText(SwitchListTile, 'Show Category Edit');
      expect(toggleFinder, findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggleFinder).value, isFalse);

      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('showEditCategoryButton'), isTrue);

      // Close settings modal
      final NavigatorState navigator = tester.state(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      // Edit buttons are now visible
      expect(find.byTooltip('Set category'), findsOneWidget);
      expect(find.byIcon(Icons.label), findsWidgets);
    });

    testWidgets('persists and restores collapsed/expanded state of category groups via SharedPreferences', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              key: const ValueKey('first_instance'),
              user: sampleUser,
              groups: categorizedGroups,
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: TextEditingController(),
              showSystemRoles: false,
              showDescriptions: true,
              showFilters: false,
              currentUsername: 'test_admin',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Collapse 'department'
      await tester.tap(find.byKey(const ValueKey('category_header_department')));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('collapsedRoleCategories'), contains('department'));
      expect(find.textContaining('adm'), findsNothing);

      // Rebuild with a brand new RoleManagementWidget instance to verify it restores collapsed state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              key: const ValueKey('second_instance'),
              user: sampleUser,
              groups: categorizedGroups,
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: TextEditingController(),
              showSystemRoles: false,
              showDescriptions: true,
              showFilters: false,
              currentUsername: 'test_admin',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 'department' should still be collapsed in the new widget instance
      expect(find.textContaining('adm'), findsNothing);
      // 'policy' should still be expanded
      expect(find.textContaining('nld'), findsOneWidget);

      // Expand 'department' and verify SharedPreferences removes it
      await tester.tap(find.byKey(const ValueKey('category_header_department')));
      await tester.pumpAndSettle();

      expect(prefs.getStringList('collapsedRoleCategories'), isNot(contains('department')));
      expect(find.textContaining('adm'), findsOneWidget);
    });

    testWidgets('switching between users shows identical categories, collapse states, and reflects category edits across all users', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'db_host': 'localhost',
        'db_port': 5432,
        'db_user': 'test_admin',
        'db_pass': '',
        'showSystemRoles': false,
        'showSuperusers': false,
        'showDescriptions': true,
        'showFilters': true,
        'showEditCategoryButton': true,
      });

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final secondUser = PgRole(
        oid: 102,
        name: 'bob',
        canLogin: true,
        isSuperuser: false,
        description: 'QA User',
        canManage: true,
        canDrop: true,
      );

      final bobGroups = categorizedGroups.map((g) {
        // Bob has different granted state (only 'hr' is granted)
        return g.copyWith(granted: g.name == 'hr');
      }).toList();

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser, secondUser],
        mockUserGroups: {
          sampleUser.oid: categorizedGroups,
          secondUser.oid: bobGroups,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Select 'alice'
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      expect(find.text('Ungrouped'), findsOneWidget);

      // 2. Select 'bob' first so bob is also visited before editing category
      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();
      expect(find.text('Ungrouped'), findsOneWidget);

      // 3. Switch back to 'alice', edit 'legacy_role' category to 'policy', and collapse 'department'
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Set category'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'policy'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      // 'Ungrouped' is gone for alice, and 'policy' now has 4 roles (1 / 4 assigned for alice)
      expect(find.text('Ungrouped'), findsNothing);
      expect(find.text('1 / 4'), findsOneWidget);

      // Collapse 'department' while viewing alice
      await tester.tap(find.byKey(const ValueKey('category_header_department')));
      await tester.pumpAndSettle();
      expect(find.textContaining('adm'), findsNothing);

      // 4. Switch to 'bob' -> must show 'legacy_role' under 'policy' (no 'Ungrouped'),
      // 'department' must still be collapsed, and bob's granted counts must be 1/3 for department and 0/4 for policy
      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();

      expect(find.text('Ungrouped'), findsNothing);
      expect(find.textContaining('adm'), findsNothing); // department stays collapsed
      expect(find.text('1 / 3'), findsOneWidget); // department: hr is granted
      expect(find.text('0 / 4'), findsOneWidget); // policy: 0 of 4 granted for bob
      expect(find.textContaining('legacy_role'), findsOneWidget);
    });
  });
}
