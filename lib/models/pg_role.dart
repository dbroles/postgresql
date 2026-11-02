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
  final DateTime? validUntil;
  final bool isValid;
  final bool isExpiringSoon;
  bool get canManage => isAdmin;

  /// Formats a [DateTime] as an ISO date string ('YYYY-MM-DD').
  static String formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Returns [validUntil] formatted as 'YYYY-MM-DD', or null if not set.
  String? get validUntilDateString =>
      validUntil != null ? formatDate(validUntil!) : null;

  static bool _defaultIsValid(DateTime? validUntil) {
    if (validUntil == null) return true;
    final now = DateTime.now();
    final target = DateTime(validUntil.year, validUntil.month, validUntil.day);
    return target.isAfter(now);
  }

  static bool _defaultIsExpiringSoon(DateTime? validUntil, bool isValid) {
    if (validUntil == null || !isValid) return false;
    final now = DateTime.now();
    final target = DateTime(validUntil.year, validUntil.month, validUntil.day);
    final threshold = now.add(const Duration(days: 7));
    return target.isAfter(now) && !target.isAfter(threshold);
  }

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
    DateTime? validUntil,
    bool? isValid,
    bool? isExpiringSoon,
  })  : isAdmin = canManage ?? isAdmin,
        validUntil = validUntil != null
            ? DateTime(validUntil.year, validUntil.month, validUntil.day)
            : null,
        isValid = isValid ?? _defaultIsValid(validUntil),
        isExpiringSoon = isExpiringSoon ??
            _defaultIsExpiringSoon(
              validUntil,
              isValid ?? _defaultIsValid(validUntil),
            );

  static DateTime? _parseValidUntil(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) {
      return DateTime(raw.year, raw.month, raw.day);
    }
    if (raw is String && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
    }
    return null;
  }

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
    final DateTime? validUntil =
        row.length > 13 ? _parseValidUntil(row[13]) : null;
    final bool? isValid =
        row.length > 14 ? (row[14] as bool?) : null;
    final bool? isExpiringSoon =
        row.length > 15 ? (row[15] as bool?) : null;
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
      validUntil: validUntil,
      isValid: isValid,
      isExpiringSoon: isExpiringSoon,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PgRole && runtimeType == other.runtimeType && oid == other.oid;

  @override
  int get hashCode => oid.hashCode;
}
