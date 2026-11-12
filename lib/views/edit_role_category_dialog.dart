import 'package:material_ui/material_ui.dart';
import '../models/pg_user_group.dart';

class const EditRoleCategoryResult({
  required final String category,
  required final List<String> assignedRoleNames,
}) {
  @override
  String toString() => category;
}

enum RoleCategoryFilterSegment { all, inCategory, ungrouped }

class const EditRoleCategoryDialog({
  super.key,
  final String? roleName,
  final String? title,
  final String? subtitle,
  final String? currentCategory,
  final int? defaultOrder,
  final List<String> existingCategories = const [],
  final List<PgUserGroup>? availableRoles,
  final List<String>? initialSelectedRoleNames,
  final bool isDefaultUngrouped = false,
}) extends StatefulWidget {
  @override
  State<EditRoleCategoryDialog> createState() => _EditRoleCategoryDialogState();
}

class _EditRoleCategoryDialogState extends State<EditRoleCategoryDialog> {
  final GlobalKey _headerSectionKey = GlobalKey();
  late final TextEditingController _nameController;
  late final TextEditingController _colorController;
  late final TextEditingController _searchController;
  int? _existingOrder;
  late final Set<String> _selectedRoleNames;
  RoleCategoryFilterSegment _selectedSegment = .all;
  String _searchQuery = '';

  static const List<({String label, String hex})> _presetColors = [
    (label: 'Olive', hex: '88AA00'),
    (label: 'Green', hex: '34BB22'),
    (label: 'Teal', hex: '00897B'),
    (label: 'Cyan', hex: '00ACC1'),
    (label: 'Blue', hex: '1E88E5'),
    (label: 'Indigo', hex: '3F51B5'),
    (label: 'Purple', hex: '5E35B1'),
    (label: 'Pink', hex: 'D81B60'),
    (label: 'Red', hex: 'E53935'),
    (label: 'Orange', hex: 'FB8C00'),
    (label: 'Amber', hex: 'FDD835'),
    (label: 'Slate', hex: '546E7A'),
  ];

