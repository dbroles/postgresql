import 'package:flutter/material.dart';
import '../models/pg_role.dart';
import '../models/pg_user_group.dart';

enum RoleFilterSegment { all, assigned, available }

class RoleManagementWidget extends StatefulWidget {
  final PgRole user;
  final List<PgUserGroup> groups;
  final Future<void> Function(PgUserGroup, bool) onToggleRole;
  final bool isLoading;
  final TextEditingController roleSearchController;
  final bool showSystemRoles;
  final bool showUngrantableRoles;
  final bool showDescriptions;
  final bool showFilters;
  final String currentUsername;
  final FocusNode? roleSearchFocusNode;
  final Future<void> Function()? onRefresh;

  const RoleManagementWidget({
    super.key,
    required this.user,
    required this.groups,
    required this.onToggleRole,
    required this.isLoading,
    required this.roleSearchController,
    this.roleSearchFocusNode,
    required this.showSystemRoles,
    this.showUngrantableRoles = false,
    required this.showDescriptions,
    required this.showFilters,
    required this.currentUsername,
    this.onRefresh,
  });

  @override
  State<RoleManagementWidget> createState() => _RoleManagementWidgetState();
}

class _RoleManagementWidgetState extends State<RoleManagementWidget> {
  String _roleSearchQuery = '';
  RoleFilterSegment _selectedSegment = RoleFilterSegment.all;
  final Set<String> _togglingRoleNames = {};

