import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final List<String> categoryTemplates;

  const RoleManagementWidget({
    super.key,
    required this.user,
    required this.groups,
    required this.onToggleRole,
    this.categoryTemplates = const [],
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
  static const String _ungroupedSectionKey = '__ungrouped__';
  static const String _collapsedCategoriesPrefKey = 'collapsedRoleCategories';
  String _roleSearchQuery = '';
  RoleFilterSegment _selectedSegment = RoleFilterSegment.all;
  final Set<String> _togglingRoleNames = {};
  final Set<String> _collapsedSections = {};

  @override
  void initState() {
    super.initState();
    _roleSearchQuery = widget.roleSearchController.text;
    widget.roleSearchController.addListener(_onSearchChanged);
    _loadCollapsedSections();
  }

  Future<void> _loadCollapsedSections() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_collapsedCategoriesPrefKey);
    if (saved != null && mounted) {
      setState(() {
        _collapsedSections.addAll(saved);
      });
    }
  }

  Future<void> _toggleSectionCollapsed(String sectionKey, bool isCurrentlyCollapsed) async {
    setState(() {
      if (isCurrentlyCollapsed) {
        _collapsedSections.remove(sectionKey);
      } else {
        _collapsedSections.add(sectionKey);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_collapsedCategoriesPrefKey, _collapsedSections.toList());
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
      filtered = filtered.where((r) {
        final matchesName = r.name.toLowerCase().contains(query);
        final matchesDescription = widget.showDescriptions &&
            (r.description?.toLowerCase().contains(query) ?? false);
        final matchesCategory = (r.categoryName ?? r.category)?.toLowerCase().contains(query) ?? false;
        return matchesName || matchesDescription || matchesCategory;
      });
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
            backgroundColor: value ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
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
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<RoleFilterSegment>(
          segments: [
            ButtonSegment<RoleFilterSegment>(
              value: RoleFilterSegment.all,
              label: Text('All ($allCount)', overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
            ButtonSegment<RoleFilterSegment>(
              value: RoleFilterSegment.assigned,
              label: Text('Assigned ($assignedCount)', overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
            ButtonSegment<RoleFilterSegment>(
              value: RoleFilterSegment.available,
              label: Text('Available ($availableCount)', overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          ],
          selected: {_selectedSegment},
          onSelectionChanged: (newSelection) {
            setState(() => _selectedSegment = newSelection.first);
          },
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  Widget _buildRoleTile(PgUserGroup group, ThemeData theme) {
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
  }

  Widget _buildSectionHeader({
    required String sectionKey,
    required String title,
    int? order,
    Color? color,
    required int assignedCount,
    required int totalCount,
    required bool isCollapsed,
    required ThemeData theme,
  }) {
    final headerColor = color ?? theme.colorScheme.primary;

    return InkWell(
      key: ValueKey('category_header_$sectionKey'),
      onTap: () => _toggleSectionCollapsed(sectionKey, isCollapsed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          border: Border(
            left: color != null
                ? BorderSide(color: color, width: 4.0)
                : BorderSide.none,
            bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isCollapsed ? Icons.expand_more : Icons.expand_less,
              size: 20,
              color: headerColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
              decoration: BoxDecoration(
                color: assignedCount > 0
                    ? (color != null ? color.withValues(alpha: 0.15) : theme.colorScheme.primaryContainer)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$assignedCount / $totalCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: assignedCount > 0
                      ? (color ?? theme.colorScheme.onPrimaryContainer)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
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

    final hasCategories = widget.groups.any((g) => g.category != null && g.category!.isNotEmpty);
    if (!hasCategories) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: filteredGroups.length,
        itemBuilder: (context, index) => _buildRoleTile(filteredGroups[index], theme),
      );
    }

    // Build sections in single pass preserving PostgreSQL's ORDER BY
    final sectionOrder = <String>[];
    final sectionTitles = <String, String>{};
    final sectionColors = <String, Color?>{};
    final sectionOrders = <String, int?>{};
    final sectionGroups = <String, List<PgUserGroup>>{};

    for (final group in filteredGroups) {
      final isUngrouped = group.category == null || group.category!.isEmpty;
      final key = isUngrouped
          ? _ungroupedSectionKey
          : (group.categoryName?.toLowerCase() ?? group.category!.toLowerCase());
      final title = isUngrouped ? 'Ungrouped' : (group.categoryName ?? group.category!);

      if (!sectionGroups.containsKey(key)) {
        sectionOrder.add(key);
        sectionTitles[key] = title;
        sectionColors[key] = isUngrouped ? null : group.categoryColor;
        sectionOrders[key] = isUngrouped ? null : group.categoryOrder;
        sectionGroups[key] = [];
      }
      sectionGroups[key]!.add(group);
    }

    final itemBuilders = <Widget Function()>[];
    for (final key in sectionOrder) {
      final groupsInSection = sectionGroups[key]!;
      final assignedCount = groupsInSection.where(_isGroupAssigned).length;
      final isCollapsed = _collapsedSections.contains(key);
      final title = sectionTitles[key]!;
      final order = sectionOrders[key];
      final color = sectionColors[key];
      final totalCount = groupsInSection.length;

      itemBuilders.add(
        () => _buildSectionHeader(
          sectionKey: key,
          title: title,
          order: order,
          color: color,
          assignedCount: assignedCount,
          totalCount: totalCount,
          isCollapsed: isCollapsed,
          theme: theme,
        ),
      );

      if (!isCollapsed) {
        for (final group in groupsInSection) {
          itemBuilders.add(() => _buildRoleTile(group, theme));
        }
      }
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemBuilders.length,
      itemBuilder: (context, index) => itemBuilders[index](),
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
