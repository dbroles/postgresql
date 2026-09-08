class PgUserGroup {
  final int oid;
  final String name;
  final String? description;
  final List<String> grantors;
  final bool grantable;
  bool granted;

  PgUserGroup({
    required this.oid,
    required this.name,
    this.description,
    required this.grantors,
    required this.grantable,
    required this.granted,
  });

  factory PgUserGroup.fromRow(List<dynamic> row) {
    final rawGrantors = row[3];
    List<String> parsedGrantors = [];
    if (rawGrantors is List) {
      parsedGrantors = rawGrantors
          .where((e) => e != null)
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (rawGrantors is String) {
      // PostgreSQL literal array format: "{postgres,daniel}" or "{}"
      var str = rawGrantors.trim();
      if (str.startsWith('{') && str.endsWith('}')) {
        str = str.substring(1, str.length - 1).trim();
        if (str.isNotEmpty) {
          parsedGrantors = str
              .split(',')
              .map((s) => s.replaceAll('"', '').trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
    }

    return PgUserGroup(
      oid: row[0] as int,
      name: row[1] as String,
      description: row[2] as String?,
      grantors: parsedGrantors,
      grantable: (row[4] as bool?) ?? false,
      granted: (row[5] as bool?) ?? false,
    );
  }

  PgUserGroup copyWith({
    int? oid,
    String? name,
    String? description,
    List<String>? grantors,
    bool? grantable,
    bool? granted,
  }) {
    return PgUserGroup(
      oid: oid ?? this.oid,
      name: name ?? this.name,
      description: description ?? this.description,
      grantors: grantors ?? List.from(this.grantors),
      grantable: grantable ?? this.grantable,
      granted: granted ?? this.granted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PgUserGroup && runtimeType == other.runtimeType && oid == other.oid;

  @override
  int get hashCode => oid.hashCode;
}
