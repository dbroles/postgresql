import 'dart:ui';

class PgUserGroup {
  final int oid;
  final String name;
  final String? description;
  final List<String> grantors;
  final bool grantable;
  bool granted;
  final String? category;

  PgUserGroup({
    required this.oid,
    required this.name,
    this.description,
    required this.grantors,
    required this.grantable,
    required this.granted,
    this.category,
  });

  /// Extracts the human-readable category name from format "name[:order[:color]]"
  String? get categoryName {
    if (category == null || category!.isEmpty) return null;
    final parts = category!.split(':');
    final name = parts[0].trim();
    return name.isNotEmpty ? name : null;
  }

  /// Extracts the numeric sort order if present
  int? get categoryOrder {
    if (category == null || category!.isEmpty) return null;
    final parts = category!.split(':');
    if (parts.length > 1) {
      return int.tryParse(parts[1].trim());
    }
    return null;
  }

  /// Extracts the 6-character hex color string (without '#') if present
  String? get categoryColorHex {
    if (category == null || category!.isEmpty) return null;
    final parts = category!.split(':');
    if (parts.length > 2) {
      var hex = parts[2].trim();
      if (hex.startsWith('#')) hex = hex.substring(1);
      return hex.isNotEmpty ? hex : null;
    }
    return null;
  }

  /// Parses the color hex into a [Color], or null if invalid/not provided
  Color? get categoryColor {
    final hex = categoryColorHex;
    if (hex == null) return null;
    final cleanHex = hex.length == 6 ? 'FF$hex' : hex;
    final val = int.tryParse(cleanHex, radix: 16);
    if (val != null) {
      return Color(val);
    }
    return null;
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
