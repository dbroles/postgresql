import 'package:postgres/postgres.dart';
import 'package:user_manager/models/pg_membership.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/models/pg_user_group.dart';
import 'package:user_manager/services/database_service.dart';

class FakeDatabaseService extends DatabaseService {
  String? testConnectionResult;
  bool isSuperuserResult;
  List<PgRole> mockRoles;
  List<PgMembership> mockMemberships;
  Map<int, List<PgUserGroup>>? mockUserGroups;
  String mockClusterName;
  bool mockSslStatus;

  Object? throwOnFetchAllRoles;
  Object? throwOnTestConnection;

  int testConnectionCalls = 0;
  int isCurrentUserSuperuserCalls = 0;
  int fetchAllRolesCalls = 0;
  int fetchClusterNameCalls = 0;
  int fetchSslStatusCalls = 0;
  int fetchGroupsForUserCalls = 0;
  int clearCacheCalls = 0;
  int closeCalls = 0;

  final List<String> grantedRoles = [];
  final List<String> revokedRoles = [];
  final List<String> droppedRoles = [];

  FakeDatabaseService({
    super.host = 'localhost',
    super.port = 5432,
    super.username = 'test_user',
    super.password = '',
    super.sslMode = SslMode.disable,
    this.testConnectionResult,
    this.isSuperuserResult = false,
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
    if (mockUserGroups != null && mockUserGroups!.containsKey(userOid)) {
      return List.of(mockUserGroups![userOid]!);
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

      return PgUserGroup(
        oid: g.oid,
        name: g.name,
        description: g.description,
        grantors: otherGrantors,
        grantable: g.canManage,
        granted: isGrantedByMe,
      );
    }).toList();

    return groups;
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
    );
    mockRoles.add(newRole);
    return newRole;
  }

  @override
  Future<void> close({bool force = false}) async {
    closeCalls++;
  }
}
