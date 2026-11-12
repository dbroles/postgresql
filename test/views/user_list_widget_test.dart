import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/views/user_list_widget.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('UserListWidget renders correct icon colors based on role status', (tester) async {
    final regularUser = PgRole(oid: 1, name: 'regular_user', isSuperuser: false, isCurrent: false);
    final currentUser = PgRole(oid: 2, name: 'current_user', isSuperuser: false, isCurrent: true);
    final superUser = PgRole(oid: 3, name: 'superuser', isSuperuser: true, isCurrent: false);
    final currentSuperUser = PgRole(oid: 4, name: 'current_superuser', isSuperuser: true, isCurrent: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserListWidget(
            users: [regularUser, currentUser, superUser, currentSuperUser],
            onUserSelected: (_) {},
            searchController: TextEditingController(),
            searchQuery: '',
            showFilters: false,
            onAddPressed: () {},
          ),
        ),
      ),
    );

    final icons = tester.widgetList<Icon>(find.byIcon(Icons.person)).toList();
    expect(icons.length, 4);

    // Regular user has no special color
    expect(icons[0].color, isNull);

    // Current user has cyan
    expect(icons[1].color, Colors.cyan.shade600);

    // Superuser has gold (amber)
    expect(icons[2].color, Colors.amber);

    // Current user that is also a superuser is gold (amber)
    expect(icons[3].color, Colors.amber);
  });

  testWidgets('UserListWidget renders FloatingActionButton when onAddPressed is provided', (tester) async {
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
          ),
        ),
      ),
    );

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('UserListWidget omits FloatingActionButton when onAddPressed is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserListWidget(
            users: const [],
            onUserSelected: (_) {},
            searchController: TextEditingController(),
            searchQuery: '',
            showFilters: false,
            onAddPressed: null,
          ),
        ),
      ),
    );

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('UserListWidget renders description subtitle when showDescriptions is true', (tester) async {
    final userWithDesc = PgRole(oid: 1, name: 'alice', description: 'Finance Analyst');
    final userWithoutDesc = PgRole(oid: 2, name: 'bob');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserListWidget(
            users: [userWithDesc, userWithoutDesc],
            onUserSelected: (_) {},
            searchController: TextEditingController(),
            searchQuery: '',
            showFilters: false,
            showDescriptions: true,
          ),
        ),
      ),
    );

    expect(find.text('Finance Analyst'), findsOneWidget);
  });

  testWidgets('UserListWidget hides description subtitle when showDescriptions is false', (tester) async {
    final userWithDesc = PgRole(oid: 1, name: 'alice', description: 'Finance Analyst');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserListWidget(
            users: [userWithDesc],
            onUserSelected: (_) {},
            searchController: TextEditingController(),
            searchQuery: '',
            showFilters: false,
            showDescriptions: false,
          ),
        ),
      ),
    );

    expect(find.text('Finance Analyst'), findsNothing);
    expect(find.byKey(const ValueKey('user_section_expired')), findsNothing);
  });

  testWidgets('UserListWidget groups expired users under a collapsible Expired section (default expanded, remembers state, not gray)', (tester) async {
    final validUser = PgRole(
      oid: 1,
      name: 'active_user',
      description: 'Active account',
      isValid: true,
    );
    final expiredUser = PgRole(
      oid: 2,
      name: 'expired_user',
      description: 'Expired account',
      validUntil: DateTime(2020, 1, 1),
      isValid: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserListWidget(
            users: [validUser, expiredUser],
            onUserSelected: (_) {},
            searchController: TextEditingController(),
            searchQuery: '',
            showFilters: false,
            showDescriptions: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Expired section header is shown
    final expiredHeader = find.byKey(const ValueKey('user_section_expired'));
    expect(expiredHeader, findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Default expanded: expired_user is visible and NOT gray
    expect(find.text('expired_user'), findsOneWidget);
    final icons = tester.widgetList<Icon>(find.byIcon(Icons.person)).toList();
    expect(icons.length, 2);
    expect(icons[0].color, isNull);
    expect(icons[1].color, isNull);

    final expiredTitle = tester.widget<Text>(find.text('expired_user'));
    expect(expiredTitle.style?.color, isNull);

    // Tap header to collapse
    await tester.tap(expiredHeader);
    await tester.pumpAndSettle();

    expect(find.text('expired_user'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('expiredUsersSectionCollapsed'), isTrue);

    // Rebuild a fresh UserListWidget and verify it remembers the collapsed state
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserListWidget(
            key: const ValueKey('rebuilt_list'),
            users: [validUser, expiredUser],
            onUserSelected: (_) {},
            searchController: TextEditingController(),
            searchQuery: '',
            showFilters: false,
            showDescriptions: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('expired_user'), findsNothing);

    // Tap header to expand again
    await tester.tap(find.byKey(const ValueKey('user_section_expired')));
    await tester.pumpAndSettle();

    expect(find.text('expired_user'), findsOneWidget);
    expect(prefs.getBool('expiredUsersSectionCollapsed'), isFalse);
  });

  testWidgets('UserListWidget renders Expiring Soon indicator and tooltip when isExpiringSoon is true', (tester) async {
    final now = DateTime.now();
    final inThreeDays = DateTime(now.year, now.month, now.day + 3);
    final expiringUser = PgRole(
      oid: 1,
      name: 'contractor_soon',
      validUntil: inThreeDays,
      isValid: true,
      isExpiringSoon: true,
    );
    final normalUser = PgRole(
      oid: 2,
      name: 'regular_user',
      isValid: true,
      isExpiringSoon: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserListWidget(
            users: [expiringUser, normalUser],
            onUserSelected: (_) {},
            searchController: TextEditingController(),
            searchQuery: '',
            showFilters: false,
          ),
        ),
      ),
    );

    final scheduleIcon = find.byIcon(Icons.schedule);
    expect(scheduleIcon, findsOneWidget);

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: scheduleIcon, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, 'Expires ${PgRole.formatDate(inThreeDays)}');
  });
}
