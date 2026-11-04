import 'package:postgres/postgres.dart';
import 'package:user_manager/models/pg_membership.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/models/pg_user_group.dart';
import 'package:user_manager/services/database_service.dart';

class FakeDatabaseService extends DatabaseService {
  String? testConnectionResult;
  bool isSuperuserResult;
  bool canCreateRoleResult;
  bool canSetCategoryParameterResult;
  List<PgRole> mockRoles;
  List<PgMembership> mockMemberships;
  Map<int, List<PgUserGroup>>? mockUserGroups;
  String mockClusterName;
  bool mockSslStatus;

  Object? throwOnFetchAllRoles;
  Object? throwOnTestConnection;

  int testConnectionCalls = 0;
  int isCurrentUserSuperuserCalls = 0;
  int canCurrentUserCreateRoleCalls = 0;
  int canCurrentUserSetCategoryParameterCalls = 0;
  int fetchAllRolesCalls = 0;
  int fetchClusterNameCalls = 0;
  int fetchSslStatusCalls = 0;
  int fetchGroupsForUserCalls = 0;
  int clearCacheCalls = 0;
  int closeCalls = 0;

  final List<String> grantedRoles = [];
  final List<String> revokedRoles = [];
  final List<String> droppedRoles = [];
  final Map<String, Map<String, String?>> _scopedRoleCategories = {};

  Map<String, String?> get roleCategories =>
      _scopedRoleCategories.putIfAbsent(categoryStorageScope, () => {});

  FakeDatabaseService({
    super.host = 'localhost',
    super.port = 5432,
    super.database = 'postgres',
    super.username = 'test_user',
    super.password = '',
    super.sslMode = SslMode.disable,
    this.testConnectionResult,
    this.isSuperuserResult = false,
    this.canCreateRoleResult = true,
    this.canSetCategoryParameterResult = true,
    List<PgRole>? roles,
    List<PgMembership>? memberships,
    this.mockClusterName = 'test_cluster',
    this.mockSslStatus = true,
    this.mockUserGroups,
  })  : mockRoles = roles ?? [],
        mockMemberships = memberships ?? [];

  @override
  Future<List<PgUserGroup>> fetchGroupsForUser(int userOid, {bool forceRefresh = false}) async {
    fetchGroupsForUserCalls++;
    final storedCategories = await loadRoleCategories();
    final currentCategories = roleCategories;
    if (mockUserGroups != null && mockUserGroups!.containsKey(userOid)) {
      final groups = mockUserGroups![userOid]!.map((g) {
        if (currentCategories.containsKey(g.name)) {
          final cat = currentCategories[g.name];
          return g.copyWith(category: cat, clearCategory: cat == null);
        } else if (storedCategories.containsKey(g.name)) {
          return g.copyWith(category: storedCategories[g.name]);
        }
        return g;
      }).toList();
      groups.sort(DatabaseService.compareGroups);
      return groups;
    }
    // Default fallback: generate from mockRoles (groups) and mockMemberships
    final groups = mockRoles.where((r) => !r.canLogin).map((g) {
      final relevantMemberships = mockMemberships.where(
        (m) => m.roleOid == g.oid && m.memberOid == userOid,
      ).toList();

      final otherGrantors = relevantMemberships
          .where((m) => m.grantor != username)
          .map((m) => m.grantor)
          .toList();

      final isGrantedByMe = relevantMemberships.any((m) => m.grantor == username);

      final cat = currentCategories.containsKey(g.name)
          ? currentCategories[g.name]
          : storedCategories[g.name];

      return PgUserGroup(
        oid: g.oid,
        name: g.name,
        description: g.description,
        grantors: otherGrantors,
        grantable: g.canManage,
        granted: isGrantedByMe,
        category: cat,
      );
    }).toList();

    groups.sort(DatabaseService.compareGroups);

    return groups;
  }

  @override
  Future<List<PgUserGroup>> fetchGroupCatalog({bool forceRefresh = false}) async {
    if (mockUserGroups != null && mockUserGroups!.isNotEmpty) {
      final firstKey = mockUserGroups!.keys.first;
      return fetchGroupsForUser(firstKey, forceRefresh: forceRefresh);
    }
    return fetchGroupsForUser(0, forceRefresh: forceRefresh);
  }

