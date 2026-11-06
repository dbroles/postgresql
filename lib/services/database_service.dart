import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pg_role.dart';
import '../models/pg_user_group.dart';

class DatabaseService {
  String _host;
  int _port;
  String _database;
  String _username;
  String _password;
  SslMode _sslMode;

  Pool? _pool;

  List<PgRole>? _cachedRoles;
  List<PgUserGroup>? _cachedGroupCatalog;
  final Map<int, Map<int, ({bool granted, List<String> grantors})>> _cachedUserMemberships = {};
  String? _cachedClusterName;
  bool? _cachedIsSuperuser;
  bool? _cachedCanCreateRole;
  bool? _cachedCanSetCategoryParameter;
  int? _cachedCurrentUserOid;

  DatabaseService({
    String host = 'localhost',
    int port = 5432,
    String database = 'postgres',
    String username = 'dbroles',
    String password = '',
    SslMode sslMode = SslMode.require,
  })  : _host = host,
        _port = port,
        _database = database,
        _username = username,
        _password = password,
        _sslMode = sslMode;

  String get host => _host;
  set host(String value) {
    if (_host != value) {
      _host = value;
      _resetPool();
    }
  }

  int get port => _port;
  set port(int value) {
    if (_port != value) {
      _port = value;
      _resetPool();
    }
  }

  String get database => _database;
  set database(String value) {
    if (_database != value) {
      _database = value;
      _resetPool();
    }
  }

  String get username => _username;
  set username(String value) {
    if (_username != value) {
      _username = value;
      _resetPool();
    }
  }

  String get password => _password;
  set password(String value) {
    if (_password != value) {
      _password = value;
      _resetPool();
    }
  }

  SslMode get sslMode => _sslMode;
  set sslMode(SslMode value) {
    if (_sslMode != value) {
      _sslMode = value;
      _resetPool();
    }
  }

  /// Safely quotes and escapes a PostgreSQL identifier (role name, table name, etc.).
  /// Encloses in double quotes and doubles any embedded double quotes.
  /// Throws [ArgumentError] if the identifier contains null characters.
  static String escapeIdentifier(String identifier) {
    if (identifier.contains('\u0000')) {
      throw ArgumentError('PostgreSQL identifier cannot contain null characters.');
    }
    return '"${identifier.replaceAll('"', '""')}"';
  }

  /// Safely quotes and escapes a PostgreSQL string literal (password, comment, etc.).
  /// Encloses in single quotes and doubles any embedded single quotes.
  /// Throws [ArgumentError] if the literal contains null characters.
  static String escapeLiteral(String literal) {
    if (literal.contains('\u0000')) {
      throw ArgumentError('PostgreSQL string literal cannot contain null characters.');
    }
    return "'${literal.replaceAll("'", "''")}'";
  }

  void resetCache() {
    _cachedRoles = null;
    _cachedGroupCatalog = null;
    _cachedUserMemberships.clear();
    _cachedClusterName = null;
    _cachedIsSuperuser = null;
    _cachedCanCreateRole = null;
    _cachedCanSetCategoryParameter = null;
    _cachedCurrentUserOid = null;
  }

  void _resetPool() {
    _pool?.close();
    _pool = null;
    resetCache();
  }

  Pool _getPool() {
    if (_pool != null && _pool!.isOpen) {
      return _pool!;
    }
    _pool = Pool.withEndpoints(
      [
        Endpoint(
          host: _host,
          port: _port,
          database: database,
          username: _username,
          password: _password,
        ),
      ],
      settings: PoolSettings(
        sslMode: _sslMode,
        applicationName: 'User Manager',
        maxConnectionCount: 5,
        maxConnectionAge: const Duration(minutes: 30),
        maxSessionUse: const Duration(minutes: 5),
        connectTimeout: const Duration(seconds: 15),
      ),
    );
    return _pool!;
  }

  Future<void> close({bool force = false}) async {
    if (_pool != null) {
      await _pool!.close(force: force);
      _pool = null;
    }
  }

