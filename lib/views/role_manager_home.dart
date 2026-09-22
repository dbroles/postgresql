import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postgres/postgres.dart';
import '../models/pg_role.dart';
import '../models/pg_user_group.dart';
import '../services/database_service.dart';
import '../services/credential_storage_service.dart';
import 'connection_settings_page.dart';
import 'create_user_dialog.dart';
import 'role_membership_page.dart';
import 'user_list_widget.dart';
import 'role_management_widget.dart';
import 'connection_status_bar.dart';

class RoleManagerHome extends StatefulWidget {
  final DatabaseService? dbService;
  final CredentialStorageService? credentialStorage;

  const RoleManagerHome({super.key, this.dbService, this.credentialStorage});

  @override
  State<RoleManagerHome> createState() => _RoleManagerHomeState();
}

class _RoleManagerHomeState extends State<RoleManagerHome> {
  late final DatabaseService _dbService;
  late final CredentialStorageService _credentialStorage;
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _roleSearchController = TextEditingController();
  late final FocusNode _userSearchFocusNode;
  late final FocusNode _roleSearchFocusNode;

  List<PgRole> _users = [];
  List<PgRole> _groups = [];
  PgRole? _selectedUser;
  List<PgUserGroup> _selectedUserGroups = [];

  bool _isLoading = true;
  String? _error;
  bool _showSystemRoles = false;
  bool _showUngrantableRoles = false;
  bool _showUsersWithoutAdminOption = false;
  bool _showSuperusers = false;
  bool _showDescriptions = true;
  bool _showFilters = false;
  bool _showConnectedUser = false;
  String _userSearchQuery = '';
  String? _clusterName;
  bool _isSslEnabled = false;
  bool _canCreateRole = false;

  @override
  void initState() {
    super.initState();
    _dbService = widget.dbService ?? DatabaseService();
    _credentialStorage = widget.credentialStorage ?? CredentialStorageService();
    _userSearchFocusNode = FocusNode(
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
    _loadSettingsAndData();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _userSearchController.addListener(() {
      setState(() {
        _userSearchQuery = _userSearchController.text;
      });
    });
    _roleSearchController.addListener(() {
      setState(() {
        // Just trigger a rebuild; RoleManagementWidget handles its own local filtering
      });
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _userSearchController.dispose();
    _roleSearchController.dispose();
    _userSearchFocusNode.dispose();
    _roleSearchFocusNode.dispose();
    if (widget.dbService == null) {
      _dbService.close();
    }
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
      _userSearchController.clear();
      _roleSearchController.clear();
      _userSearchFocusNode.unfocus();
      _roleSearchFocusNode.unfocus();
      _saveFiltersSetting(false);
    }
  }

  void _activateSearchFilters() {
    if (!_showFilters) {
      _saveFiltersSetting(true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusAppropriateSearchField();
        }
      });
    } else {
      _focusAppropriateSearchField();
    }
  }