  @override
  void initState() {
    super.initState();
    _roleSearchQuery = widget.roleSearchController.text;
    widget.roleSearchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    widget.roleSearchController.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {
        _roleSearchQuery = widget.roleSearchController.text;
      });
    }
  }

  bool _isGroupAssigned(PgUserGroup group) {
    return group.granted || (!group.grantable && group.grantors.isNotEmpty);
  }

  Iterable<PgUserGroup> _getBaseFilteredGroups() {
    Iterable<PgUserGroup> filtered = widget.groups;
    if (!widget.showSystemRoles) {
      filtered = filtered.where((r) => !r.name.startsWith('pg_'));
    }
    if (!widget.showUngrantableRoles) {
      filtered = filtered.where((r) => r.grantable);
    }
    if (_roleSearchQuery.isNotEmpty) {
      final query = _roleSearchQuery.toLowerCase();
      filtered = filtered.where((r) => r.name.toLowerCase().contains(query));
    }
    return filtered;
  }

  List<PgUserGroup> _filterGroups() {
    final base = _getBaseFilteredGroups();
    switch (_selectedSegment) {
      case RoleFilterSegment.all:
        return base.toList();
      case RoleFilterSegment.assigned:
        return base.where(_isGroupAssigned).toList();
      case RoleFilterSegment.available:
        return base.where((g) => !_isGroupAssigned(g)).toList();
    }
  }

  Future<void> _handleToggleRole(PgUserGroup group) async {
    if (_togglingRoleNames.contains(group.name)) return;
    setState(() {
      _togglingRoleNames.add(group.name);
    });
    try {
      await widget.onToggleRole(group, group.granted);
    } finally {
      if (mounted) {
        setState(() {
          _togglingRoleNames.remove(group.name);
        });
      }
    }
  }

  Widget _buildAttributeBall(String label, String abbreviation, bool value, ThemeData theme) {
    return SizedBox(
      width: 55, // Fixed width for consistent spacing
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: value ? Colors.green : Colors.grey.shade400,
            child: Text(
              abbreviation,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfoSection(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.user;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4.0, 16.0, 16.0, 16.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showDescriptions && user.description != null && user.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, bottom: 12.0),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Description: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: user.description!,
                    ),
                  ],
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildAttributeBall('Super', 'S', user.isSuperuser, theme),
                _buildAttributeBall('Inherit', 'I', user.inherit, theme),
                _buildAttributeBall('CreateRole', 'R', user.createRole, theme),
                _buildAttributeBall('CreateDB', 'D', user.createDb, theme),
                _buildAttributeBall('Login', 'L', user.canLogin, theme),
                _buildAttributeBall('Repl', 'P', user.replication, theme),
                _buildAttributeBall('Bypass', 'B', user.bypassRls, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showGrantorDetails(BuildContext context, PgUserGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Role "${group.name}"',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Granted by:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...group.grantors.map(
              (grantor) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(grantor),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildGrantorBadge(BuildContext context, PgUserGroup group) {
    if (group.grantors.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isMultiple = group.grantors.length > 1;
    final iconColor = group.grantable
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
        : Colors.grey.shade400;
    final tooltipMessage = 'Granted by:\n${group.grantors.map((g) => '• $g').join('\n')}';

    return Padding(
      padding: const EdgeInsets.only(left: 6.0),
      child: Tooltip(
        message: tooltipMessage,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showGrantorDetails(context, group),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
            child: Icon(
              isMultiple ? Icons.people_outline : Icons.person_outline,
              size: 16,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentChips(ThemeData theme, Iterable<PgUserGroup> baseGroups) {
    final allCount = baseGroups.length;
    final assignedCount = baseGroups.where(_isGroupAssigned).length;
    final availableCount = allCount - assignedCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Wrap(
        spacing: 8.0,
        children: [
          ChoiceChip(
            label: Text('All ($allCount)'),
            selected: _selectedSegment == RoleFilterSegment.all,
            onSelected: (selected) {
              if (selected) {
                setState(() => _selectedSegment = RoleFilterSegment.all);
              }
            },
          ),
          ChoiceChip(
            label: Text('Assigned ($assignedCount)'),
            selected: _selectedSegment == RoleFilterSegment.assigned,
            onSelected: (selected) {
              if (selected) {
                setState(() => _selectedSegment = RoleFilterSegment.assigned);
              }
            },
          ),
          ChoiceChip(
            label: Text('Available ($availableCount)'),
            selected: _selectedSegment == RoleFilterSegment.available,
            onSelected: (selected) {
              if (selected) {
                setState(() => _selectedSegment = RoleFilterSegment.available);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRoleList(List<PgUserGroup> filteredGroups, ThemeData theme) {
    if (filteredGroups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 48, color: theme.disabledColor),
                const SizedBox(height: 12),
                Text(
                  _selectedSegment == RoleFilterSegment.assigned
                      ? 'No assigned roles'
                      : _selectedSegment == RoleFilterSegment.available
                          ? 'No available roles'
                          : 'No roles found',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: filteredGroups.length,
      itemBuilder: (context, index) {
        final group = filteredGroups[index];
        final isToggling = _togglingRoleNames.contains(group.name);
        final isInteractive = group.grantable && !isToggling && !widget.isLoading;
        final isChecked = group.granted || (!group.grantable && group.grantors.isNotEmpty);

        return CheckboxListTile(
          enabled: isInteractive,
          secondary: isToggling
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: Padding(
                    padding: EdgeInsets.all(2.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Icon(
                  Icons.group,
                  color: group.grantable ? null : Colors.grey.shade400,
                ),
          title: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: group.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: group.grantable ? null : Colors.grey.shade400,
                  ),
                ),
                if (widget.showDescriptions && group.description != null && group.description!.isNotEmpty)
                  TextSpan(
                    text: '  ${group.description!}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: group.grantable
                          ? theme.colorScheme.onSurfaceVariant
                          : Colors.grey.shade400,
                      fontSize: 11,
                    ),
                  ),
                if (group.grantors.isNotEmpty)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _buildGrantorBadge(context, group),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          value: isChecked,
          onChanged: isInteractive ? (val) => _handleToggleRole(group) : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseGroups = _getBaseFilteredGroups();
    final filteredGroups = _filterGroups();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showFilters)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: widget.roleSearchController,
                    focusNode: widget.roleSearchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Filter roles...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _roleSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => widget.roleSearchController.clear(),
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              _buildUserInfoSection(context),
              _buildSegmentChips(theme, baseGroups),
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                child: Text(
                  'Assign or revoke roles to this user.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Expanded(
                child: widget.onRefresh != null
                    ? RefreshIndicator(
                        onRefresh: widget.onRefresh!,
                        child: _buildRoleList(filteredGroups, theme),
                      )
                    : _buildRoleList(filteredGroups, theme),
              ),
            ],
          ),
          if (widget.isLoading)
            Container(
              color: Colors.black12,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
