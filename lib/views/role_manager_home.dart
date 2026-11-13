import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postgres/postgres.dart';
import '../main.dart';
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
import 'edit_role_category_dialog.dart';

class const RoleManagerHome({
  super.key,
  final DatabaseService? dbService,
  final CredentialStorageService? credentialStorage,
}) extends StatefulWidget {
  @override
  State<RoleManagerHome> createState() => _RoleManagerHomeState();
}

class _RoleManagerHomeState extends State<RoleManagerHome> {
  static const String _ungroupedCategoryKey = '__ungrouped__';
  late final DatabaseService _dbService;
  late final CredentialStorageService _credentialStorage;
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _roleSearchController = TextEditingController();
  late final FocusNode _userSearchFocusNode;
  late final FocusNode _roleSearchFocusNode;

  List<PgRole> _users = [];
  List<PgRole> _groups = [];
  List<PgUserGroup> _groupCatalog = [];
  List<String> _savedCategoryTemplates = [];
  String get _customCategoriesPrefKey =>
      'savedRoleCategoryTemplates_${_dbService.categoryStorageScope}';

  List<String> get _allCategoryTemplates {
    final seen = <String>{};
    final result = <String>[];

    for (final t in _savedCategoryTemplates) {
      final key = PgUserGroup.categoryKey(t);
      if (key != null && seen.add(key)) {
        result.add(t.trim());
      }
    }

    for (final g in _groupCatalog) {
      if (!g.grantable) continue;
      final cat = g.category?.trim();
      final key = PgUserGroup.categoryKey(cat);
      if (cat != null && key != null && seen.add(key)) {
        result.add(cat);
      }
    }

    for (final g in _selectedUserGroups) {
      if (!g.grantable) continue;
      final cat = g.category?.trim();
      final key = PgUserGroup.categoryKey(cat);
      if (cat != null && key != null && seen.add(key)) {
        result.add(cat);
      }
    }

    return result;
  }

  List<PgUserGroup> get _allAvailableGroupsWithCategories {
    if (_groupCatalog.isNotEmpty) {
      return _groupCatalog.where((r) => r.grantable).toList();
    }
    final catMap = <String, String?>{};
    for (final g in _selectedUserGroups) {
      if (g.category != null && g.category!.isNotEmpty) {
        catMap[g.name] = g.category;
      }
    }
    return _groups.where((r) => r.isAdmin).map((r) => PgUserGroup(
      oid: r.oid,
      name: r.name,
      description: r.description,
      grantors: const [],
      grantable: true,
      granted: false,
      category: catMap[r.name],
    )).toList();
  }

  PgRole? _selectedUser;
  List<PgUserGroup> _selectedUserGroups = [];

  bool _isLoading = true;
  String? _error;
  bool _showDescriptions = true;
  bool _showFilters = false;
  ThemeMode _themeMode = .system;
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
    _dbService.database = prefs.getString('db_name') ?? 'postgres';
    _dbService.username = prefs.getString('db_user') ?? 'dbroles';

    final rememberPass = prefs.getBool('db_remember_pass') ?? true;
    if (rememberPass) {
      final connKey = CredentialStorageService.connectionStorageKey(
        host: _dbService.host,
        port: _dbService.port,
        database: _dbService.database,
        username: _dbService.username,
      );
      final securePass = await _credentialStorage.getPassword(connectionKey: connKey);
      _dbService.password = securePass ?? '';
    } else {
      _dbService.password = '';
    }

    _dbService.sslMode = SslMode.values[prefs.getInt('db_ssl_mode') ?? SslMode.require.index];

    final savedTheme = prefs.getString('themeMode');
    final themeMode = switch (savedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    appThemeModeNotifier.value = themeMode;

    setState(() {
      _showDescriptions = prefs.getBool('showDescriptions') ?? true;
      _showFilters = prefs.getBool('showFilters') ?? false;
      _themeMode = themeMode;
      _savedCategoryTemplates =
          prefs.getStringList(_customCategoriesPrefKey) ??
          prefs.getStringList('savedRoleCategoryTemplates') ??
          [];
    });
    
    await _loadInitialData();
  }