  @override
  void initState() {
    super.initState();
    final parsed = PgUserGroup.parseCategory(widget.currentCategory);
    _existingOrder = parsed.order;

    _nameController = TextEditingController(text: parsed.name ?? '');
    _colorController = TextEditingController(text: parsed.colorHex ?? '');
    _searchController = TextEditingController();
    _selectedRoleNames = Set<String>.from(widget.initialSelectedRoleNames ?? const []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _colorController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Color? get _activeColor => PgUserGroup.parseCategoryColor(_colorController.text);

  void _selectSuggestion(String rawCategory) {
    final parsed = PgUserGroup.parseCategory(rawCategory);
    setState(() {
      _nameController.text = parsed.name ?? '';
      _existingOrder = parsed.order;
      _colorController.text = parsed.colorHex ?? '';
    });
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (widget.availableRoles == null) {
        Navigator.of(context).pop('');
      } else {
        Navigator.of(context).pop(null);
      }
      return;
    }
    final colorHex = _colorController.text.trim().replaceAll('#', '');
    final order = _existingOrder ?? widget.defaultOrder;
    final formatted = PgUserGroup.formatCategory(
      name: name,
      order: order,
      colorHex: colorHex.isNotEmpty ? colorHex : null,
    );

    if (widget.availableRoles == null) {
      // Legacy backwards-compatible return for test that expects String
      Navigator.of(context).pop(formatted);
    } else {
      Navigator.of(context).pop(
        EditRoleCategoryResult(
          category: formatted,
          assignedRoleNames: _selectedRoleNames.toList(),
        ),
      );
    }
  }

  List<PgUserGroup> get _grantableRoles {
    if (widget.availableRoles == null) return [];
    return widget.availableRoles!.where((r) => r.grantable).toList();
  }

  List<PgUserGroup> _getFilteredRoles(List<PgUserGroup> grantable) {
    if (grantable.isEmpty) return [];
    final query = _searchQuery.trim().toLowerCase();

    return grantable.where((role) {
      // Search in role name and description
      if (query.isNotEmpty) {
        final matchesName = role.name.toLowerCase().contains(query);
        final matchesDescription = role.description != null &&
            role.description!.toLowerCase().contains(query);
        if (!matchesName && !matchesDescription) {
          return false;
        }
      }

      final isSelected = _selectedRoleNames.contains(role.name);
      final isUngrouped = role.isDefaultUngrouped;

      return switch (_selectedSegment) {
        .all => true,
        .inCategory => isSelected,
        .ungrouped => isUngrouped,
      };
    }).toList();
  }

  Widget _buildPresetColorDots(ThemeData theme, {bool isCompactHeight = false}) {
    final dotSize = isCompactHeight ? 24.0 : 28.0;
    final spacing = isCompactHeight ? 6.0 : 8.0;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: _presetColors.map((preset) {
        final colorVal = int.parse('FF${preset.hex}', radix: 16);
        final isSelected = _colorController.text.trim().toLowerCase() == preset.hex.toLowerCase();
        return InkWell(
          onTap: () {
            setState(() {
              _colorController.text = preset.hex;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: Color(colorVal),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? theme.colorScheme.onSurface : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: isSelected
                ? Icon(Icons.check, size: isCompactHeight ? 14 : 16, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRoleTile(ThemeData theme, PgUserGroup role) {
    final isLockedInUngrouped = widget.isDefaultUngrouped && role.isDefaultUngrouped;
    final isSelected = isLockedInUngrouped || _selectedRoleNames.contains(role.name);
    final otherCat = role.categoryName ?? role.category;
    final currentCatName = _nameController.text.trim();
    final hasOtherCategory = !role.isDefaultUngrouped &&
        otherCat != null &&
        otherCat.isNotEmpty &&
        (widget.isDefaultUngrouped ||
            currentCatName.isEmpty ||
            otherCat.toLowerCase() != currentCatName.toLowerCase());

    return CheckboxListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      enabled: !isLockedInUngrouped,
      value: isSelected,
      onChanged: isLockedInUngrouped
          ? null
          : (val) {
              setState(() {
                if (val == true) {
                  _selectedRoleNames.add(role.name);
                } else {
                  _selectedRoleNames.remove(role.name);
                }
              });
            },
      title: Row(
        children: [
          Expanded(
            child: Text(
              role.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasOtherCategory)
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'In "$otherCat"',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                  ),
                ),
              ),
            )
          else if (role.isDefaultUngrouped)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                role.effectiveCategoryName,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      subtitle: role.description != null && role.description!.isNotEmpty
          ? Text(
              role.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            )
          : null,
    );
  }

  Widget _buildHeaderSection(
    ThemeData theme, {
    required String dialogSubtitle,
    required String currentName,
    required int allCount,
    required int inCatCount,
    required int ungroupedCount,
    required bool allFilteredSelected,
    required List<PgUserGroup> filtered,
    required bool isCompactHeight,
  }) {
    return Column(
      key: _headerSectionKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dialogSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: isCompactHeight ? 4 : 12),
        // Name and Color inputs (on separate rows)
        TextField(
          controller: _nameController,
          autofocus: currentName.isEmpty && !isCompactHeight,
          decoration: InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g. department, country',
            border: const OutlineInputBorder(),
            isDense: true,
            visualDensity: isCompactHeight ? VisualDensity.compact : null,
            contentPadding: isCompactHeight
                ? const EdgeInsets.symmetric(vertical: 6, horizontal: 10)
                : null,
            suffixIcon: _nameController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear name',
                    onPressed: () => setState(() => _nameController.clear()),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(height: isCompactHeight ? 6 : 10),
        TextField(
          controller: _colorController,
          decoration: InputDecoration(
            labelText: 'Color Hex',
            hintText: 'e.g. 88AA00',
            prefixText: '#',
            border: const OutlineInputBorder(),
            isDense: true,
            visualDensity: isCompactHeight ? VisualDensity.compact : null,
            contentPadding: isCompactHeight
                ? const EdgeInsets.symmetric(vertical: 6, horizontal: 10)
                : null,
            suffixIcon: _colorController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear color',
                    onPressed: () => setState(() => _colorController.clear()),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(height: isCompactHeight ? 4 : 10),
        _buildPresetColorDots(theme, isCompactHeight: isCompactHeight),
        Divider(height: isCompactHeight ? 8 : 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Assign Roles ($inCatCount selected):',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              style: isCompactHeight
                  ? TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                    )
                  : null,
              onPressed: filtered.isEmpty
                  ? null
                  : () {
                      setState(() {
                        if (allFilteredSelected) {
                          _selectedRoleNames.removeAll(filtered.map((r) => r.name));
                        } else {
                          _selectedRoleNames.addAll(filtered.map((r) => r.name));
                        }
                      });
                    },
              child: Text(
                allFilteredSelected ? 'Deselect All' : 'Select All',
              ),
            ),
          ],
        ),
        SizedBox(height: isCompactHeight ? 2 : 6),
        // Search TextField (searches name & description)
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search roles or descriptions...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: const OutlineInputBorder(),
            isDense: true,
            visualDensity: isCompactHeight ? VisualDensity.compact : null,
            contentPadding: EdgeInsets.symmetric(
              vertical: isCompactHeight ? 4 : 8,
              horizontal: 10,
            ),
          ),
          onChanged: (val) {
            setState(() => _searchQuery = val);
          },
        ),
        SizedBox(height: isCompactHeight ? 4 : 8),
        // Filter Segments
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: isCompactHeight ? MaterialTapTargetSize.shrinkWrap : null,
                label: Text('All ($allCount)'),
                selected: _selectedSegment == RoleCategoryFilterSegment.all,
                onSelected: (_) => setState(() => _selectedSegment = RoleCategoryFilterSegment.all),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: isCompactHeight ? MaterialTapTargetSize.shrinkWrap : null,
                label: Text('In Category ($inCatCount)'),
                selected: _selectedSegment == RoleCategoryFilterSegment.inCategory,
                onSelected: (_) => setState(() => _selectedSegment = RoleCategoryFilterSegment.inCategory),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: isCompactHeight ? MaterialTapTargetSize.shrinkWrap : null,
                label: Text('Ungrouped ($ungroupedCount)'),
                selected: _selectedSegment == RoleCategoryFilterSegment.ungrouped,
                onSelected: (_) => setState(() => _selectedSegment = RoleCategoryFilterSegment.ungrouped),
              ),
            ],
          ),
        ),
        SizedBox(height: isCompactHeight ? 4 : 8),
      ],
    );
  }

  Widget _buildRoleAssignmentContent(
    ThemeData theme, {
    required String dialogSubtitle,
    required String currentName,
    required bool isCompactHeight,
    required double textScale,
  }) {
    final grantable = _grantableRoles;
    final filtered = _getFilteredRoles(grantable);
    final toggleableFiltered = widget.isDefaultUngrouped
        ? filtered.where((r) => !r.isDefaultUngrouped).toList()
        : filtered;
    final allFilteredSelected = toggleableFiltered.isNotEmpty &&
        toggleableFiltered.every((r) => _selectedRoleNames.contains(r.name));

    final allCount = grantable.length;
    var inCatCount = 0;
    var ungroupedCount = 0;
    for (final r in grantable) {
      if (_selectedRoleNames.contains(r.name) ||
          (widget.isDefaultUngrouped && r.isDefaultUngrouped)) {
        inCatCount++;
      }
      if (r.isDefaultUngrouped) {
        ungroupedCount++;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final headerSection = _buildHeaderSection(
          theme,
          dialogSubtitle: dialogSubtitle,
          currentName: currentName,
          allCount: allCount,
          inCatCount: inCatCount,
          ungroupedCount: ungroupedCount,
          allFilteredSelected: allFilteredSelected,
          filtered: toggleableFiltered,
          isCompactHeight: isCompactHeight,
        );

        final borderDecoration = BoxDecoration(
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        );

        final minPinnedHeight = (isCompactHeight ? 450.0 : 520.0) * textScale;
        final useScrollableLayout = constraints.maxHeight < minPinnedHeight;

        if (useScrollableLayout) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: headerSection),
              if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    decoration: borderDecoration,
                    padding: const EdgeInsets.all(16.0),
                    alignment: Alignment.center,
                    child: Text(
                      'No matching roles found',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                DecoratedSliver(
                  decoration: borderDecoration,
                  sliver: SliverList.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _buildRoleTile(theme, filtered[index]),
                  ),
                ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headerSection,
            Expanded(
              child: Container(
                decoration: borderDecoration,
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'No matching roles found',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => _buildRoleTile(theme, filtered[index]),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = _activeColor;
    final previewColor = activeColor ?? theme.colorScheme.primary;
    final currentName = _nameController.text.trim();
    final hasRoles = widget.availableRoles != null && widget.availableRoles!.isNotEmpty;

    final dialogTitle = widget.title ??
        (widget.roleName != null
            ? 'Category for "${widget.roleName}"'
            : (widget.currentCategory != null ? 'Edit Role Category' : 'New Role Category'));
    final dialogSubtitle = widget.subtitle ??
        (hasRoles
            ? 'Configure category details and assign member roles.'
            : 'Configure category name, numeric order, and color.');

    final mediaQuery = MediaQuery.of(context);
    final isNarrow = mediaQuery.size.width < 600;
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom - mediaQuery.padding.vertical;
    final isCompactHeight = mediaQuery.size.height < 700 || availableHeight < 650;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    final dialogWidth = isNarrow ? mediaQuery.size.width * 0.95 : 540.0;
    final dialogHeight = isCompactHeight
        ? mediaQuery.size.height * 0.92
        : (isNarrow ? mediaQuery.size.height * 0.85 : mediaQuery.size.height * 0.78);

    return AlertDialog(
      insetPadding: isCompactHeight
          ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0)
          : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      titlePadding: isCompactHeight
          ? const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 0.0)
          : null,
      contentPadding: isCompactHeight
          ? const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0)
          : null,
      actionsPadding: isCompactHeight
          ? const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 8.0)
          : null,
      title: Row(
        children: [
          Icon(Icons.category_outlined, color: previewColor, size: isCompactHeight ? 20 : 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              dialogTitle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: hasRoles ? dialogHeight : null,
        child: hasRoles
            ? _buildRoleAssignmentContent(
                theme,
                dialogSubtitle: dialogSubtitle,
                currentName: currentName,
                isCompactHeight: isCompactHeight,
                textScale: textScale,
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dialogSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      autofocus: !isCompactHeight,
                      decoration: InputDecoration(
                        labelText: 'Category Name',
                        hintText: 'e.g. department, country',
                        border: const OutlineInputBorder(),
                        suffixIcon: _nameController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear name',
                                onPressed: () => setState(() => _nameController.clear()),
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _colorController,
                      decoration: InputDecoration(
                        labelText: 'Color Hex',
                        hintText: 'e.g. 88AA00',
                        prefixText: '#',
                        border: const OutlineInputBorder(),
                        suffixIcon: _colorController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear color',
                                onPressed: () => setState(() => _colorController.clear()),
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Color presets:',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPresetColorDots(theme, isCompactHeight: isCompactHeight),
                    if (widget.existingCategories.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Existing categories:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 6.0,
                        children: widget.existingCategories.map((rawCat) {
                          final name = PgUserGroup.parseCategory(rawCat).name ?? rawCat;
                          final isSelected = currentName.toLowerCase() == name.toLowerCase();
                          return ChoiceChip(
                            label: Text(name),
                            selected: isSelected,
                            onSelected: (_) => _selectSuggestion(rawCat),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: currentName.isNotEmpty ? _submit : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