  void _focusAppropriateSearchField() {
    if (_selectedUser != null && _userSearchFocusNode.hasFocus) {
      _roleSearchFocusNode.requestFocus();
      _roleSearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _roleSearchController.text.length,
      );
    } else if (_selectedUser != null && _roleSearchFocusNode.hasFocus) {
      _userSearchFocusNode.requestFocus();
      _userSearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _userSearchController.text.length,
      );
    } else {
      _userSearchFocusNode.requestFocus();
      _userSearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _userSearchController.text.length,
      );
    }
  }

  Future<void> _loadSettingsAndData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Connection Settings
    _dbService.host = prefs.getString('db_host') ?? 'localhost';
    _dbService.port = prefs.getInt('db_port') ?? 5432;
    _dbService.username = prefs.getString('db_user') ?? 'dbroles';

    final rememberPass = prefs.getBool('db_remember_pass') ?? true;
    if (rememberPass) {
      final securePass = await _credentialStorage.getPassword();
      _dbService.password = securePass ?? '';
    } else {
      _dbService.password = '';
    }

    _dbService.sslMode = SslMode.values[prefs.getInt('db_ssl_mode') ?? SslMode.require.index];

    setState(() {
      _showSystemRoles = prefs.getBool('showSystemRoles') ?? false;
      _showUngrantableRoles = prefs.getBool('showUngrantableRoles') ?? false;
      _showUsersWithoutAdminOption = prefs.getBool('showUsersWithoutAdminOption') ?? prefs.getBool('showUngrantableUsers') ?? false;
      _showSuperusers = prefs.getBool('showSuperusers') ?? false;
      _showDescriptions = prefs.getBool('showDescriptions') ?? true;
      _showFilters = prefs.getBool('showFilters') ?? false;
      _showConnectedUser = prefs.getBool('showConnectedUser') ?? false;
    });
    
    await _loadInitialData();
  }

  void _validateSelectedUser() {
    if (_selectedUser == null) return;
    final visibleUsers = _filterRoles(_users, isUserList: true);
    if (!visibleUsers.any((u) => u.oid == _selectedUser!.oid)) {
      _selectedUser = null;
      _selectedUserGroups = [];
    }
  }

  Future<void> _saveSystemRolesSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showSystemRoles', value);
    setState(() {
      _showSystemRoles = value;
      _validateSelectedUser();
    });
  }

  Future<void> _saveUngrantableRolesSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showUngrantableRoles', value);
    setState(() {
      _showUngrantableRoles = value;
    });
  }

  Future<void> _saveUsersWithoutAdminOptionSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showUsersWithoutAdminOption', value);
    setState(() {
      _showUsersWithoutAdminOption = value;
      _validateSelectedUser();
    });
  }

  Future<void> _saveSuperusersSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showSuperusers', value);
    setState(() {
      _showSuperusers = value;
      _validateSelectedUser();
    });
  }

  Future<void> _saveDescriptionsSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showDescriptions', value);
    setState(() {
      _showDescriptions = value;
    });
  }

  Future<void> _saveFiltersSetting(bool value) async {
    setState(() {
      _showFilters = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showFilters', value);
  }

  Future<void> _saveShowConnectedUserSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showConnectedUser', value);
    setState(() {
      _showConnectedUser = value;
      _validateSelectedUser();
    });
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedUser = null; // Clear selection on refresh
      _selectedUserGroups = []; // Clear groups on refresh
    });

    try {
      _dbService.clearCache();
      final connectionError = await _dbService.testConnection();
      if (connectionError != null) {
        if (!mounted) return;
        await _openConnectionSettings();
        return;
      }

      // Security check: We don't want to run as superuser
      final isSuper = await _dbService.isCurrentUserSuperuser();
      if (isSuper) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Superuser connection detected. Please setup a Role Admin.')),
        );
        await _openConnectionSettings();
        return;
      }

      final allRoles = await _dbService.fetchAllRoles(forceRefresh: true);
      final clusterName = await _dbService.fetchClusterName();
      final isSsl = await _dbService.fetchSslStatus();
      final canCreateRole = await _dbService.canCurrentUserCreateRole();
      
      setState(() {
        _users = allRoles.where((r) => r.canLogin).toList();
        _groups = allRoles.where((r) => !r.canLogin).toList();
        _clusterName = clusterName;
        _isSslEnabled = isSsl;
        _canCreateRole = canCreateRole;
      });
    } catch (e) {
      setState(() => _error = e.toString());
      if (!mounted) return;
      await _openConnectionSettings();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openConnectionSettings() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConnectionSettingsPage(
          dbService: _dbService,
          credentialStorage: _credentialStorage,
        ),
      ),
    );

    if (result == true) {
      await _loadInitialData();
    }
  }

  Future<void> _createNewRole() async {
    final result = await showDialog<PgRole>(
      context: context,
      builder: (context) => CreateUserDialog(dbService: _dbService),
    );

    if (result != null) {
      // Optimistically add to cache instead of full reload
      setState(() {
        if (result.canLogin) {
          _users.add(result);
          _users.sort((a, b) => a.name.compareTo(b.name));
        }
        if (!result.canLogin) {
          _groups.add(result);
          _groups.sort((a, b) => a.name.compareTo(b.name));
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User "${result.name}" created successfully.')),
        );
      }
    }
  }

  Future<void> _selectUser(PgRole user, bool isNarrow) async {
    setState(() {
      _selectedUser = user;
      _isLoading = true;
    });

    try {
      final userGroups = await _dbService.fetchGroupsForUser(user.oid);
      if (!mounted) return;

      setState(() {
        _selectedUserGroups = userGroups;
        _isLoading = false;
      });

      if (isNarrow) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RoleMembershipPage(
              user: user,
              groups: _selectedUserGroups,
              onToggleRole: _toggleRole,
              roleSearchController: _roleSearchController,
              showSystemRoles: _showSystemRoles,
              showUngrantableRoles: _showUngrantableRoles,
              showDescriptions: _showDescriptions,
              showFilters: _showFilters,
              currentUsername: _dbService.username,
              isDeletable: _isUserDeletable(user),
              onDeletePressed: _handleDeleteUser,
              dbService: _dbService,
              onRefresh: _refreshRolesData,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading memberships: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshRolesData() async {
    try {
      final allRoles = await _dbService.fetchAllRoles(forceRefresh: true);
      List<PgUserGroup>? refreshedGroups;
      if (_selectedUser != null) {
        refreshedGroups = await _dbService.fetchGroupsForUser(_selectedUser!.oid, forceRefresh: true);
      }
      final clusterName = await _dbService.fetchClusterName();
      final isSsl = await _dbService.fetchSslStatus();
      final canCreateRole = await _dbService.canCurrentUserCreateRole();
      if (!mounted) return;

      setState(() {
        _users = allRoles.where((r) => r.canLogin).toList();
        _groups = allRoles.where((r) => !r.canLogin).toList();
        _clusterName = clusterName;
        _isSslEnabled = isSsl;
        _canCreateRole = canCreateRole;

        if (_selectedUser != null) {
          final updatedUser = allRoles.where((r) => r.oid == _selectedUser!.oid).firstOrNull;
          if (updatedUser != null) {
            _selectedUser = updatedUser;
            _selectedUserGroups = refreshedGroups ?? [];
            _validateSelectedUser();
          } else {
            _selectedUser = null;
            _selectedUserGroups = [];
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh roles: $e')),
        );
      }
    }
  }

  Future<void> _toggleRole(PgUserGroup group, bool isAssigned) async {
    if (_selectedUser == null) return;

    final targetUserOid = _selectedUser!.oid;
    final targetUserName = _selectedUser!.name;

    // Optimistic Update: Update local cache first
    setState(() {
      group.granted = !isAssigned;
    });

    try {
      if (isAssigned) {
        await _dbService.revokeRole(targetUserName, group.name, userOid: targetUserOid);
      } else {
        await _dbService.grantRole(targetUserName, group.name, userOid: targetUserOid);
      }
    } catch (e) {
      // Revert optimistic update
      setState(() {
        group.granted = isAssigned;
      });
      if (!mounted) return;
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('does not exist')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User or role no longer exists. Refreshing data...')),
        );
        _loadInitialData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e. Please reload data.')),
        );
      }
    }
  }

  List<PgRole> _filterRoles(List<PgRole> roles, {String? searchQuery, bool isUserList = false}) {
    Iterable<PgRole> filtered = roles;

    if (isUserList && !_showConnectedUser) {
      // Hide the currently connected user from the target list if setting is off
      filtered = filtered.where((r) => !r.isCurrent && r.name != _dbService.username);
    }

    if (!_showSystemRoles) {
      filtered = filtered.where((r) => !r.name.startsWith('pg_'));
    }

    if (isUserList && !_showUsersWithoutAdminOption) {
      filtered = filtered.where((r) => r.isAdmin || r.isSuperuser || r.isCurrent || r.name == _dbService.username);
    }

    if (isUserList && !_showSuperusers) {
      filtered = filtered.where((r) => !r.isSuperuser || (_showConnectedUser && (r.isCurrent || r.name == _dbService.username)));
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((r) {
        final matchesName = r.name.toLowerCase().contains(query);
        final matchesDescription = _showDescriptions &&
            (r.description?.toLowerCase().contains(query) ?? false);
        return matchesName || matchesDescription;
      });
    }
    return filtered.toList();
  }

  bool _isUserDeletable(PgRole user) {
    // Condition 0: PostgreSQL Entitlement (CREATEROLE + ADMIN OPTION on this role)
    if (!user.canDrop) {
      return false;
    }

    // Condition 1: No special attributes (Security safety)
    if (user.isSuperuser || user.createRole || user.createDb || user.replication || user.bypassRls) {
      return false;
    }

    // Condition 2: No memberships granted by another grantor (Revocation safety)
    if (_selectedUser?.oid == user.oid) {
      final hasExternalGrantors = _selectedUserGroups.any((g) => g.grantors.isNotEmpty);
      if (hasExternalGrantors) return false;
    }

    return true;
  }

  Future<void> _handleDeleteUser(PgRole user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text('Are you sure you want to delete the role "${user.name}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _dbService.dropRole(user.name);
      
      setState(() {
        _users.removeWhere((u) => u.oid == user.oid);
        _groups.removeWhere((g) => g.oid == user.oid);
        if (_selectedUser?.oid == user.oid) {
          _selectedUser = null;
          _selectedUserGroups = [];
        }
      });

      if (mounted) {
        // If on mobile (narrow screen), navigate back to the user list
        if (MediaQuery.of(context).size.width < 600) {
          Navigator.of(context).pop();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role "${user.name}" deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete role: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('General Settings', style: Theme.of(context).textTheme.titleLarge),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('Show Descriptions'),
                      subtitle: const Text('Show role and user descriptions'),
                      value: _showDescriptions,
                      onChanged: (value) {
                        _saveDescriptionsSetting(value);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Filters'),
                      subtitle: const Text('Show user and role search filters'),
                      value: _showFilters,
                      onChanged: (value) {
                        _saveFiltersSetting(value);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Ungrantable Roles'),
                      subtitle: const Text('Include roles that cannot be granted due to missing permissions'),
                      value: _showUngrantableRoles,
                      onChanged: (value) {
                        _saveUngrantableRolesSetting(value);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Users Without Admin Option'),
                      subtitle: const Text('Include users for which the connected user does not have ADMIN OPTION'),
                      value: _showUsersWithoutAdminOption,
                      onChanged: (value) {
                        _saveUsersWithoutAdminOptionSetting(value);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Superusers'),
                      subtitle: const Text('Include roles with superuser privileges'),
                      value: _showSuperusers,
                      onChanged: (value) {
                        _saveSuperusersSetting(value);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Connected User'),
                      subtitle: const Text('Show the active connection account in the user list'),
                      value: _showConnectedUser,
                      onChanged: (value) {
                        _saveShowConnectedUserSetting(value);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show System Roles'),
                      subtitle: const Text('Include roles starting with "pg_"'),
                      value: _showSystemRoles,
                      onChanged: (value) {
                        _saveSystemRolesSetting(value);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrow = MediaQuery.of(context).size.width < 600;
    final isMobile = theme.platform == TargetPlatform.android || theme.platform == TargetPlatform.iOS;

    final filteredUsers = _filterRoles(_users, searchQuery: _userSearchQuery, isUserList: true);

    final userListWidget = UserListWidget(
      users: filteredUsers,
      selectedUserOid: _selectedUser?.oid,
      onUserSelected: (user) => _selectUser(user, isNarrow),
      searchController: _userSearchController,
      searchFocusNode: _userSearchFocusNode,
      searchQuery: _userSearchQuery,
      showFilters: _showFilters,
      showDescriptions: _showDescriptions,
      onAddPressed: _canCreateRole ? _createNewRole : null,
      onRefresh: _refreshRolesData,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedUser != null && !isNarrow 
            ? 'User Manager - ${_selectedUser!.name}'
            : 'User Manager'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          if (_selectedUser != null && _isUserDeletable(_selectedUser!) && !isNarrow)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete Role',
              onPressed: () => _handleDeleteUser(_selectedUser!),
            ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Connection Settings',
            onPressed: _openConnectionSettings,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'App Settings',
            onPressed: _openSettings,
          ),
          if (!isMobile)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _refreshRolesData,
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
        child: _isLoading && _users.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _users.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Error: $_error', style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadInitialData, child: const Text('Retry')),
                      ],
                    ),
                  )
                : isNarrow
                    ? userListWidget
                    : Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(right: BorderSide(color: theme.dividerColor)),
                              ),
                              child: userListWidget,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: _selectedUser == null
                                ? const Center(child: Text('Select a user to manage roles'))
                                : RoleManagementWidget(
                                    user: _selectedUser!,
                                    groups: _selectedUserGroups,
                                    onToggleRole: _toggleRole,
                                    isLoading: _isLoading,
                                    roleSearchController: _roleSearchController,
                                    roleSearchFocusNode: _roleSearchFocusNode,
                                    showSystemRoles: _showSystemRoles,
                                    showUngrantableRoles: _showUngrantableRoles,
                                    showDescriptions: _showDescriptions,
                                    showFilters: _showFilters,
                                    currentUsername: _dbService.username,
                                    onRefresh: _refreshRolesData,
                                  ),
                          ),
                        ],
                      ),
      ),
      bottomNavigationBar: ConnectionStatusBar(
        clusterName: _clusterName,
        host: _dbService.host,
        isSslEnabled: _isSslEnabled,
        onTap: _openConnectionSettings,
      ),
    );
  }
}
