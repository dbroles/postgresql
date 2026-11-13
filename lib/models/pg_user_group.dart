import 'dart:ui';

typedef ParsedCategory = ({
  String? name,
  int? order,
  String? colorHex,
  Color? color,
});

class PgUserGroup({
  required final int oid,
  required final String name,
  final String? description,
  required final List<String> grantors,
  required final bool grantable,
  required var bool granted,
  final String? category,
  final String ungroupedTemplate = defaultUngroupedTemplate,
}) {
  static const String defaultUngroupedName = 'Ungrouped';
  static const String defaultUngroupedColorHex = '88AA00';
  static const Color defaultUngroupedColor = Color(0xFF88AA00);
  static const String defaultUngroupedTemplate =
      '$defaultUngroupedName::$defaultUngroupedColorHex';

  final ParsedCategory _parsedCategory = parseCategory(category);
  final ParsedCategory _parsedUngrouped = parseCategory(ungroupedTemplate);

  /// Whether this role has no custom category assigned and belongs to the default Ungrouped group.
  bool get isDefaultUngrouped => _parsedCategory.name == null;

  /// Pre-parsed human-readable category name from format "name[:order[:color]]"
  String? get categoryName => _parsedCategory.name;

  /// Pre-parsed numeric sort order if present
  int? get categoryOrder => _parsedCategory.order;

  /// Pre-parsed 6-character hex color string (without '#') if present
  String? get categoryColorHex => _parsedCategory.colorHex;

  /// Pre-parsed [Color] from [categoryColorHex], or null if invalid/not provided
  Color? get categoryColor => _parsedCategory.color;

  /// Effective category display name (falls back to [ungroupedTemplate] when [isDefaultUngrouped]).
  String get effectiveCategoryName =>
      _parsedCategory.name ?? _parsedUngrouped.name ?? defaultUngroupedName;

  /// Effective numeric sort order (falls back to [ungroupedTemplate] order when [isDefaultUngrouped]).
  int? get effectiveCategoryOrder =>
      isDefaultUngrouped ? _parsedUngrouped.order : _parsedCategory.order;

  /// Effective 6-character hex color (falls back to [ungroupedTemplate] / `#88AA00` when [isDefaultUngrouped]).
  String? get effectiveCategoryColorHex => isDefaultUngrouped
      ? (_parsedUngrouped.colorHex ?? defaultUngroupedColorHex)
      : _parsedCategory.colorHex;

  /// Effective [Color] (falls back to [ungroupedTemplate] / `Color(0xFF88AA00)` when [isDefaultUngrouped]).
  Color? get effectiveCategoryColor => isDefaultUngrouped
      ? (_parsedUngrouped.color ?? defaultUngroupedColor)
      : _parsedCategory.color;

  /// Parses a category string of format `"name[:order[:color]]"` in a single pass
  /// using Dart 3 list pattern matching.
  static ParsedCategory parseCategory(String? category) {
    if (category == null || category.isEmpty) {
      return (name: null, order: null, colorHex: null, color: null);
    }
    final (rawName, rawOrder, rawColor) = switch (category.split(':')) {
      [final n, final o, final c, ...final rest] => (
        n,
        o,
        rest.isEmpty ? c : [c, ...rest].join(':'),
      ),
      [final n, final o] => (n, o, null),
      [final n] => (n, null, null),
      [] => ('', null, null),
    };
    final trimmedName = rawName.trim();
    final name = trimmedName.isNotEmpty ? trimmedName : null;
    final order = rawOrder != null ? int.tryParse(rawOrder.trim()) : null;
    var hex = rawColor?.trim() ?? '';
    if (hex.startsWith('#')) hex = hex.substring(1);
    final colorHex = hex.isNotEmpty ? hex : null;
    return (
      name: name,
      order: order,
      colorHex: colorHex,
      color: parseCategoryColor(colorHex),
    );
  }

  /// Canonical lower-cased category name key for deduplication and matching.
  static String? categoryKey(String? category) =>
      parseCategory(category).name?.toLowerCase();

  static Color? parseCategoryColor(String? hex) {
    if (hex == null) return null;
    var trimmed = hex.trim();
    if (trimmed.startsWith('#')) trimmed = trimmed.substring(1);
    if (trimmed.isEmpty) return null;
    final cleanHex = trimmed.length == 6 ? 'FF$trimmed' : trimmed;
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

  factory fromRow(List<dynamic> row) {
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
    String? ungroupedTemplate,
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
      ungroupedTemplate: ungroupedTemplate ?? this.ungroupedTemplate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PgUserGroup && runtimeType == other.runtimeType && oid == other.oid;

  @override
  int get hashCode => oid.hashCode;
}