  Future<void> _saveCustomCategoryTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customCategoriesPrefKey, _savedCategoryTemplates);
  }

  void _validateSelectedUser() {
    if (_selectedUser == null) return;
    final visibleUsers = _filterRoles(_users, isUserList: true);
    if (!visibleUsers.any((u) => u.oid == _selectedUser!.oid)) {
      _selectedUser = null;
      _selectedUserGroups = [];
    }
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

  Future<void> _saveThemeModeSetting(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = switch (mode) {
      .light => 'light',
      .dark => 'dark',
      .system => 'system',
    };
    await prefs.setString('themeMode', modeStr);
    appThemeModeNotifier.value = mode;
    setState(() {
      _themeMode = mode;
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

      final prefs = await SharedPreferences.getInstance();
      final savedTemplates =
          prefs.getStringList(_customCategoriesPrefKey) ??
          prefs.getStringList('savedRoleCategoryTemplates') ??
          [];
      final (allRoles, groupCatalog, clusterName, isSsl) = await (
        _dbService.fetchAllRoles(forceRefresh: true),
        _dbService.fetchGroupCatalog(forceRefresh: true),
        _dbService.fetchClusterName(),
        _dbService.fetchSslStatus(),
      ).wait;
      final canCreateRole = await _dbService.canCurrentUserCreateRole();

      setState(() {
        _savedCategoryTemplates = savedTemplates;
        _users = allRoles.where((r) => r.canLogin).toList();
        _groups = allRoles.where((r) => !r.canLogin).toList();
        _groupCatalog = groupCatalog;
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

  static int _compareUsers(PgRole a, PgRole b) {
    if (a.isValid != b.isValid) {
      return a.isValid ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Future<void> _createNewUser() async {
    final result = await showDialog<PgRole>(
      context: context,
      builder: (context) => CreateUserDialog(dbService: _dbService),
    );

    if (result != null) {
      // Optimistically add to cache instead of full reload
      setState(() {
        if (result.canLogin) {
          _users.add(result);
          _users.sort(_compareUsers);
        }
        if (!result.canLogin) {
          _groups.add(result);
          _groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User "${result.name}" created successfully.')),
        );
      }
    }
  }

  Future<PgRole?> _handleEditUser(PgRole user) async {
    final updatedUser = await showDialog<PgRole>(
      context: context,
      builder: (context) => CreateUserDialog(
        dbService: _dbService,
        initialUser: user,
      ),
    );

    if (updatedUser != null && mounted) {
      setState(() {
        final idx = _users.indexWhere((u) => u.oid == user.oid || u.name == user.name);
        if (idx != -1) {
          _users[idx] = updatedUser;
        } else if (updatedUser.canLogin) {
          _users.add(updatedUser);
        }
        _users.sort(_compareUsers);
        if (_selectedUser?.oid == user.oid || _selectedUser?.name == user.name) {
          _selectedUser = updatedUser;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User "${updatedUser.name}" updated successfully.')),
      );
    }
    return updatedUser;
  }

  Future<PgRole?> _handleDuplicateUser(PgRole user, [List<PgUserGroup>? groups]) async {
    List<PgUserGroup> groupsToCopy = groups ?? [];
    if (groupsToCopy.isEmpty) {
      if (_selectedUser?.oid == user.oid && _selectedUserGroups.isNotEmpty) {
        groupsToCopy = _selectedUserGroups;
      } else {
        try {
          groupsToCopy = await _dbService.fetchGroupsForUser(user.oid);
        } catch (_) {}
      }
    }

    if (!mounted) return null;

    final newUser = await showDialog<PgRole>(
      context: context,
      builder: (context) => CreateUserDialog(
        dbService: _dbService,
        initialUser: user,
        isDuplicate: true,
        rolesToCopy: groupsToCopy,
      ),
    );

    if (newUser != null && mounted) {
      setState(() {
        _users.add(newUser);
        _users.sort(_compareUsers);
        _selectedUser = newUser;
      });

      try {
        final newGroups = await _dbService.fetchGroupsForUser(newUser.oid);
        if (mounted && _selectedUser?.oid == newUser.oid) {
          setState(() {
            _selectedUserGroups = newGroups;
          });
        }
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User "${newUser.name}" duplicated from "${user.name}".')),
        );
      }
    }
    return newUser;
  }

  Future<void> _selectUser(PgRole user, bool isNarrow) async {
    setState(() {
      _selectedUser = user;
      _isLoading = true;
    });

    try {
      final userGroups = await _dbService.fetchGroupsForUser(user.oid);
      if (!mounted || _selectedUser?.oid != user.oid) return;

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
              categoryTemplates: _allCategoryTemplates,
              roleSearchController: _roleSearchController,
              showDescriptions: _showDescriptions,
              showFilters: _showFilters,
              currentUsername: _dbService.username,
              onDeletePressed: _handleDeleteUser,
              onEditPressed: _canCreateRole ? _handleEditUser : null,
              onDuplicatePressed: _canCreateRole ? _handleDuplicateUser : null,
              dbService: _dbService,
              onRefresh: _refreshRolesData,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted && _selectedUser?.oid == user.oid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading memberships: $e')),
        );
      }
    } finally {
      if (mounted && _selectedUser?.oid == user.oid) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshRolesData() async {
    try {
      final (allRoles, groupCatalog, clusterName, isSsl) = await (
        _dbService.fetchAllRoles(forceRefresh: true),
        _dbService.fetchGroupCatalog(forceRefresh: true),
        _dbService.fetchClusterName(),
        _dbService.fetchSslStatus(),
      ).wait;
      List<PgUserGroup>? refreshedGroups;
      if (_selectedUser != null) {
        refreshedGroups = await _dbService.fetchGroupsForUser(_selectedUser!.oid, forceRefresh: true);
      }
      final canCreateRole = await _dbService.canCurrentUserCreateRole();
      if (!mounted) return;

      setState(() {
        _users = allRoles.where((r) => r.canLogin).toList();
        _groups = allRoles.where((r) => !r.canLogin).toList();
        _groupCatalog = groupCatalog;
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

    if (isUserList) {
      filtered = filtered.where(
        (r) => r.isAdmin && !r.isSuperuser && !r.isCurrent && r.name != _dbService.username,
      );
    } else {
      filtered = filtered.where((r) => r.isAdmin);
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

  bool _isUserEditable(PgRole user) {
    return _canCreateRole && user.isAdmin;
  }

  Future<void> _handleDeleteUser(PgRole user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete the user "${user.name}"? This action cannot be undone.'),
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
          SnackBar(content: Text('User "${user.name}" deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete user: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openSettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final sheetHeight = MediaQuery.of(context).size.height * 0.85;

            return SafeArea(
              child: SizedBox(
                height: sheetHeight,
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      Padding(
                        padding: const .fromLTRB(16, 12, 8, 4),
                        child: Row(
                          children: [
                            const Icon(Icons.settings),
                            const SizedBox(width: 8),
                            Text('Settings', style: theme.textTheme.titleLarge),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Close',
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      TabBar(
                        labelColor: theme.colorScheme.primary,
                        tabs: const [
                          Tab(icon: Icon(Icons.tune), text: 'General Preferences'),
                          Tab(icon: Icon(Icons.category_outlined), text: 'Role Categories'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildGeneralPreferencesTab(setModalState),
                            _buildRoleCategoriesTab(setModalState),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildGeneralPreferencesTab(void Function(void Function()) setModalState) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const .all(16.0),
      child: Column(
        mainAxisSize: .min,
        children: [
          SwitchListTile(
            title: const Text('Show Descriptions'),
            subtitle: const Text('Show user and role descriptions'),
            value: _showDescriptions,
            onChanged: (value) {
              _saveDescriptionsSetting(value);
              setModalState(() {});
            },
          ),
          const Divider(),
          Padding(
            padding: const .symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text('Theme', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(
                  'Choose light, dark, or system appearance',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: .system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto_outlined),
                      ),
                      ButtonSegment(
                        value: .light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: .dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                    ],
                    selected: {_themeMode},
                    onSelectionChanged: (selected) {
                      _saveThemeModeSetting(selected.first);
                      setModalState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildRoleCategoriesTab(void Function(void Function()) setModalState) {
    final theme = Theme.of(context);

    // Group only grantable roles by category so operators only see and manage their own roles
    final Map<String, List<PgUserGroup>> categoryMembers = {};
    final Map<String, PgUserGroup> categorySamples = {};

    final managedGroups = (_groupCatalog.isNotEmpty ? _groupCatalog : _selectedUserGroups)
        .where((r) => r.grantable)
        .toList();

    for (final g in managedGroups) {
      if (g.isDefaultUngrouped) {
        categoryMembers.putIfAbsent(_ungroupedCategoryKey, () => []).add(g);
        categorySamples.putIfAbsent(_ungroupedCategoryKey, () => g);
      } else {
        final raw = g.category!.trim();
        final catName = g.categoryName ?? raw;
        categoryMembers.putIfAbsent(catName, () => []).add(g);
        categorySamples.putIfAbsent(catName, () => g);
      }
    }

    for (final template in _savedCategoryTemplates) {
      final tName = PgUserGroup.parseCategory(template).name ?? template;
      if (!categoryMembers.containsKey(tName)) {
        categoryMembers[tName] = [];
        categorySamples[tName] = PgUserGroup(
          oid: 0,
          name: '',
          category: template,
          grantors: const [],
          grantable: true,
          granted: false,
        );
      }
    }

    final customCategoryCount =
        categoryMembers.keys.where((k) => k != _ungroupedCategoryKey).length;

    final sortedCategoryNames = categoryMembers.keys.toList()
      ..sort((a, b) {
        final sampleA = categorySamples[a]!;
        final sampleB = categorySamples[b]!;
        final orderA = sampleA.effectiveCategoryOrder;
        final orderB = sampleB.effectiveCategoryOrder;
        if (orderA != null && orderB != null && orderA != orderB) {
          return orderA.compareTo(orderB);
        } else if (orderA != null && orderB == null) {
          return -1;
        } else if (orderA == null && orderB != null) {
          return 1;
        }
        if (sampleA.isDefaultUngrouped != sampleB.isDefaultUngrouped) {
          return sampleA.isDefaultUngrouped ? 1 : -1;
        }
        return sampleA.effectiveCategoryName
            .toLowerCase()
            .compareTo(sampleB.effectiveCategoryName.toLowerCase());
      });

    return Column(
      crossAxisAlignment: .start,
      children: [
        Padding(
          padding: const .fromLTRB(16.0, 12.0, 16.0, 8.0),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          'Manage Categories',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: .bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Drag categories to set their sort order.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Category'),
                    onPressed: () => _addNewCategoryInSettings(
                      setModalState,
                      nextOrder: customCategoryCount + 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: sortedCategoryNames.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const .symmetric(vertical: 24.0, horizontal: 16.0),
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        Icon(Icons.category_outlined, size: 48, color: theme.disabledColor),
                        const SizedBox(height: 12),
                        Text('No role categories defined yet.', style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "New Category" to organize your roles into groups.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          textAlign: .center,
                        ),
                      ],
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const .symmetric(horizontal: 16.0, vertical: 8.0),
                  itemCount: sortedCategoryNames.length,
                  // ignore: deprecated_member_use
                  onReorder: (oldIndex, newIndex) async {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final item = sortedCategoryNames.removeAt(oldIndex);
                    sortedCategoryNames.insert(newIndex, item);

                    final batchUpdates = <String, String?>{};
                    for (int i = 0; i < sortedCategoryNames.length; i++) {
                      final cat = sortedCategoryNames[i];
                      final newOrder = i + 1;
                      final sample = categorySamples[cat]!;
                      final members = categoryMembers[cat]!;
                      final formatted = PgUserGroup.formatCategory(
                        name: sample.effectiveCategoryName,
                        order: newOrder,
                        colorHex: sample.effectiveCategoryColorHex,
                      );
                      if (cat == _ungroupedCategoryKey) {
                        await _dbService.saveUngroupedCategoryTemplate(formatted);
                      } else {
                        for (final member in members) {
                          batchUpdates[member.name] = formatted;
                        }
                        _savedCategoryTemplates.removeWhere(
                          (t) => PgUserGroup.categoryKey(t) == cat.toLowerCase(),
                        );
                        _savedCategoryTemplates.add(formatted);
                      }
                    }
                    if (batchUpdates.isNotEmpty) {
                      await _dbService.updateCategoriesBatch(batchUpdates);
                    }
                    await _saveCustomCategoryTemplates();
                    await _refreshRolesData();
                    setModalState(() {});
                  },
                  itemBuilder: (context, index) {
                    final catKey = sortedCategoryNames[index];
                    final isDefaultUngrouped = catKey == _ungroupedCategoryKey;
                    final sample = categorySamples[catKey]!;
                    final displayName = sample.effectiveCategoryName;
                    final members = categoryMembers[catKey]!;
                    final color = sample.effectiveCategoryColor;

                    return Card(
                      key: ValueKey(catKey),
                      margin: const .only(bottom: 8.0),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: color?.withValues(alpha: 0.5) ?? theme.dividerColor,
                          width: color != null ? 1.5 : 1.0,
                        ),
                        borderRadius: .circular(10),
                      ),
                      child: ListTile(
                        title: Text(
                          displayName,
                          style: const TextStyle(fontWeight: .bold),
                          overflow: .ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: .min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Edit Category',
                              onPressed: () => _editCategoryInSettings(
                                displayName,
                                sample,
                                members,
                                setModalState,
                                isDefaultUngrouped: isDefaultUngrouped,
                              ),
                            ),
                            if (!isDefaultUngrouped)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                tooltip: 'Delete Category',
                                onPressed: () => _deleteCategoryInSettings(displayName, members, setModalState),
                              ),
                            ReorderableDragStartListener(
                              index: index,
                              child: Padding(
                                padding: const .symmetric(horizontal: 4.0),
                                child: Icon(
                                  Icons.drag_handle,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _editCategoryInSettings(
    String catName,
    PgUserGroup sample,
    List<PgUserGroup> members,
    void Function(void Function()) setModalState, {
    bool isDefaultUngrouped = false,
  }) async {
    final result = await showDialog<EditRoleCategoryResult>(
      context: context,
      builder: (context) => EditRoleCategoryDialog(
        title: 'Edit Category "$catName"',
        subtitle: 'Configure category details and assign member roles.',
        currentCategory: isDefaultUngrouped ? sample.ungroupedTemplate : sample.category,
        defaultOrder: sample.effectiveCategoryOrder,
        availableRoles: _allAvailableGroupsWithCategories,
        initialSelectedRoleNames: members.map((r) => r.name).toList(),
        isDefaultUngrouped: isDefaultUngrouped,
      ),
    );

    if (result == null || !mounted) return;
    final newCategory = result.category;
    final normalized = newCategory.trim().isEmpty ? null : newCategory.trim();
    final newSelectedSet = result.assignedRoleNames.toSet();
    final previousMemberNames = members.map((r) => r.name).toSet();

    try {
      if (isDefaultUngrouped) {
        final newlyUngroupedNames =
            newSelectedSet.difference(previousMemberNames).toList();
        if (newlyUngroupedNames.isNotEmpty) {
          await _dbService.updateCategoriesBatch({
            for (final name in newlyUngroupedNames) name: null,
          });
        }
        await _dbService.saveUngroupedCategoryTemplate(
          normalized ?? PgUserGroup.defaultUngroupedTemplate,
        );
      } else {
        final removedRoleNames =
            previousMemberNames.difference(newSelectedSet).toList();
        final assignedRoleNames = newSelectedSet.toList();
        final batchUpdates = <String, String?>{
          for (final name in removedRoleNames) name: null,
          if (normalized != null)
            for (final name in assignedRoleNames) name: normalized,
        };
        if (batchUpdates.isNotEmpty) {
          await _dbService.updateCategoriesBatch(batchUpdates);
        }
        _savedCategoryTemplates.removeWhere(
          (t) => PgUserGroup.categoryKey(t) == catName.toLowerCase(),
        );
        if (normalized != null) {
          _savedCategoryTemplates.add(normalized);
        }
        await _saveCustomCategoryTemplates();
      }

      await _refreshRolesData();
      if (mounted) {
        setModalState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Category "$catName" updated across ${newSelectedSet.length} role(s).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update category: $e')),
        );
      }
    }
  }

  Future<void> _deleteCategoryInSettings(
    String catName,
    List<PgUserGroup> members,
    void Function(void Function()) setModalState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Are you sure you want to delete category "$catName"?\n'
          'This will remove the category from ${members.length} role(s), making them Ungrouped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      if (members.isNotEmpty) {
        await _dbService.updateCategoryForRoles(members.map((r) => r.name), null);
      }
      _savedCategoryTemplates.removeWhere(
        (t) => PgUserGroup.categoryKey(t) == catName.toLowerCase(),
      );
      await _saveCustomCategoryTemplates();

      await _refreshRolesData();
      if (mounted) {
        setModalState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Category "$catName" deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete category: $e')),
        );
      }
    }
  }

  Future<void> _addNewCategoryInSettings(void Function(void Function()) setModalState, {int? nextOrder}) async {
    final result = await showDialog<EditRoleCategoryResult>(
      context: context,
      builder: (context) => EditRoleCategoryDialog(
        title: 'New Role Category',
        subtitle: 'Define a category and assign member roles.',
        defaultOrder: nextOrder,
        availableRoles: _allAvailableGroupsWithCategories,
        initialSelectedRoleNames: const [],
      ),
    );

    if (result == null || !mounted) return;

    try {
      if (result.assignedRoleNames.isNotEmpty) {
        await _dbService.updateCategoryForRoles(result.assignedRoleNames, result.category);
      }
      _savedCategoryTemplates.add(result.category);
      await _saveCustomCategoryTemplates();

      await _refreshRolesData();
      if (mounted) {
        setModalState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.assignedRoleNames.isNotEmpty
                  ? 'Category created and assigned to ${result.assignedRoleNames.length} role(s).'
                  : 'Category created successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create category: $e')),
        );
      }
    }
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
      onAddPressed: _canCreateRole ? _createNewUser : null,
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
          if (_selectedUser != null && _isUserEditable(_selectedUser!) && !isNarrow)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit User',
              onPressed: () => _handleEditUser(_selectedUser!),
            ),
          if (_selectedUser != null && _canCreateRole && !isNarrow)
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Duplicate User',
              onPressed: () => _handleDuplicateUser(_selectedUser!),
            ),
          if (_selectedUser != null && _selectedUser!.canDrop && !isNarrow)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete User',
              onPressed: () => _handleDeleteUser(_selectedUser!),
            ),
          IconButton(
            icon: Icon(_showFilters ? Icons.search_off : Icons.search),
            tooltip: _showFilters ? 'Hide Filters' : 'Search',
            onPressed: () {
              if (_showFilters) {
                _handleEscape();
              } else {
                _activateSearchFilters();
              }
            },
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
            .touch,
            .mouse,
            .trackpad,
            .stylus,
          },
        ),
        child: _isLoading && _users.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _users.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: .center,
                      children: [
                        Text('Error: $_error', style: const TextStyle(color: Colors.red), textAlign: .center),
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
                                    categoryTemplates: _allCategoryTemplates,
                                    isLoading: _isLoading,
                                    roleSearchController: _roleSearchController,
                                    roleSearchFocusNode: _roleSearchFocusNode,
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
        port: _dbService.port,
        database: _dbService.database,
        username: _dbService.username,
        isSslEnabled: _isSslEnabled,
        onTap: _openConnectionSettings,
      ),
    );
  }
}
