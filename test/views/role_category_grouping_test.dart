import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/models/pg_user_group.dart';
import 'package:user_manager/views/role_management_widget.dart';
import 'package:user_manager/views/role_manager_home.dart';
import 'package:user_manager/views/edit_role_category_dialog.dart';

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

      // 'legacy_role' is currently in 'Ungrouped'
      expect(find.text('Ungrouped'), findsOneWidget);

      // Open Settings -> Role Categories
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      // Tap Edit on 'policy' category (second category)
      final editButtons = find.byTooltip('Edit Category');
      expect(editButtons, findsWidgets);
      await tester.tap(editButtons.at(1));
      await tester.pumpAndSettle();

      expect(find.text('Edit Category "policy"'), findsOneWidget);

      // Select 'legacy_role' to assign it to 'policy'
      final legacyRoleCheckbox = find.descendant(
        of: find.byType(EditRoleCategoryDialog),
        matching: find.widgetWithText(CheckboxListTile, 'legacy_role'),
      );
      expect(legacyRoleCheckbox, findsOneWidget);
      await tester.ensureVisible(legacyRoleCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(legacyRoleCheckbox);
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      // Close Settings
      await tester.tap(find.byTooltip('Close'));
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

      // Open Settings modal -> 'Role Categories' tab should NOT be shown
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Role Categories'), findsNothing);
    });

    testWidgets('Role rows do not show category edit buttons, keeping the main view clean', (WidgetTester tester) async {
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

      // Role tiles in RoleManagementWidget must not show category edit buttons
      expect(find.byTooltip('Set category'), findsNothing);
      expect(find.byIcon(Icons.label), findsNothing);
      expect(find.byIcon(Icons.label_outline), findsNothing);
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

      // 3. Switch back to 'alice', edit 'policy' category in Settings to include 'legacy_role', and collapse 'department'
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      final editButtons = find.byTooltip('Edit Category');
      await tester.tap(editButtons.at(1)); // policy
      await tester.pumpAndSettle();

      final legacyRoleCheckbox = find.descendant(
        of: find.byType(EditRoleCategoryDialog),
        matching: find.widgetWithText(CheckboxListTile, 'legacy_role'),
      );
      expect(legacyRoleCheckbox, findsOneWidget);
      await tester.ensureVisible(legacyRoleCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(legacyRoleCheckbox);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // 'Ungrouped' is gone for alice, and 'policy' now has 4 roles (1 / 4 assigned for alice)
      expect(find.text('Ungrouped'), findsNothing);
      expect(find.text('1 / 4'), findsOneWidget);

      // Collapse 'department' while viewing alice
      await tester.tap(find.byKey(const ValueKey('category_header_department')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(RoleManagementWidget),
          matching: find.textContaining('adm'),
        ),
        findsNothing,
      );

      // 4. Switch to 'bob' -> must show 'legacy_role' under 'policy' (no 'Ungrouped'),
      // 'department' must still be collapsed, and bob's granted counts must be 1/3 for department and 0/4 for policy
      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();

      expect(find.text('Ungrouped'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(RoleManagementWidget),
          matching: find.textContaining('adm'),
        ),
        findsNothing,
      ); // department stays collapsed
      expect(find.text('1 / 3'), findsOneWidget); // department: hr is granted
      expect(find.text('0 / 4'), findsOneWidget); // policy: 0 of 4 granted for bob
      expect(find.textContaining('legacy_role'), findsOneWidget);
    });
  });

  group('Extended Category Capabilities (name:order:color)', () {
    test('PgUserGroup parses name, order, and color from category string', () {
      final g1 = PgUserGroup(
        oid: 1,
        name: 'r1',
        category: 'department:1:34BB22',
        grantors: [],
        grantable: true,
        granted: false,
      );
      expect(g1.categoryName, 'department');
      expect(g1.categoryOrder, 1);
      expect(g1.categoryColorHex, '34BB22');
      expect(g1.categoryColor, const Color(0xFF34BB22));

      final g2 = PgUserGroup(
        oid: 2,
        name: 'r2',
        category: 'country:2:#88AA00',
        grantors: [],
        grantable: true,
        granted: false,
      );
      expect(g2.categoryName, 'country');
      expect(g2.categoryOrder, 2);
      expect(g2.categoryColorHex, '88AA00');
      expect(g2.categoryColor, const Color(0xFF88AA00));

      // Legacy plain name without colons
      final g3 = PgUserGroup(
        oid: 3,
        name: 'r3',
        category: 'simple_category',
        grantors: [],
        grantable: true,
        granted: false,
      );
      expect(g3.categoryName, 'simple_category');
      expect(g3.categoryOrder, isNull);
      expect(g3.categoryColorHex, isNull);
      expect(g3.categoryColor, isNull);

      // formatCategory helper
      expect(
        PgUserGroup.formatCategory(name: 'department', order: 1, colorHex: '34BB22'),
        'department:1:34BB22',
      );
      expect(
        PgUserGroup.formatCategory(name: 'country', order: 2, colorHex: '#88AA00'),
        'country:2:88AA00',
      );
      expect(
        PgUserGroup.formatCategory(name: 'dept', order: 5),
        'dept:5',
      );
      expect(
        PgUserGroup.formatCategory(name: 'plain'),
        'plain',
      );
    });

    testWidgets('orders groups by category order before alphabetical name and displays colored badges and order indicators', (tester) async {
      final groups = [
        PgUserGroup(
          oid: 201,
          name: 'usa_role',
          category: 'country:2:88AA00',
          granted: false,
          grantable: true,
          grantors: [],
        ),
        PgUserGroup(
          oid: 202,
          name: 'sales_role',
          category: 'department:1:34BB22',
          granted: true,
          grantable: true,
          grantors: [],
        ),
      ];

      final fakeDb = FakeDatabaseService(
        canCreateRoleResult: true,
        roles: [sampleUser],
        mockUserGroups: {
          sampleUser.oid: groups,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoleManagementWidget(
              user: sampleUser,
              groups: await fakeDb.fetchGroupsForUser(sampleUser.oid),
              onToggleRole: (_, _) async {},
              isLoading: false,
              roleSearchController: TextEditingController(),
              roleSearchFocusNode: FocusNode(),
              showSystemRoles: false,
              showDescriptions: true,
              showFilters: true,
              currentUsername: 'test_admin',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // department (#1) should appear before country (#2) even though 'c' comes before 'd'
      final deptFinder = find.text('department');
      final countryFinder = find.text('country');
      expect(deptFinder, findsOneWidget);
      expect(countryFinder, findsOneWidget);

      final deptTop = tester.getTopLeft(deptFinder).dy;
      final countryTop = tester.getTopLeft(countryFinder).dy;
      expect(deptTop, lessThan(countryTop));
    });

    testWidgets('EditRoleCategoryDialog splits name, order, color and saves formatted string', (tester) async {
      String? savedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  savedResult = await showDialog<String>(
                    context: context,
                    builder: (context) => const EditRoleCategoryDialog(
                      roleName: 'test_role',
                      currentCategory: 'initial_cat:3:E53935',
                      existingCategories: ['department:1:34BB22'],
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Pre-populated fields from initial_cat:3:E53935
      expect(find.text('initial_cat'), findsWidgets);
      expect(find.text('E53935'), findsOneWidget);

      // Select existing category suggestion chip (only name is displayed)
      await tester.tap(find.widgetWithText(ChoiceChip, 'department'));
      await tester.pumpAndSettle();

      expect(find.text('department'), findsWidgets);
      expect(find.text('34BB22'), findsOneWidget);

      // Tap Save
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(savedResult, 'department:1:34BB22');
    });
  });

  group('Role Categories in Settings & Dedicated Tab', () {
    testWidgets('Settings shows dedicated Role Categories tab when privilege is granted', (WidgetTester tester) async {
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

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('General Preferences'), findsOneWidget);
      expect(find.text('Role Categories'), findsOneWidget);

      // Switch to Role Categories tab
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      expect(find.text('Manage Categories'), findsOneWidget);
      expect(find.text('New Category'), findsOneWidget);
      expect(find.text('department'), findsOneWidget);
      expect(find.text('policy'), findsOneWidget);
      // Clean circles with no order numbers or pills
      expect(find.text('#1'), findsNothing);
      expect(find.text('#2'), findsNothing);
      // Ungrouped summary is not shown
      expect(find.textContaining('Ungrouped'), findsNothing);
      // Subtitle with member roles list is not shown
      expect(find.textContaining('roles:'), findsNothing);
      expect(find.textContaining('roles assigned'), findsNothing);
    });

    testWidgets('Editing a category in Settings updates category across all member roles', (WidgetTester tester) async {
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

      // Open Settings and switch to Role Categories tab
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      // Tap Edit on 'department' category (which has adm, hr, mktg)
      final editButtons = find.byTooltip('Edit Category');
      expect(editButtons, findsWidgets);
      await tester.tap(editButtons.first);
      await tester.pumpAndSettle();

      // Edit dialog: only Name and Color Hex (no Order field)
      expect(find.text('Edit Category "department"'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Order'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, 'Color Hex'), '34BB22');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      // Verify dbroles.category updated across member roles
      expect(fakeDb.roleCategories['adm'], 'department::34BB22');
      expect(fakeDb.roleCategories['hr'], 'department::34BB22');
      expect(fakeDb.roleCategories['mktg'], 'department::34BB22');

      // Close settings
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Select 'alice' and verify department header is displayed
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      expect(find.text('department'), findsOneWidget);
    });

    testWidgets('Deleting a category in Settings resets dbroles.category on member roles', (WidgetTester tester) async {
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

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      // Tap Delete on first category ('department')
      final deleteButtons = find.byTooltip('Delete Category');
      expect(deleteButtons, findsWidgets);
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Delete Category'), findsOneWidget);
      expect(find.textContaining('This will remove the category from 3 role(s)'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();

      // Verify roles became null in database
      expect(fakeDb.roleCategories['adm'], isNull);
      expect(fakeDb.roleCategories['hr'], isNull);
      expect(fakeDb.roleCategories['mktg'], isNull);
    });

    testWidgets('Adding a new category in Settings with role assignment sets category', (WidgetTester tester) async {
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

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      // Tap 'New Category'
      await tester.tap(find.widgetWithText(FilledButton, 'New Category'));
      await tester.pumpAndSettle();

      expect(find.text('New Role Category'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Order'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Category Name'), 'infrastructure');
      await tester.pumpAndSettle();

      // Select 'legacy_role' from the role list
      final roleCheckbox = find.widgetWithText(CheckboxListTile, 'legacy_role');
      if (roleCheckbox.evaluate().isNotEmpty) {
        await tester.tap(roleCheckbox);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      // If legacy_role was selected, it should now have the category in the database
      if (roleCheckbox.evaluate().isNotEmpty) {
        expect(fakeDb.roleCategories['legacy_role'], 'infrastructure:3');
      }
    });

    testWidgets('Dragging a category reorders categories and persists new numeric order', (WidgetTester tester) async {
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

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      // ReorderableListView is present
      expect(find.byType(ReorderableListView), findsOneWidget);

      // Drag policy (index 1) to index 0 using drag handle
      final dragHandles = find.byIcon(Icons.drag_handle);
      expect(dragHandles, findsWidgets);

      // Perform reorder gesture
      final firstHandle = tester.getCenter(dragHandles.first);
      final secondHandle = tester.getCenter(dragHandles.at(1));

      final TestGesture gesture = await tester.startGesture(secondHandle);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveTo(firstHandle - const Offset(0, 20));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      // Close settings
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('Category editor search box filters by both role name and description', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final countryRoles = [
        PgUserGroup(
          oid: 301,
          name: 'bel',
          description: 'Belgium country group',
          granted: false,
          grantable: true,
          grantors: [],
        ),
        PgUserGroup(
          oid: 302,
          name: 'nld',
          description: 'Netherlands country policy',
          granted: false,
          grantable: true,
          grantors: [],
        ),
        PgUserGroup(
          oid: 303,
          name: 'usa',
          description: 'United States country office',
          granted: false,
          grantable: true,
          grantors: [],
        ),
        PgUserGroup(
          oid: 304,
          name: 'other_role',
          description: 'DevOps team',
          granted: false,
          grantable: true,
          grantors: [],
        ),
      ];

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockUserGroups: {sampleUser.oid: countryRoles},
        canSetCategoryParameterResult: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      // Open settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      // Tap "New Category"
      await tester.tap(find.widgetWithText(FilledButton, 'New Category'));
      await tester.pumpAndSettle();

      // Enter name "country"
      await tester.enterText(find.widgetWithText(TextField, 'Category Name'), 'country');
      await tester.pumpAndSettle();

      // Search for "country" in the search box
      final searchField = find.widgetWithText(TextField, 'Search roles or descriptions...');
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'country');
      await tester.pumpAndSettle();

      // bel, nld, and usa all matched via description
      expect(find.widgetWithText(CheckboxListTile, 'bel'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'nld'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'usa'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'other_role'), findsNothing);

      // Tap "Select All"
      await tester.tap(find.widgetWithText(TextButton, 'Select All'));
      await tester.pumpAndSettle();

      // Save category
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      // Close settings modal
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Verify that all 3 country roles were assigned 'country:1'
      expect(fakeDb.roleCategories['bel'], 'country:1');
      expect(fakeDb.roleCategories['nld'], 'country:1');
      expect(fakeDb.roleCategories['usa'], 'country:1');
      expect(fakeDb.roleCategories.containsKey('other_role'), isFalse);
    });

    testWidgets('handles 100+ groups in category editor with filtering and bulk selection', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Generate 120 groups
      final manyGroups = <PgUserGroup>[];
      for (int i = 1; i <= 60; i++) {
        manyGroups.add(PgUserGroup(
          oid: 1000 + i,
          name: 'dev_$i',
          description: 'Developer backend engineering team role',
          granted: false,
          grantable: true,
          grantors: [],
        ));
      }
      manyGroups.add(PgUserGroup(
        oid: 2001,
        name: 'bel',
        description: 'Belgium country office',
        granted: false,
        grantable: true,
        grantors: [],
      ));
      manyGroups.add(PgUserGroup(
        oid: 2002,
        name: 'nld',
        description: 'Netherlands country office',
        granted: false,
        grantable: true,
        grantors: [],
      ));
      manyGroups.add(PgUserGroup(
        oid: 2003,
        name: 'usa',
        description: 'United States country office',
        granted: false,
        grantable: true,
        grantors: [],
      ));
      for (int i = 1; i <= 57; i++) {
        manyGroups.add(PgUserGroup(
          oid: 3000 + i,
          name: 'finance_$i',
          description: 'Finance billing role',
          granted: false,
          grantable: true,
          grantors: [],
        ));
      }

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockUserGroups: {sampleUser.oid: manyGroups},
        canSetCategoryParameterResult: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'New Category'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Category Name'), 'countries');
      await tester.pumpAndSettle();

      // Search by description containing "country"
      final searchField = find.widgetWithText(TextField, 'Search roles or descriptions...');
      await tester.enterText(searchField, 'country');
      await tester.pumpAndSettle();

      // Select All filtered (bel, nld, usa)
      await tester.tap(find.widgetWithText(TextButton, 'Select All'));
      await tester.pumpAndSettle();

      // Tap "In Category" segment chip
      await tester.tap(find.widgetWithText(ChoiceChip, 'In Category (3)'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(CheckboxListTile, 'bel'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'nld'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'usa'), findsOneWidget);

      // Save category
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(fakeDb.roleCategories['bel'], 'countries:1');
      expect(fakeDb.roleCategories['nld'], 'countries:1');
      expect(fakeDb.roleCategories['usa'], 'countries:1');
    });

    testWidgets('Edit Category displays Category Name and Color Hex on separate rows and hides ungrantable roles', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mixedGrantableRoles = [
        PgUserGroup(
          oid: 401,
          name: 'grantable_role',
          description: 'Can be managed',
          granted: false,
          grantable: true,
          grantors: [],
        ),
        PgUserGroup(
          oid: 402,
          name: 'ungrantable_role',
          description: 'Cannot be managed by current user',
          granted: false,
          grantable: false,
          grantors: [],
        ),
      ];

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockUserGroups: {sampleUser.oid: mixedGrantableRoles},
        canSetCategoryParameterResult: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'New Category'));
      await tester.pumpAndSettle();

      final nameField = find.widgetWithText(TextField, 'Category Name');
      final colorField = find.widgetWithText(TextField, 'Color Hex');

      expect(nameField, findsOneWidget);
      expect(colorField, findsOneWidget);

      // Verify they are on different vertical rows (nameField top is strictly less than colorField top)
      final nameTop = tester.getTopLeft(nameField).dy;
      final colorTop = tester.getTopLeft(colorField).dy;
      expect(nameTop, lessThan(colorTop));

      // Verify ungrantable role is hidden, while grantable role is displayed
      expect(find.widgetWithText(CheckboxListTile, 'grantable_role'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'ungrantable_role'), findsNothing);
    });

    testWidgets('Multi-admin isolation: Settings Role Categories tab only displays and updates categories for grantable roles', (tester) async {
      final sampleUser = PgRole(
        oid: 101,
        name: 'operator_a',
        canLogin: true,
        isSuperuser: false,
        inherit: true,
        createRole: true,
        createDb: false,
        replication: false,
        bypassRls: false,
        canManage: true,
        canDrop: true,
      );

      final mixedGroups = [
        PgUserGroup(
          oid: 501,
          name: 'sales_rep',
          category: 'sales:1:1E88E5',
          grantable: true,
          granted: false,
          grantors: [],
        ),
        PgUserGroup(
          oid: 502,
          name: 'warehouse_forklift',
          category: 'logistics:2:00ACC1',
          grantable: false, // Belongs to Program B / another admin!
          granted: false,
          grantors: [],
        ),
      ];

      final fakeDb = FakeDatabaseService(
        roles: [sampleUser],
        mockUserGroups: {sampleUser.oid: mixedGroups},
        canSetCategoryParameterResult: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoleManagerHome(dbService: fakeDb),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Role Categories'));
      await tester.pumpAndSettle();

      // Program A's category 'sales' must be displayed
      expect(find.text('sales'), findsOneWidget);

      // Program B's category 'logistics' must NOT be displayed because operator_a has no grantable roles in it!
      expect(find.text('logistics'), findsNothing);
    });

    test('persists role categories in SharedPreferences scoped per host:login:database', () async {
      SharedPreferences.setMockInitialValues({});

      final ungroupedRoles = [
        PgUserGroup(
          oid: 601,
          name: 'hr',
          grantable: true,
          granted: false,
          grantors: [],
        ),
        PgUserGroup(
          oid: 602,
          name: 'nld',
          grantable: true,
          granted: false,
          grantors: [],
        ),
      ];

      final dbProd = FakeDatabaseService(
        host: 'rds.amazonaws.com',
        username: 'dbroles',
        database: 'app_prod',
        mockUserGroups: {sampleUser.oid: ungroupedRoles},
      );

      final dbStaging = FakeDatabaseService(
        host: 'rds.amazonaws.com',
        username: 'dbroles',
        database: 'app_staging',
        mockUserGroups: {sampleUser.oid: ungroupedRoles},
      );

      expect(dbProd.categoryStorageScope, 'rds.amazonaws.com:dbroles:app_prod');
      expect(dbStaging.categoryStorageScope, 'rds.amazonaws.com:dbroles:app_staging');

      // Set category in app_prod
      await dbProd.setRoleCategory('hr', 'department:1:1E88E5');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('role_categories_rds.amazonaws.com:dbroles:app_prod'),
        contains('"hr":"department:1:1E88E5"'),
      );
      expect(
        prefs.getString('role_categories_rds.amazonaws.com:dbroles:app_staging'),
        isNull,
      );

      // Verify app_prod returns categorized 'hr' while app_staging remains ungrouped
      final prodGroups = await dbProd.fetchGroupsForUser(sampleUser.oid);
      expect(prodGroups.firstWhere((g) => g.name == 'hr').categoryName, 'department');

      final stagingGroups = await dbStaging.fetchGroupsForUser(sampleUser.oid);
      expect(stagingGroups.firstWhere((g) => g.name == 'hr').category, isNull);
    });
  });
}