  @override
  Future<void> setRoleCategory(String roleName, String? category) async {
    final trimmed = category?.trim();
    roleCategories[roleName] = (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
    await super.setRoleCategory(roleName, category);
  }

  @override
  Future<void> updateCategoryForRoles(Iterable<String> roleNames, String? newCategory) async {
    final trimmed = newCategory?.trim();
    for (final roleName in roleNames) {
      roleCategories[roleName] = (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
    }
    await super.updateCategoryForRoles(roleNames, newCategory);
  }

  @override
  Future<void> updateCategoriesBatch(Map<String, String?> updates) async {
    for (final entry in updates.entries) {
      final trimmed = entry.value?.trim();
      roleCategories[entry.key] = (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
    }
    await super.updateCategoriesBatch(updates);
  }

  @override
  Future<String?> testConnection() async {
    testConnectionCalls++;
    if (throwOnTestConnection != null) {
      throw throwOnTestConnection!;
    }
    return testConnectionResult;
  }

  @override
  Future<bool> isCurrentUserSuperuser({bool forceRefresh = false}) async {
    isCurrentUserSuperuserCalls++;
    return isSuperuserResult;
  }

  @override
  Future<bool> canCurrentUserCreateRole({bool forceRefresh = false}) async {
    canCurrentUserCreateRoleCalls++;
    final currentRole = mockRoles.where((r) => r.isCurrent).firstOrNull;
    if (currentRole != null) {
      return currentRole.isSuperuser || currentRole.createRole;
    }
    return canCreateRoleResult;
  }

  @override
  Future<bool> canCurrentUserSetCategoryParameter({bool forceRefresh = false}) async {
    canCurrentUserSetCategoryParameterCalls++;
    return canSetCategoryParameterResult;
  }

  @override
  void clearCache() {
    clearCacheCalls++;
    super.clearCache();
  }

  @override
  Future<List<PgRole>> fetchAllRoles({bool forceRefresh = false}) async {
    fetchAllRolesCalls++;
    if (forceRefresh) {
      clearCache();
    }
    if (throwOnFetchAllRoles != null) {
      throw throwOnFetchAllRoles!;
    }
    return List.of(mockRoles);
  }

  @override
  Future<PgRole?> fetchCurrentUserRole({bool forceRefresh = false}) async {
    final allRoles = await fetchAllRoles(forceRefresh: forceRefresh);
    return allRoles.where((r) => r.isCurrent || r.name == username).firstOrNull;
  }

  @override
  Future<PgRole?> fetchRoleByName(String name, {bool fromCache = true}) async {
    try {
      return mockRoles.firstWhere((r) => r.name == name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> fetchClusterName() async {
    fetchClusterNameCalls++;
    return mockClusterName;
  }

  @override
  Future<bool> fetchSslStatus() async {
    fetchSslStatusCalls++;
    return mockSslStatus;
  }

  @override
  Future<void> grantRole(String userName, String roleName, {int? userOid}) async {
    grantedRoles.add('$userName:$roleName');
  }

  @override
  Future<void> revokeRole(String userName, String roleName, {int? userOid}) async {
    revokedRoles.add('$userName:$roleName');
  }

  @override
  Future<void> dropRole(String name) async {
    droppedRoles.add(name);
    mockRoles.removeWhere((r) => r.name == name);
  }

  @override
  Future<PgRole> createRole({
    required String name,
    String? description,
    String? password,
    DateTime? validUntil,
    bool isSuper = false,
    bool inherit = true,
    bool createRole = false,
    bool createDb = false,
    bool canLogin = true,
    bool replication = false,
    bool bypassRls = false,
  }) async {
    final newRole = PgRole(
      oid: mockRoles.length + 1000,
      name: name,
      canLogin: canLogin,
      isSuperuser: isSuper,
      description: description ?? '',
      inherit: inherit,
      createRole: createRole,
      createDb: createDb,
      replication: replication,
      bypassRls: bypassRls,
      canManage: true,
      canDrop: true,
      validUntil: validUntil,
    );
    mockRoles.add(newRole);
    return newRole;
  }

  @override
  Future<PgRole> updateRole({
    required String oldName,
    required String name,
    String? description,
    String? password,
    DateTime? validUntil,
  }) async {
    final index = mockRoles.indexWhere((r) => r.name == oldName);
    final existing = index != -1 ? mockRoles[index] : null;
    final updated = PgRole(
      oid: existing?.oid ?? (mockRoles.length + 1000),
      name: name,
      canLogin: existing?.canLogin ?? true,
      isSuperuser: existing?.isSuperuser ?? false,
      description: (description != null && description.trim().isNotEmpty)
          ? description.trim()
          : null,
      inherit: existing?.inherit ?? true,
      createRole: existing?.createRole ?? false,
      createDb: existing?.createDb ?? false,
      replication: existing?.replication ?? false,
      bypassRls: existing?.bypassRls ?? false,
      isCurrent: existing?.isCurrent ?? false,
      isAdmin: existing?.isAdmin ?? true,
      canDrop: existing?.canDrop ?? true,
      validUntil: validUntil,
    );
    if (index != -1) {
      mockRoles[index] = updated;
    } else {
      mockRoles.add(updated);
    }
    return updated;
  }

  @override
  Future<void> close({bool force = false}) async {
    closeCalls++;
  }
}
