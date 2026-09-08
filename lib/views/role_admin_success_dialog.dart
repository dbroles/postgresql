import 'package:flutter/material.dart';

class RoleAdminSuccessDialog extends StatelessWidget {
  const RoleAdminSuccessDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade600),
          const SizedBox(width: 12),
          const Text('Role Admin Created'),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'The administrative account has been successfully configured with the necessary permissions.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          Text(
            'Gentle Reminder: Your DBA might need to update the pg_hba.conf file on the server to allow this new user access to the database.',
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Continue to Connection'),
        ),
      ],
    );
  }
}
