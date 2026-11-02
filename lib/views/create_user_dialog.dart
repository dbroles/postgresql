import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/pg_role.dart';
import '../services/database_service.dart';

class CreateUserDialog extends StatefulWidget {
  final DatabaseService dbService;
  final PgRole? initialUser;

  const CreateUserDialog({
    super.key,
    required this.dbService,
    this.initialUser,
  });

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  final _passController = TextEditingController();
  late final TextEditingController _validUntilController;

  DateTime? _validUntil;
  bool _obscurePassword = true;
  bool _isSaving = false;

  bool get _isEditMode => widget.initialUser != null;

  @override
  void initState() {
    super.initState();
    final initialUser = widget.initialUser;
    _nameController = TextEditingController(text: initialUser?.name ?? '');
    _descController = TextEditingController(text: initialUser?.description ?? '');
    _validUntil = initialUser?.validUntil;
    _validUntilController = TextEditingController(
      text: _validUntil != null ? PgRole.formatDate(_validUntil!) : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _passController.dispose();
    _validUntilController.dispose();
    super.dispose();
  }

  void _setValidUntil(DateTime? date) {
    setState(() {
      _validUntil = date != null ? DateTime(date.year, date.month, date.day) : null;
      _validUntilController.text =
          _validUntil != null ? PgRole.formatDate(_validUntil!) : '';
    });
  }

  static String generateStrongPassword({int length = 16}) {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#\$%^&*()-_=+';
    const all = '$upper$lower$digits$symbols';

    final rng = Random.secure();
    final chars = <String>[
      upper[rng.nextInt(upper.length)],
      lower[rng.nextInt(lower.length)],
      digits[rng.nextInt(digits.length)],
      symbols[rng.nextInt(symbols.length)],
      for (int i = 4; i < length; i++) all[rng.nextInt(all.length)],
    ];
    chars.shuffle(rng);
    return chars.join();
  }

  void _generatePassword() {
    if (_isSaving) return;
    final generated = generateStrongPassword();
    setState(() {
      _passController.text = generated;
      _obscurePassword = false;
    });
  }

  static String _formatDateTime(DateTime dt) {
    final date = PgRole.formatDate(dt);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$date $h:$m:$s';
  }

  String buildOnboardingCredentials({DateTime? now}) {
    final timestamp = _formatDateTime(now ?? DateTime.now());
    final host = widget.dbService.host;
    final port = widget.dbService.port;
    final database = widget.dbService.database;
    final username = _nameController.text.trim();
    final password = _passController.text;

    final encodedUser = Uri.encodeComponent(username);
    final encodedPass = Uri.encodeComponent(password);
    final authPart = password.isNotEmpty
        ? '$encodedUser:$encodedPass@'
        : (username.isNotEmpty ? '$encodedUser@' : '');
    final uri = 'postgresql://$authPart$host:$port/$database';

    final buffer = StringBuffer()
      ..writeln(timestamp)
      ..writeln('Host: $host')
      ..writeln('Port: $port')
      ..writeln('Username: $username')
      ..writeln('Password: $password');

    if (_validUntil != null) {
      buffer.writeln('Valid Until: ${PgRole.formatDate(_validUntil!)}');
    }

    buffer.write('URI: $uri');
    return buffer.toString();
  }

  Future<void> _copyOnboardingCredentials() async {
    final text = buildOnboardingCredentials();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Onboarding credentials copied to clipboard.')),
    );
  }

  Widget _buildQuickDateChips() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final presets = <({String label, DateTime date})>[
      (label: 'Expire Now', date: today),
      (label: '+30', date: DateTime(today.year, today.month, today.day + 30)),
      (label: '+90', date: DateTime(today.year, today.month, today.day + 90)),
      (label: '+365', date: DateTime(today.year, today.month, today.day + 365)),
    ];

    return Wrap(
      spacing: 8.0,
      runSpacing: 6.0,
      children: presets.map((preset) {
        final isSelected = _validUntil != null &&
            _validUntil!.year == preset.date.year &&
            _validUntil!.month == preset.date.month &&
            _validUntil!.day == preset.date.day;
        return ChoiceChip(
          label: Text(preset.label),
          selected: isSelected,
          onSelected: _isSaving ? null : (_) => _setValidUntil(preset.date),
        );
      }).toList(),
    );
  }

  Future<void> _pickValidUntilDate() async {
    if (_isSaving) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(1970, 1, 1);
    final lastDate = DateTime(2100, 12, 31);
    var initialDate = _validUntil ?? today;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;

    final platform = Theme.of(context).platform;
    final isCupertino =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    DateTime? picked;
    if (isCupertino) {
      picked = await _showCupertinoDatePicker(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      );
    } else {
      picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      );
    }

    if (picked != null && mounted) {
      _setValidUntil(picked);
    }
  }

  Future<DateTime?> _showCupertinoDatePicker({
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    DateTime tempPicked = initialDate;
    final theme = Theme.of(context);
    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (popupContext) {
        return Container(
          height: 300,
          color: CupertinoColors.systemBackground.resolveFrom(popupContext),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        onPressed: () => Navigator.of(popupContext).pop(null),
                        child: const Text('Cancel'),
                      ),
                      CupertinoButton(
                        onPressed: () =>
                            Navigator.of(popupContext).pop(tempPicked),
                        child: const Text(
                          'Done',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: initialDate,
                    minimumDate: firstDate,
                    maximumDate: lastDate,
                    onDateTimeChanged: (DateTime newDate) {
                      tempPicked = newDate;
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final PgRole savedRole;
      if (_isEditMode) {
        savedRole = await widget.dbService.updateRole(
          oldName: widget.initialUser!.name,
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          password: _passController.text,
          validUntil: _validUntil,
        );
      } else {
        savedRole = await widget.dbService.createRole(
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          password: _passController.text,
          validUntil: _validUntil,
          isSuper: false,
          inherit: true,
          createRole: false,
          createDb: false,
          canLogin: true,
          replication: false,
          bypassRls: false,
        );
      }
      if (mounted) Navigator.of(context).pop(savedRole);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to ${_isEditMode ? 'update' : 'create'} user: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(_isEditMode ? Icons.edit : Icons.person_add, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(_isEditMode ? 'Edit User' : 'New User'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isEditMode
                      ? 'Update user attributes and settings.'
                      : 'Create a new user with login attribute.',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Username is required' : null,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: _isEditMode ? 'Leave blank to keep current password' : null,
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.casino_outlined),
                          tooltip: 'Generate password',
                          onPressed: _generatePassword,
                        ),
                        IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _validUntilController,
                  readOnly: true,
                  onTap: _pickValidUntilDate,
                  decoration: InputDecoration(
                    labelText: 'Valid Until',
                    hintText: 'Never expires',
                    border: const OutlineInputBorder(),
                    suffixIcon: _validUntil != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear date',
                            onPressed: () => _setValidUntil(null),
                          )
                        : IconButton(
                            icon: const Icon(Icons.calendar_today),
                            tooltip: 'Select date',
                            onPressed: _pickValidUntilDate,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildQuickDateChips(),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _copyOnboardingCredentials,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy Onboarding Credentials'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
            : const Icon(Icons.check),
          label: Text(_isEditMode ? 'Save Changes' : 'Create User'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }
}
