import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/pg_role.dart';
import '../models/pg_user_group.dart';
import '../services/database_service.dart';
import 'role_management_widget.dart';

class RoleMembershipPage extends StatefulWidget {
  final PgRole user;
  final List<PgUserGroup> groups;
  final Future<void> Function(PgUserGroup, bool) onToggleRole;
  final TextEditingController roleSearchController;
  final bool showSystemRoles;
  final bool showUngrantableRoles;
  final bool showDescriptions;
  final bool showFilters;
  final String currentUsername;
  final bool isDeletable;
  final Function(PgRole) onDeletePressed;
  final DatabaseService? dbService;
  final Future<void> Function()? onRefresh;

  const RoleMembershipPage({
    super.key,
    required this.user,
    required this.groups,
    required this.onToggleRole,
    required this.roleSearchController,
    required this.showSystemRoles,
    this.showUngrantableRoles = false,
    required this.showDescriptions,
    required this.showFilters,
    required this.currentUsername,
    required this.isDeletable,
    required this.onDeletePressed,
    this.dbService,
    this.onRefresh,
  });

  @override
  State<RoleMembershipPage> createState() => _RoleMembershipPageState();
}

class _RoleMembershipPageState extends State<RoleMembershipPage> {
  late PgRole _currentUser;
  late List<PgUserGroup> _currentGroups;
  late bool _showFilters;
  late FocusNode _roleSearchFocusNode;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _currentGroups = List.from(widget.groups);
    _showFilters = widget.showFilters;
    _roleSearchFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          if (_showFilters) {
            _handleEscape();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _roleSearchFocusNode.dispose();
    super.dispose();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_showFilters) {
        _handleEscape();
        return true;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.keyF &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      _activateSearchFilters();
      return true;
    }
    return false;
  }

  void _handleEscape() {
    if (_showFilters) {
      widget.roleSearchController.clear();
      _roleSearchFocusNode.unfocus();
      setState(() {
        _showFilters = false;
      });
    }
  }

  void _activateSearchFilters() {
    if (!_showFilters) {
      setState(() {
        _showFilters = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusRoleSearchField();
        }
      });
    } else {
      _focusRoleSearchField();
    }
  }

  void _focusRoleSearchField() {
    _roleSearchFocusNode.requestFocus();
    widget.roleSearchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.roleSearchController.text.length,
    );
  }

  Future<void> _handleToggle(PgUserGroup group, bool isAssigned) async {
    await widget.onToggleRole(group, isAssigned);
  }

  Future<void> _handleRefresh() async {
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
    }
    if (widget.dbService != null) {
      try {
        final allRoles = await widget.dbService!.fetchAllRoles(forceRefresh: true);
        final updatedGroups = await widget.dbService!.fetchGroupsForUser(_currentUser.oid, forceRefresh: true);
        if (!mounted) return;

        final updatedUser = allRoles.where((r) => r.oid == _currentUser.oid).firstOrNull;
        if (updatedUser == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User no longer exists.')),
          );
          Navigator.of(context).pop();
          return;
        }

        setState(() {
          _currentUser = updatedUser;
          _currentGroups = updatedGroups;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to refresh roles: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentUser.name),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          if (widget.isDeletable)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete Role',
              onPressed: () => widget.onDeletePressed(_currentUser),
            ),
        ],
      ),
      body: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: RoleManagementWidget(
          user: _currentUser,
          groups: _currentGroups,
          onToggleRole: _handleToggle,
          isLoading: false,
          roleSearchController: widget.roleSearchController,
          roleSearchFocusNode: _roleSearchFocusNode,
          showSystemRoles: widget.showSystemRoles,
          showUngrantableRoles: widget.showUngrantableRoles,
          showDescriptions: widget.showDescriptions,
          showFilters: _showFilters,
          currentUsername: widget.currentUsername,
          onRefresh: (widget.dbService != null || widget.onRefresh != null) ? _handleRefresh : null,
        ),
      ),
    );
  }
}
