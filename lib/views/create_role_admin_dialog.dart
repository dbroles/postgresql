import 'package:flutter/material.dart';
import '../services/database_service.dart';

class CreateRoleAdminDialog extends StatefulWidget {
  final DatabaseService dbService;

  const CreateRoleAdminDialog({super.key, required this.dbService});

  @override
  State<CreateRoleAdminDialog> createState() => _CreateRoleAdminDialogState();
}

class _CreateRoleAdminDialogState extends State<CreateRoleAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'dbroles');
  final _passController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    try {
      final roleName = _nameController.text.trim();
      
      // Check if target role is an existing superuser
      final role = await widget.dbService.fetchRoleByName(roleName);
      if (role != null && role.isSuperuser) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot use an existing superuser as a Role Admin.')),
        );
        return;
      }

      await widget.dbService.setupRoleAdmin(roleName, _passController.text);
      
      if (mounted) {
        Navigator.of(context).pop({'user': roleName, 'pass': _passController.text});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Setup failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Role Admin'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Running as superuser is not allowed for security reasons. '
                'We will set up a dedicated "Role Admin" account with the minimal '
                'permissions needed to manage non-login roles.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Admin Username', border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passController,
                decoration: const InputDecoration(labelText: 'Admin Password', border: OutlineInputBorder()),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _setup,
          child: _isSaving 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
            : const Text('Setup Admin'),
        ),
      ],
    );
  }
}
