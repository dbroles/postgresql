import 'dart:ui';

class PgUserGroup {
  final int oid;
  final String name;
  final String? description;
  final List<String> grantors;
  final bool grantable;
  bool granted;
  final String? category;

  /// Pre-parsed human-readable category name from format "name[:order[:color]]"
  final String? categoryName;

  /// Pre-parsed numeric sort order if present
  final int? categoryOrder;

  /// Pre-parsed 6-character hex color string (without '#') if present
  final String? categoryColorHex;

  /// Pre-parsed [Color] from [categoryColorHex], or null if invalid/not provided
  final Color? categoryColor;

  PgUserGroup({
    required this.oid,
    required this.name,
    this.description,
    required this.grantors,
    required this.grantable,
    required this.granted,
    this.category,
  })  : categoryName = _parseCategoryName(category),
        categoryOrder = _parseCategoryOrder(category),
        categoryColorHex = _parseCategoryColorHex(category),
        categoryColor = _parseCategoryColor(_parseCategoryColorHex(category));

  static String? _parseCategoryName(String? category) {
    if (category == null || category.isEmpty) return null;
    final colonIdx = category.indexOf(':');
    final rawName = colonIdx == -1 ? category : category.substring(0, colonIdx);
    final trimmed = rawName.trim();
    return trimmed.isNotEmpty ? trimmed : null;
  }

  static int? _parseCategoryOrder(String? category) {
    if (category == null || category.isEmpty) return null;
    final firstColon = category.indexOf(':');
    if (firstColon == -1) return null;
    final secondColon = category.indexOf(':', firstColon + 1);
    final rawOrder = secondColon == -1
        ? category.substring(firstColon + 1)
        : category.substring(firstColon + 1, secondColon);
    return int.tryParse(rawOrder.trim());
  }

  static String? _parseCategoryColorHex(String? category) {
    if (category == null || category.isEmpty) return null;
    final firstColon = category.indexOf(':');
    if (firstColon == -1) return null;
    final secondColon = category.indexOf(':', firstColon + 1);
    if (secondColon == -1) return null;
    var hex = category.substring(secondColon + 1).trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    return hex.isNotEmpty ? hex : null;
  }

  static Color? _parseCategoryColor(String? hex) {
    if (hex == null) return null;
    final cleanHex = hex.length == 6 ? 'FF$hex' : hex;
    final val = int.tryParse(cleanHex, radix: 16);
    return val != null ? Color(val) : null;
  }

  /// Parses PostgreSQL grantor array values (either a Dart [List] or PG array literal `"{a,b}"`).
  static List<String> parseGrantors(dynamic rawGrantors) {
    if (rawGrantors is List) {
      return rawGrantors
          .where((e) => e != null)
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (rawGrantors is String) {
      var str = rawGrantors.trim();
      if (str.startsWith('{') && str.endsWith('}')) {
        str = str.substring(1, str.length - 1).trim();
        if (str.isNotEmpty) {
          return str
              .split(',')
              .map((s) => s.replaceAll('"', '').trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
    }
    return [];
  }

  /// Formats category components into "name[:order[:color]]" string
  static String formatCategory({
    required String name,
    int? order,
    String? colorHex,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return '';
    final trimmedColor = colorHex?.trim().replaceAll('#', '') ?? '';
    if (order != null || trimmedColor.isNotEmpty) {
      final orderPart = order != null ? order.toString() : '';
      if (trimmedColor.isNotEmpty) {
        return '$trimmedName:$orderPart:$trimmedColor';
      }
      return '$trimmedName:$orderPart';
    }
    return trimmedName;
  }

  factory PgUserGroup.fromRow(List<dynamic> row) {
    final parsedGrantors = parseGrantors(row[3]);

    final rawCategory = row.length > 6 ? (row[6] as String?)?.trim() : null;
    final category = (rawCategory != null && rawCategory.isNotEmpty) ? rawCategory : null;

    return PgUserGroup(
      oid: row[0] as int,
      name: row[1] as String,
      description: row[2] as String?,
      grantors: parsedGrantors,
      grantable: (row[4] as bool?) ?? false,
      granted: (row[5] as bool?) ?? false,
      category: category,
    );
  }

  PgUserGroup copyWith({
    int? oid,
    String? name,
    String? description,
    List<String>? grantors,
    bool? grantable,
    bool? granted,
    String? category,
    bool clearCategory = false,
  }) {
    return PgUserGroup(
      oid: oid ?? this.oid,
      name: name ?? this.name,
      description: description ?? this.description,
      grantors: grantors ?? List.from(this.grantors),
      grantable: grantable ?? this.grantable,
      granted: granted ?? this.granted,
      category: clearCategory ? null : (category ?? this.category),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PgUserGroup && runtimeType == other.runtimeType && oid == other.oid;

  @override
  int get hashCode => oid.hashCode;
}
