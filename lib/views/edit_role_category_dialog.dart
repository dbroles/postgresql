import 'package:flutter/material.dart';
import '../models/pg_user_group.dart';

class EditRoleCategoryResult {
  final String category;
  final List<String> assignedRoleNames;

  const EditRoleCategoryResult({
    required this.category,
    required this.assignedRoleNames,
  });

  @override
  String toString() => category;
}

enum RoleCategoryFilterSegment { all, inCategory, ungrouped }

class EditRoleCategoryDialog extends StatefulWidget {
  final String? roleName;
  final String? title;
  final String? subtitle;
  final String? currentCategory;
  final int? defaultOrder;
  final List<String> existingCategories;
  final List<PgUserGroup>? availableRoles;
  final List<String>? initialSelectedRoleNames;

  const EditRoleCategoryDialog({
    super.key,
    this.roleName,
    this.title,
    this.subtitle,
    this.currentCategory,
    this.defaultOrder,
    this.existingCategories = const [],
    this.availableRoles,
    this.initialSelectedRoleNames,
  });

  @override
  State<EditRoleCategoryDialog> createState() => _EditRoleCategoryDialogState();
}

class _EditRoleCategoryDialogState extends State<EditRoleCategoryDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _colorController;
  late final TextEditingController _searchController;
  int? _existingOrder;
  late final Set<String> _selectedRoleNames;
  RoleCategoryFilterSegment _selectedSegment = RoleCategoryFilterSegment.all;
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
    final raw = widget.currentCategory ?? '';
    final parts = raw.split(':');
    final name = parts.isNotEmpty ? parts[0].trim() : '';
    _existingOrder = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
    final color = parts.length > 2 ? parts[2].trim().replaceAll('#', '') : '';

    _nameController = TextEditingController(text: name);
    _colorController = TextEditingController(text: color);
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

  Color? get _activeColor {
    final hex = _colorController.text.trim().replaceAll('#', '');
    if (hex.isEmpty) return null;
    final cleanHex = hex.length == 6 ? 'FF$hex' : hex;
    final val = int.tryParse(cleanHex, radix: 16);
    if (val != null) return Color(val);
    return null;
  }

  void _selectSuggestion(String rawCategory) {
    final parts = rawCategory.split(':');
    setState(() {
      _nameController.text = parts.isNotEmpty ? parts[0].trim() : '';
      _existingOrder = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
      _colorController.text = parts.length > 2 ? parts[2].trim().replaceAll('#', '') : '';
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

  List<PgUserGroup> _getFilteredRoles() {
    final grantable = _grantableRoles;
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
      final isUngrouped = role.category == null || role.category!.trim().isEmpty;

      switch (_selectedSegment) {
        case RoleCategoryFilterSegment.all:
          return true;
        case RoleCategoryFilterSegment.inCategory:
          return isSelected;
        case RoleCategoryFilterSegment.ungrouped:
          return isUngrouped;
      }
    }).toList();
  }

  Widget _buildPresetColorDots(ThemeData theme) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
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
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color(colorVal),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? theme.colorScheme.onSurface : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRoleListSection(ThemeData theme) {
    final grantable = _grantableRoles;
    final filtered = _getFilteredRoles();
    final allFilteredSelected = filtered.isNotEmpty &&
        filtered.every((r) => _selectedRoleNames.contains(r.name));

    final allCount = grantable.length;
    final inCatCount = _selectedRoleNames.where((name) => grantable.any((r) => r.name == name)).length;
    final ungroupedCount = grantable
        .where((r) => r.category == null || r.category!.trim().isEmpty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
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
        const SizedBox(height: 6),
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
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          ),
          onChanged: (val) {
            setState(() => _searchQuery = val);
          },
        ),
        const SizedBox(height: 8),
        // Filter Segments
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text('All ($allCount)'),
                selected: _selectedSegment == RoleCategoryFilterSegment.all,
                onSelected: (_) => setState(() => _selectedSegment = RoleCategoryFilterSegment.all),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text('In Category ($inCatCount)'),
                selected: _selectedSegment == RoleCategoryFilterSegment.inCategory,
                onSelected: (_) => setState(() => _selectedSegment = RoleCategoryFilterSegment.inCategory),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text('Ungrouped ($ungroupedCount)'),
                selected: _selectedSegment == RoleCategoryFilterSegment.ungrouped,
                onSelected: (_) => setState(() => _selectedSegment = RoleCategoryFilterSegment.ungrouped),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Virtualized ListView of filtered roles
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'No matching roles found',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final role = filtered[index];
                      final isSelected = _selectedRoleNames.contains(role.name);
                      final otherCat = role.categoryName ?? role.category;
                      final currentCatName = _nameController.text.trim();
                      final hasOtherCategory = otherCat != null &&
                          otherCat.isNotEmpty &&
                          (currentCatName.isEmpty || otherCat.toLowerCase() != currentCatName.toLowerCase());

                      return CheckboxListTile(
                        dense: true,
                        value: isSelected,
                        onChanged: (val) {
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
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'In "$otherCat"',
                                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                                ),
                              )
                            else if (role.category == null || role.category!.trim().isEmpty)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Ungrouped',
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
                    },
                  ),
          ),
        ),
      ],
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
    final dialogWidth = isNarrow ? mediaQuery.size.width * 0.95 : 540.0;
    final dialogHeight = isNarrow ? mediaQuery.size.height * 0.85 : mediaQuery.size.height * 0.78;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.category_outlined, color: previewColor),
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
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dialogSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Name and Color inputs (on separate rows)
                  TextField(
                    controller: _nameController,
                    autofocus: currentName.isEmpty,
                    decoration: InputDecoration(
                      labelText: 'Category Name',
                      hintText: 'e.g. department, country',
                      border: const OutlineInputBorder(),
                      isDense: true,
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
                  const SizedBox(height: 10),
                  TextField(
                    controller: _colorController,
                    decoration: InputDecoration(
                      labelText: 'Color Hex',
                      hintText: 'e.g. 88AA00',
                      prefixText: '#',
                      border: const OutlineInputBorder(),
                      isDense: true,
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
                  const SizedBox(height: 10),
                  _buildPresetColorDots(theme),
                  Expanded(
                    child: _buildRoleListSection(theme),
                  ),
                ],
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
                      autofocus: true,
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
                    _buildPresetColorDots(theme),
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
                          final parts = rawCat.split(':');
                          final name = parts.isNotEmpty ? parts[0].trim() : rawCat;
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
