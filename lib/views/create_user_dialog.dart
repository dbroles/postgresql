import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/pg_role.dart';
import '../models/pg_user_group.dart';
import '../services/database_service.dart';

class CreateUserDialog extends StatefulWidget {
  final DatabaseService dbService;
  final PgRole? initialUser;
  final bool isDuplicate;
  final List<PgUserGroup>? rolesToCopy;

  const CreateUserDialog({
    super.key,
    required this.dbService,
    this.initialUser,
    this.isDuplicate = false,
    this.rolesToCopy,
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
  bool _isSaving = false;
  Set<String> _selectedRolesToCopy = {};

  bool get _isDuplicateMode => widget.isDuplicate;
  bool get _isEditMode => widget.initialUser != null && !_isDuplicateMode;

  @override
  void initState() {
    super.initState();
    final initialUser = widget.initialUser;
    final defaultName = _isDuplicateMode && initialUser != null
        ? '${initialUser.name}_copy'
        : (initialUser?.name ?? '');
    _nameController = TextEditingController(text: defaultName);
    _descController = TextEditingController(text: initialUser?.description ?? '');
    _validUntil = initialUser?.validUntil;
    _validUntilController = TextEditingController(
      text: _validUntil != null ? PgRole.formatDate(_validUntil!) : '',
    );

    if (_isDuplicateMode && widget.rolesToCopy != null) {
      _selectedRolesToCopy = widget.rolesToCopy!
          .where((g) => g.granted && g.grantable)
          .map((g) => g.name)
          .toSet();
    }
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets.map((preset) {
          final isSelected = _validUntil != null &&
              _validUntil!.year == preset.date.year &&
              _validUntil!.month == preset.date.month &&
              _validUntil!.day == preset.date.day;
          return Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: ChoiceChip(
              label: Text(preset.label, style: const TextStyle(fontSize: 12)),
              selected: isSelected,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              onSelected: _isSaving ? null : (_) => _setValidUntil(preset.date),
            ),
          );
        }).toList(),
      ),
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
      } else if (_isDuplicateMode && widget.initialUser != null) {
        final initial = widget.initialUser!;
        final currentUser = await widget.dbService.fetchCurrentUserRole();
        final canCreateRole = currentUser?.isSuperuser == true || currentUser?.createRole == true;
        final canCreateDb = currentUser?.isSuperuser == true || currentUser?.createDb == true;
        final canReplicate = currentUser?.isSuperuser == true || currentUser?.replication == true;
        final canBypassRls = currentUser?.isSuperuser == true || currentUser?.bypassRls == true;

        savedRole = await widget.dbService.createRole(
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          password: _passController.text,
          validUntil: _validUntil,
          isSuper: false,
          inherit: initial.inherit,
          createRole: initial.createRole && canCreateRole,
          createDb: initial.createDb && canCreateDb,
          canLogin: true,
          replication: initial.replication && canReplicate,
          bypassRls: initial.bypassRls && canBypassRls,
        );

        for (final roleName in _selectedRolesToCopy) {
          try {
            await widget.dbService.grantRole(savedRole.name, roleName, userOid: savedRole.oid);
          } catch (_) {
            // Ignore individual role grant failures to allow remaining grants to succeed
          }
        }
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
        final action = _isDuplicateMode ? 'duplicate' : (_isEditMode ? 'update' : 'create');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to $action user: $e')),
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
          Icon(
            _isDuplicateMode
                ? Icons.copy_rounded
                : (_isEditMode ? Icons.edit : Icons.person_add),
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isDuplicateMode
                  ? 'Duplicate User'
                  : (_isEditMode ? 'Edit User' : 'New User'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
                  _isDuplicateMode
                      ? 'Duplicate user attributes and assigned roles from "${widget.initialUser?.name}".'
                      : (_isEditMode
                          ? 'Update user attributes and settings.'
                          : 'Create a new user with login attribute.'),
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
                  obscureText: false,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: _isEditMode
                        ? 'Leave blank to keep current password'
                        : (_isDuplicateMode ? 'Set password for new user' : null),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.casino_outlined),
                      tooltip: 'Generate password',
                      onPressed: _generatePassword,
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
                if (_isDuplicateMode && widget.rolesToCopy != null && widget.rolesToCopy!.any((g) => g.granted)) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Copy Assigned Roles',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 6.0,
                    children: widget.rolesToCopy!.where((g) => g.granted).map((role) {
                      final canGrant = role.grantable;
                      return FilterChip(
                        label: Text(role.name),
                        selected: _selectedRolesToCopy.contains(role.name),
                        onSelected: canGrant && !_isSaving
                            ? (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedRolesToCopy.add(role.name);
                                  } else {
                                    _selectedRolesToCopy.remove(role.name);
                                  }
                                });
                              }
                            : null,
                        tooltip: canGrant ? null : 'Cannot grant: missing admin option on this role',
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _isSaving ? null : _copyOnboardingCredentials,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.copy, size: 18),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Copy Onboarding Credentials',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
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
          label: Text(
            _isDuplicateMode
                ? 'Duplicate User'
                : (_isEditMode ? 'Save Changes' : 'Create User'),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }
}
