class PgMembership {
  final int roleOid;
  final int memberOid;
  final String grantor;
  final bool adminOption;
  final bool inheritOption;
  final bool setOption;

  PgMembership({
    required this.roleOid,
    required this.memberOid,
    required this.grantor,
    required this.adminOption,
    required this.inheritOption,
    required this.setOption,
  });

  factory PgMembership.fromRow(List<dynamic> row) {
    return PgMembership(
      roleOid: row[0] as int,
      memberOid: row[1] as int,
      grantor: row[2] as String,
      adminOption: row[3] as bool,
      inheritOption: row[4] as bool,
      setOption: row[5] as bool,
    );
  }
}
