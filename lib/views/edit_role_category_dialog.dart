import 'package:flutter/material.dart';

class EditRoleCategoryDialog extends StatefulWidget {
  final String roleName;
  final String? currentCategory;
  final List<String> existingCategories;

  const EditRoleCategoryDialog({
    super.key,
    required this.roleName,
    this.currentCategory,
    required this.existingCategories,
  });

  @override
  State<EditRoleCategoryDialog> createState() => _EditRoleCategoryDialogState();
}

class _EditRoleCategoryDialogState extends State<EditRoleCategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentCategory ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectSuggestion(String category) {
    setState(() {
      _controller.text = category;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentText = _controller.text.trim();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.label_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Category for "${widget.roleName}"',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set dbroles.category to group this role in the list.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Category',
                hintText: 'e.g. department, policy',
                border: const OutlineInputBorder(),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear input',
                        onPressed: () => setState(() => _controller.clear()),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
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
                children: widget.existingCategories.map((cat) {
                  final isSelected = currentText.toLowerCase() == cat.toLowerCase();
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) => _selectSuggestion(cat),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

