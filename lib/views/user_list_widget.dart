import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pg_role.dart';

class const UserListWidget({
  super.key,
  required final List<PgRole> users,
  final int? selectedUserOid,
  required final Function(PgRole) onUserSelected,
  required final TextEditingController searchController,
  final FocusNode? searchFocusNode,
  required final String searchQuery,
  required final bool showFilters,
  final bool showDescriptions = false,
  final VoidCallback? onAddPressed,
  final Future<void> Function()? onRefresh,
}) extends StatefulWidget {

  @override
  State<UserListWidget> createState() => _UserListWidgetState();
}

class _UserListWidgetState extends State<UserListWidget> {
  static const String _expiredCollapsedPrefKey = 'expiredUsersSectionCollapsed';
  bool _isExpiredCollapsed = false;

  @override
  void initState() {
    super.initState();
    _loadExpiredSectionState();
  }

  Future<void> _loadExpiredSectionState() async {
    final prefs = await SharedPreferences.getInstance();
    final collapsed = prefs.getBool(_expiredCollapsedPrefKey);
    if (collapsed != null && mounted) {
      setState(() {
        _isExpiredCollapsed = collapsed;
      });
    }
  }

  Future<void> _toggleExpiredSection() async {
    final nextState = !_isExpiredCollapsed;
    setState(() {
      _isExpiredCollapsed = nextState;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expiredCollapsedPrefKey, nextState);
  }

  Widget _buildUserTile(PgRole user, ThemeData theme) {
    return ListTile(
      selected: widget.selectedUserOid == user.oid,
      leading: Icon(
        Icons.person,
        color: user.isSuperuser
            ? Colors.amber
            : (user.isCurrent ? Colors.cyan.shade600 : null),
      ),
      title: Text(user.name),
      subtitle: (widget.showDescriptions &&
              user.description != null &&
              user.description!.isNotEmpty)
          ? Text(
              user.description!,
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: .italic,
              ),
            )
          : null,
      trailing: user.isExpiringSoon
          ? Tooltip(
              message: user.validUntilDateString != null
                  ? 'Expires ${user.validUntilDateString}'
                  : 'Expiring soon',
              child: const Icon(
                Icons.schedule,
                color: Colors.orange,
                size: 18,
              ),
            )
          : null,
      onTap: () => widget.onUserSelected(user),
    );
  }

  Widget _buildExpiredSectionHeader(int expiredCount, ThemeData theme) {
    return InkWell(
      key: const ValueKey('user_section_expired'),
      onTap: _toggleExpiredSection,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
            bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _isExpiredCollapsed ? Icons.expand_more : Icons.expand_less,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Expired',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$expiredCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(BuildContext context) {
    final theme = Theme.of(context);
    final activeUsers = <PgRole>[];
    final expiredUsers = <PgRole>[];

    for (final user in widget.users) {
      if (user.isValid) {
        activeUsers.add(user);
      } else {
        expiredUsers.add(user);
      }
    }

    if (expiredUsers.isEmpty) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: activeUsers.length,
        itemBuilder: (context, index) => _buildUserTile(activeUsers[index], theme),
      );
    }

    final itemCount =
        activeUsers.length + 1 + (_isExpiredCollapsed ? 0 : expiredUsers.length);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < activeUsers.length) {
          return _buildUserTile(activeUsers[index], theme);
        }
        if (index == activeUsers.length) {
          return _buildExpiredSectionHeader(expiredUsers.length, theme);
        }
        return _buildUserTile(
          expiredUsers[index - activeUsers.length - 1],
          theme,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          if (widget.showFilters)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: widget.searchController,
                focusNode: widget.searchFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Filter users...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: widget.searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => widget.searchController.clear(),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          Expanded(
            child: widget.onRefresh != null
                ? RefreshIndicator(
                    onRefresh: widget.onRefresh!,
                    child: _buildUserList(context),
                  )
                : _buildUserList(context),
          ),
        ],
      ),
      floatingActionButton: widget.onAddPressed != null
          ? FloatingActionButton(
              onPressed: widget.onAddPressed,
              mini: true, // Optional: make it mini to fit better in the pane
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
