import 'package:flutter/material.dart';
import '../models/pg_role.dart';

class UserListWidget extends StatelessWidget {
  final List<PgRole> users;
  final int? selectedUserOid;
  final Function(PgRole) onUserSelected;
  final TextEditingController searchController;
  final FocusNode? searchFocusNode;
  final String searchQuery;
  final bool showFilters;
  final bool showDescriptions;
  final VoidCallback? onAddPressed;
  final Future<void> Function()? onRefresh;

  const UserListWidget({
    super.key,
    required this.users,
    this.selectedUserOid,
    required this.onUserSelected,
    required this.searchController,
    this.searchFocusNode,
    required this.searchQuery,
    required this.showFilters,
    this.showDescriptions = false,
    this.onAddPressed,
    this.onRefresh,
  });

  Widget _buildUserList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final theme = Theme.of(context);
        return ListTile(
          selected: selectedUserOid == user.oid,
          leading: Icon(
            Icons.person,
            color: user.isSuperuser
                ? Colors.amber
                : (user.isCurrent ? Colors.cyan.shade600 : null),
          ),
          title: Text(user.name),
          subtitle: (showDescriptions &&
                  user.description != null &&
                  user.description!.isNotEmpty)
              ? Text(
                  user.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : null,
          onTap: () => onUserSelected(user),
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
          if (showFilters)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Filter users...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => searchController.clear(),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          Expanded(
            child: onRefresh != null
                ? RefreshIndicator(
                    onRefresh: onRefresh!,
                    child: _buildUserList(),
                  )
                : _buildUserList(),
          ),
        ],
      ),
      floatingActionButton: onAddPressed != null
          ? FloatingActionButton(
              onPressed: onAddPressed,
              mini: true, // Optional: make it mini to fit better in the pane
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
