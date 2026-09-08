class PgRole {
  final int oid;
  final String name;
  final bool isSuperuser;
  final bool inherit;
  final bool createRole;
  final bool createDb;
  final bool canLogin;
  final bool replication;
  final bool bypassRls;
  final bool isCurrent;
  final String? description;
  final bool isAdmin;
  final bool canDrop;
  bool get canManage => isAdmin;

  PgRole({
    required this.oid,
    required this.name,
    this.isSuperuser = false,
    this.inherit = true,
    this.createRole = false,
    this.createDb = false,
    this.canLogin = true,
    this.replication = false,
    this.bypassRls = false,
    this.isCurrent = false,
    this.description,
    bool isAdmin = false,
    this.canDrop = false,
    bool? canManage,
  })  : isAdmin = canManage ?? isAdmin;

  factory PgRole.fromRow(List<dynamic> row) {
    final bool isAdmin;
    final bool canDrop;
    if (row.length > 12) {
      isAdmin = (row[11] as bool?) ?? false;
      canDrop = (row[12] as bool?) ?? false;
    } else {
      canDrop = (row[11] as bool?) ?? false;
      isAdmin = canDrop;
    }
    return PgRole(
      oid: row[0] as int,
      name: row[1] as String,
      isSuperuser: (row[2] as bool?) ?? false,
      inherit: (row[3] as bool?) ?? true,
      createRole: (row[4] as bool?) ?? false,
      createDb: (row[5] as bool?) ?? false,
      canLogin: (row[6] as bool?) ?? true,
      replication: (row[7] as bool?) ?? false,
      bypassRls: (row[8] as bool?) ?? false,
      isCurrent: (row[9] as bool?) ?? false,
      description: row[10] as String?,
      isAdmin: isAdmin,
      canDrop: canDrop,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PgRole && runtimeType == other.runtimeType && oid == other.oid;

  @override
  int get hashCode => oid.hashCode;
}