  Future<String?> testConnection() async {
    try {
      final conn = await Connection.open(
        Endpoint(
          host: _host,
          port: _port,
          database: database,
          username: _username,
          password: _password,
        ),
        settings: ConnectionSettings(
          sslMode: _sslMode,
          applicationName: 'User Manager',
          connectTimeout: const Duration(seconds: 10),
        ),
      );
      await conn.close();
      return null; // Success
    } catch (e) {
      return e.toString();
    }
  }

  /// Scope identifier (`host:login:database`) used to isolate local settings per connection.
  String get categoryStorageScope => '$_host:$_username:$_database';

  String get _roleCategoriesPrefKey => 'role_categories_$categoryStorageScope';

  Future<Map<String, String>> loadRoleCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_roleCategoriesPrefKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  Future<void> _saveRoleCategories(Map<String, String> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleCategoriesPrefKey, jsonEncode(categories));
  }

  Future<void> _fetchCurrentUserInfo({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedCurrentUserOid != null && _cachedCanSetCategoryParameter != null) return;
    final pool = _getPool();
    final result = await pool.execute(
      'SELECT oid::int, rolsuper, (rolsuper OR rolcreaterole) AS can_create_role FROM pg_roles WHERE rolname = current_user',
    );
    if (result.isNotEmpty) {
      _cachedCurrentUserOid = result.first[0] as int;
      _cachedIsSuperuser = result.first[1] as bool;
      _cachedCanCreateRole = result.first[2] as bool;
      _cachedCanSetCategoryParameter = true;
    }
  }

  Future<bool> isCurrentUserSuperuser({bool forceRefresh = false}) async {
    await _fetchCurrentUserInfo(forceRefresh: forceRefresh);
    return _cachedIsSuperuser ?? false;
  }

  Future<bool> canCurrentUserCreateRole({bool forceRefresh = false}) async {
    await _fetchCurrentUserInfo(forceRefresh: forceRefresh);
    return _cachedCanCreateRole ?? false;
  }

  Future<bool> canCurrentUserSetCategoryParameter({bool forceRefresh = false}) async {
    return _cachedCanSetCategoryParameter ?? true;
  }

  Future<void> setupRoleAdmin(String adminName, String adminPass) async {
    final pool = _getPool();
    await pool.withConnection((conn) async {
      // 1. Check if role exists
      final checkResult = await conn.execute(
        r'SELECT count(*) FROM pg_roles WHERE rolname = $1',
        parameters: [adminName],
      );
      final exists = (checkResult.first[0] as int) > 0;

      final safeAdmin = escapeIdentifier(adminName);
      final safePass = escapeLiteral(adminPass);

      // 2. Create or Alter role
      if (!exists) {
        await conn.execute('CREATE ROLE $safeAdmin WITH LOGIN CREATEROLE PASSWORD $safePass');
      } else {
        await conn.execute('ALTER ROLE $safeAdmin WITH LOGIN CREATEROLE PASSWORD $safePass');
      }

      // 3. Set standard description
      await conn.execute('COMMENT ON ROLE $safeAdmin IS ${escapeLiteral('grant and revoke roles to users')}');

      // 4. Grant ADMIN OPTION on all non-login roles (groups)
      // We skip system roles (pg_*, rds_*, cloudsql*, azure_*) because some do not allow members.
      final groupsResult = await conn.execute(
        "SELECT rolname FROM pg_roles WHERE rolcanlogin = false AND rolname NOT LIKE 'pg_%' AND rolname NOT LIKE 'rds%' AND rolname NOT LIKE 'cloudsql%' AND rolname NOT LIKE 'azure_%'",
      );
      for (final row in groupsResult) {
        final groupName = row[0] as String;
        try {
          await conn.execute('GRANT ${escapeIdentifier(groupName)} TO $safeAdmin WITH ADMIN OPTION');
        } catch (_) {
          // Ignore provider-managed roles that cannot be granted WITH ADMIN OPTION
        }
      }
    });

    // Bulk update: easier to just re-fetch everything as many roles may have been affected
    await fetchAllRoles(forceRefresh: true);
    _cachedGroupCatalog = null;
    _cachedUserMemberships.clear();
  }

  void clearCache() {
    _cachedRoles = null;
    _cachedGroupCatalog = null;
    _cachedUserMemberships.clear();
    _cachedCanSetCategoryParameter = null;
  }

  Future<List<PgRole>> fetchAllRoles({bool forceRefresh = false}) async {
    if (forceRefresh || _cachedRoles == null) {
      _cachedRoles = await _queryRoles(forceRefresh: forceRefresh);
      final current = _cachedRoles!.where((r) => r.isCurrent).firstOrNull;
      if (current != null) {
        _cachedCurrentUserOid = current.oid;
        _cachedIsSuperuser = current.isSuperuser;
        _cachedCanCreateRole = current.isSuperuser || current.createRole;
        _cachedCanSetCategoryParameter = true;
      }
    }
    return _cachedRoles!;
  }

  Future<PgRole?> fetchCurrentUserRole({bool forceRefresh = false}) async {
    final allRoles = await fetchAllRoles(forceRefresh: forceRefresh);
    return allRoles.where((r) => r.isCurrent || r.name == username).firstOrNull;
  }

  Future<PgRole?> fetchRoleByName(String name, {bool fromCache = true}) async {
    if (fromCache && _cachedRoles != null) {
      try {
        return _cachedRoles!.firstWhere((r) => r.name == name);
      } catch (_) {
        // Fall through to DB if not in cache
      }
    }
    final results = await _queryRoles(name: name);
    return results.isEmpty ? null : results.first;
  }

  Future<List<PgRole>> _queryRoles({String? name, bool forceRefresh = false}) async {
    final pool = _getPool();
    final result = await pool.execute(
      '''
      WITH me AS (
          SELECT 
              current_setting('is_superuser') = 'on' AS is_super,
              rolcreaterole AS can_create
          FROM pg_catalog.pg_roles
          WHERE rolname = CURRENT_USER
      ),
      user_roles AS (
          SELECT
              r.oid::int,
              r.rolname AS name,
              r.rolsuper AS is_superuser,
              r.rolinherit AS inherit,
              r.rolcreaterole AS create_role,
              r.rolcreatedb AS create_db,
              r.rolcanlogin AS can_login,
              r.rolreplication AS replication,
              r.rolbypassrls AS bypass_rls,
              (CURRENT_USER = r.rolname) AS is_current,
              pg_catalog.shobj_description(r.oid, 'pg_authid') AS description,
              (
                  me.is_super
                  OR EXISTS (
                      SELECT 1 FROM pg_catalog.pg_auth_members m
                      WHERE m.roleid = r.oid
                        AND m.member = CURRENT_USER::regrole::oid
                        AND m.admin_option = true
                  )
              ) AS is_admin,
              CASE
                  WHEN r.rolvaliduntil IS NOT NULL AND isfinite(r.rolvaliduntil)
                  THEN to_char(r.rolvaliduntil, 'YYYY-MM-DD')
              END AS valid_until,
              (r.rolvaliduntil IS NULL OR r.rolvaliduntil > CURRENT_TIMESTAMP) AS is_valid,
              (
                  r.rolvaliduntil IS NOT NULL
                  AND isfinite(r.rolvaliduntil)
                  AND r.rolvaliduntil > CURRENT_TIMESTAMP
                  AND r.rolvaliduntil <= CURRENT_TIMESTAMP + INTERVAL '7 days'
              ) AS is_expiring_soon,
              me.is_super,
              me.can_create
          FROM pg_catalog.pg_roles r
          CROSS JOIN me
          ${name != null ? 'WHERE r.rolname = \$1' : ''}
      )
      SELECT
          oid,
          name,
          is_superuser,
          inherit,
          create_role,
          create_db,
          can_login,
          replication,
          bypass_rls,
          is_current,
          description,
          is_admin,
          (is_admin AND (is_super OR can_create)) AS can_drop,
          valid_until,
          is_valid,
          is_expiring_soon
      FROM user_roles
      ORDER BY is_valid DESC, LOWER(name) ASC
    ''',
      parameters: name != null ? [name] : null,
    );
    return result.map((row) => PgRole.fromRow(row)).toList();
  }

  Future<String> fetchClusterName() async {
    if (_cachedClusterName != null) return _cachedClusterName!;
    
    final pool = _getPool();
    final result = await pool.execute("SELECT current_setting('cluster_name')");
    _cachedClusterName = result.first[0] as String;
    return _cachedClusterName!;
  }

  Future<bool> fetchSslStatus() async {
    final pool = _getPool();
    final result = await pool.execute("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()");
    if (result.isEmpty) return false;
    return result.first[0] as bool;
  }

  Future<List<PgUserGroup>> _fetchGroupCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedGroupCatalog != null) {
      return _cachedGroupCatalog!;
    }

    final pool = _getPool();
    final result = await pool.execute(
      r'''
      SELECT 
          g.oid::int,
          g.rolname AS name,
          pg_catalog.shobj_description(g.oid, 'pg_authid') AS description,
          '{}'::text[] AS grantors,
          (COALESCE(bool_or(me.admin_option), false) OR current_setting('is_superuser') = 'on') AS grantable,
          false AS granted
      FROM pg_catalog.pg_roles g
      LEFT JOIN pg_catalog.pg_auth_members me
          ON g.oid = me.roleid
         AND me.member = CURRENT_USER::regrole::oid
         AND me.admin_option = true
      WHERE NOT g.rolcanlogin
      GROUP BY g.oid, g.rolname
      ORDER BY LOWER(g.rolname) ASC;
      ''',
    );

    final categories = await loadRoleCategories();
    final groups = result.map((row) {
      final group = PgUserGroup.fromRow(row);
      final cat = categories[group.name];
      return cat != null ? group.copyWith(category: cat) : group;
    }).toList();
    groups.sort(compareGroups);

    _cachedGroupCatalog = groups;
    return _cachedGroupCatalog!;
  }

  static int compareGroups(PgUserGroup a, PgUserGroup b) {
    final orderA = a.categoryOrder;
    final orderB = b.categoryOrder;
    if (orderA != null && orderB != null && orderA != orderB) {
      return orderA.compareTo(orderB);
    } else if (orderA != null && orderB == null) {
      return -1;
    } else if (orderA == null && orderB != null) {
      return 1;
    }
    final catA = a.categoryName?.toLowerCase();
    final catB = b.categoryName?.toLowerCase();
    if (catA != null && catB != null) {
      final cmp = catA.compareTo(catB);
      if (cmp != 0) return cmp;
    } else if (catA != null) {
      return -1;
    } else if (catB != null) {
      return 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Future<Map<int, ({bool granted, List<String> grantors})>> _fetchUserMemberships(
    int userOid, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedUserMemberships.containsKey(userOid)) {
      return _cachedUserMemberships[userOid]!;
    }

    final pool = _getPool();
    final result = await pool.execute(
      r'''
      SELECT
          m.roleid::int,
          COALESCE(bool_or(m.grantor = CURRENT_USER::regrole::oid), false) AS granted,
          COALESCE(
              array_agg(m.grantor::regrole::text ORDER BY m.grantor::regrole::text)
              FILTER (WHERE m.grantor IS NOT NULL AND m.grantor <> CURRENT_USER::regrole::oid),
              '{}'::text[]
          ) AS grantors
      FROM pg_catalog.pg_auth_members m
      WHERE m.member = $1::oid
      GROUP BY m.roleid;
      ''',
      parameters: [userOid],
    );

    final memberships = <int, ({bool granted, List<String> grantors})>{};
    for (final row in result) {
      final roleOid = row[0] as int;
      final granted = (row[1] as bool?) ?? false;
      final grantors = PgUserGroup.parseGrantors(row[2]);
      memberships[roleOid] = (granted: granted, grantors: grantors);
    }

    _cachedUserMemberships[userOid] = memberships;
    return memberships;
  }

  Future<List<PgUserGroup>> fetchGroupCatalog({bool forceRefresh = false}) async {
    return _fetchGroupCatalog(forceRefresh: forceRefresh);
  }

  Future<List<PgUserGroup>> fetchGroupsForUser(int userOid, {bool forceRefresh = false}) async {
    final (catalog, memberships) = await (
      _fetchGroupCatalog(forceRefresh: forceRefresh),
      _fetchUserMemberships(userOid, forceRefresh: forceRefresh),
    ).wait;

    return catalog.map((group) {
      final membership = memberships[group.oid];
      return group.copyWith(
        granted: membership?.granted ?? false,
        grantors: membership?.grantors ?? const [],
      );
    }).toList();
  }

  Future<void> setRoleCategory(String roleName, String? category) async {
    final categories = await loadRoleCategories();
    final trimmed = category?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      categories[roleName] = trimmed;
    } else {
      categories.remove(roleName);
    }
    await _saveRoleCategories(categories);
    _cachedGroupCatalog = null;
  }

  Future<void> updateCategoryForRoles(Iterable<String> roleNames, String? newCategory) async {
    final categories = await loadRoleCategories();
    final trimmed = newCategory?.trim();
    for (final roleName in roleNames) {
      if (trimmed != null && trimmed.isNotEmpty) {
        categories[roleName] = trimmed;
      } else {
        categories.remove(roleName);
      }
    }
    await _saveRoleCategories(categories);
    _cachedGroupCatalog = null;
  }

  Future<void> updateCategoriesBatch(Map<String, String?> updates) async {
    if (updates.isEmpty) return;
    final categories = await loadRoleCategories();
    for (final entry in updates.entries) {
      final trimmed = entry.value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        categories[entry.key] = trimmed;
      } else {
        categories.remove(entry.key);
      }
    }
    await _saveRoleCategories(categories);
    _cachedGroupCatalog = null;
  }

  Future<void> grantRole(String userName, String roleName, {int? userOid}) async {
    final pool = _getPool();
    // DDL statements like GRANT cannot use parameters for identifiers ($1)
    await pool.execute('GRANT ${escapeIdentifier(roleName)} TO ${escapeIdentifier(userName)}');

    if (userOid != null && _cachedUserMemberships.containsKey(userOid) && _cachedGroupCatalog != null) {
      final group = _cachedGroupCatalog!.where((g) => g.name == roleName).firstOrNull;
      if (group != null) {
        final existing = _cachedUserMemberships[userOid]![group.oid];
        _cachedUserMemberships[userOid]![group.oid] = (
          granted: true,
          grantors: existing?.grantors ?? const [],
        );
      }
    } else if (userOid != null) {
      _cachedUserMemberships.remove(userOid);
    }
  }

  Future<void> revokeRole(String userName, String roleName, {int? userOid}) async {
    final pool = _getPool();
    await pool.execute('REVOKE ${escapeIdentifier(roleName)} FROM ${escapeIdentifier(userName)}');

    if (userOid != null && _cachedUserMemberships.containsKey(userOid) && _cachedGroupCatalog != null) {
      final group = _cachedGroupCatalog!.where((g) => g.name == roleName).firstOrNull;
      if (group != null) {
        final existing = _cachedUserMemberships[userOid]![group.oid];
        _cachedUserMemberships[userOid]![group.oid] = (
          granted: false,
          grantors: existing?.grantors ?? const [],
        );
      }
    } else if (userOid != null) {
      _cachedUserMemberships.remove(userOid);
    }
  }

  Future<void> dropRole(String name) async {
    final pool = _getPool();
    final roleToDrop = _cachedRoles?.where((r) => r.name == name).firstOrNull;
    
    await pool.execute('DROP ROLE ${escapeIdentifier(name)}');
    
    if (roleToDrop != null) {
      _cachedRoles?.removeWhere((r) => r.name == name);
      _cachedGroupCatalog = null;
      _cachedUserMemberships.clear();
    }

    final categories = await loadRoleCategories();
    if (categories.remove(name) != null) {
      await _saveRoleCategories(categories);
    }
  }

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
    final List<String> options = [];
    if (isSuper) {
      options.add('SUPERUSER');
    } else {
      options.add('NOSUPERUSER');
    }
    
    if (inherit) {
      options.add('INHERIT');
    } else {
      options.add('NOINHERIT');
    }
    
    if (createRole) {
      options.add('CREATEROLE');
    } else {
      options.add('NOCREATEROLE');
    }
    
    if (createDb) {
      options.add('CREATEDB');
    } else {
      options.add('NOCREATEDB');
    }
    
    if (canLogin) {
      options.add('LOGIN');
    } else {
      options.add('NOLOGIN');
    }
    
    if (replication) {
      options.add('REPLICATION');
    } else {
      options.add('NOREPLICATION');
    }
    
    if (bypassRls) {
      options.add('BYPASSRLS');
    } else {
      options.add('NOBYPASSRLS');
    }

    if (password != null && password.isNotEmpty) {
      options.add('PASSWORD ${escapeLiteral(password)}');
    }

    if (validUntil != null) {
      options.add('VALID UNTIL ${escapeLiteral(PgRole.formatDate(validUntil))}');
    }

    final sql = 'CREATE ROLE ${escapeIdentifier(name)} WITH ${options.join(' ')}';
    final pool = _getPool();
    await pool.execute(sql);

    if (description != null && description.isNotEmpty) {
      await pool.execute('COMMENT ON ROLE ${escapeIdentifier(name)} IS ${escapeLiteral(description)}');
    }
    
    // Fetch the full role object from DB to update cache
    final newRole = await fetchRoleByName(name, fromCache: false);
    if (newRole == null) throw Exception('Role created but not found in catalog');
    
    if (_cachedRoles != null) {
      _cachedRoles!.add(newRole);
      _cachedRoles!.sort(_compareRoles);
    }
    if (!canLogin) {
      _cachedGroupCatalog = null;
    }

    return newRole;
  }

  Future<PgRole> updateRole({
    required String oldName,
    required String name,
    String? description,
    String? password,
    DateTime? validUntil,
  }) async {
    final pool = _getPool();
    final trimmedName = name.trim();
    if (trimmedName != oldName) {
      await pool.execute(
        'ALTER ROLE ${escapeIdentifier(oldName)} RENAME TO ${escapeIdentifier(trimmedName)}',
      );
    }

    final List<String> options = [];
    if (password != null && password.isNotEmpty) {
      options.add('PASSWORD ${escapeLiteral(password)}');
    }
    if (validUntil != null) {
      options.add('VALID UNTIL ${escapeLiteral(PgRole.formatDate(validUntil))}');
    } else {
      options.add("VALID UNTIL 'infinity'");
    }

    await pool.execute(
      'ALTER ROLE ${escapeIdentifier(trimmedName)} WITH ${options.join(' ')}',
    );

    final trimmedDesc = description?.trim();
    if (trimmedDesc != null && trimmedDesc.isNotEmpty) {
      await pool.execute(
        'COMMENT ON ROLE ${escapeIdentifier(trimmedName)} IS ${escapeLiteral(trimmedDesc)}',
      );
    } else {
      await pool.execute(
        'COMMENT ON ROLE ${escapeIdentifier(trimmedName)} IS NULL',
      );
    }

    final updatedRole = await fetchRoleByName(trimmedName, fromCache: false);
    if (updatedRole == null) {
      throw Exception('Role updated but not found in catalog');
    }

    if (_cachedRoles != null) {
      final index = _cachedRoles!.indexWhere(
        (r) => r.oid == updatedRole.oid || r.name == oldName,
      );
      if (index != -1) {
        _cachedRoles![index] = updatedRole;
      } else {
        _cachedRoles!.add(updatedRole);
      }
      _cachedRoles!.sort(_compareRoles);
    }

    return updatedRole;
  }

  static int _compareRoles(PgRole a, PgRole b) {
    if (a.isValid != b.isValid) {
      return a.isValid ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}
