import 'package:material_ui/material_ui.dart';
import '../models/pg_role.dart';
import '../models/pg_user_group.dart';
import 'edit_role_category_dialog.dart';

typedef AddRoleCategoryResult = EditRoleCategoryResult;

class const AddRoleCategoryDialog({
  super.key,
  required final List<PgRole> availableRoles,
  final List<String> existingCategories = const [],
  final int? defaultOrder,
}) extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    final groups = availableRoles.map((r) => PgUserGroup(
      oid: r.oid,
      name: r.name,
      description: r.description,
      grantors: const [],
      grantable: true,
      granted: false,
    )).toList();

    return EditRoleCategoryDialog(
      title: 'New Role Category',
      subtitle: 'Define a category and assign member roles.',
      defaultOrder: defaultOrder,
      existingCategories: existingCategories,
      availableRoles: groups,
      initialSelectedRoleNames: const [],
    );
  }
}
