import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/views/user_list_widget.dart';

void main() {
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
}
