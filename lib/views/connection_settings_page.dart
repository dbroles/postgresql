import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postgres/postgres.dart';
import '../services/database_service.dart';
import '../services/credential_storage_service.dart';
import 'connection_status_bar.dart';
import 'create_role_admin_dialog.dart';
import 'role_admin_success_dialog.dart';

class SavedConnectionProfile {
  final String host;
  final int port;
  final String database;
  final String username;
  final bool useSsl;
  final bool rememberPassword;

  const SavedConnectionProfile({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.useSsl,
    required this.rememberPassword,
  });

  String get key => CredentialStorageService.connectionStorageKey(
        host: host,
        port: port,
        database: database,
        username: username,
      );

  String get label => ConnectionStatusBar.formatConnectionTarget(
        username: username,
        host: host,
        port: port,
        database: database,
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'database': database,
        'username': username,
        'useSsl': useSsl,
        'rememberPassword': rememberPassword,
      };

  factory SavedConnectionProfile.fromJson(Map<String, dynamic> json) {
    return SavedConnectionProfile(
      host: (json['host'] as String?) ?? 'localhost',
      port: (json['port'] as int?) ?? 5432,
      database: (json['database'] as String?) ?? 'postgres',
      username: (json['username'] as String?) ?? 'dbroles',
      useSsl: (json['useSsl'] as bool?) ?? true,
      rememberPassword: (json['rememberPassword'] as bool?) ?? true,
    );
  }
}

typedef DatabaseServiceFactory = DatabaseService Function({
  String host,
  int port,
  String database,
  String username,
  String password,
  SslMode sslMode,
});

class ConnectionSettingsPage extends StatefulWidget {
  final DatabaseService dbService;
  final CredentialStorageService? credentialStorage;
  final DatabaseServiceFactory? databaseServiceFactory;

  const ConnectionSettingsPage({
    super.key,
    required this.dbService,
    this.credentialStorage,
    this.databaseServiceFactory,
  });

  @override
  State<ConnectionSettingsPage> createState() => _ConnectionSettingsPageState();
}

class _ConnectionSettingsPageState extends State<ConnectionSettingsPage> {
  static const String savedConnectionsPrefKey = 'saved_connections';
  static const int _maxSavedConnections = 10;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _dbController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  late bool _useSsl;
  late final CredentialStorageService _credentialStorage;
  bool _rememberPassword = true;
  List<SavedConnectionProfile> _savedConnections = [];
  
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.dbService.host);
    _portController = TextEditingController(text: widget.dbService.port.toString());
    _dbController = TextEditingController(text: widget.dbService.database);
    _userController = TextEditingController(text: widget.dbService.username);
    _passController = TextEditingController(text: widget.dbService.password);
    _useSsl = widget.dbService.sslMode != SslMode.disable;
    _credentialStorage = widget.credentialStorage ?? CredentialStorageService();
    _loadRememberPasswordPreference();
  }

  Future<void> _loadRememberPasswordPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('db_remember_pass') ?? true;
    final rawSaved = prefs.getStringList(savedConnectionsPrefKey) ?? [];
    final savedProfiles = <SavedConnectionProfile>[];
    for (final item in rawSaved) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          savedProfiles.add(SavedConnectionProfile.fromJson(decoded));
        }
      } catch (_) {}
    }

    String? securePass;
    if (remember && _passController.text.isEmpty) {
      final connKey = CredentialStorageService.connectionStorageKey(
        host: widget.dbService.host,
        port: widget.dbService.port,
        database: widget.dbService.database,
        username: widget.dbService.username,
      );
      securePass = await _credentialStorage.getPassword(connectionKey: connKey);
    }
    if (mounted) {
      setState(() {
        _rememberPassword = remember;
        _savedConnections = savedProfiles;
        if (securePass != null && _passController.text.isEmpty) {
          _passController.text = securePass;
        }
      });
    }
  }

  Future<void> _selectSavedConnection(SavedConnectionProfile profile) async {
    String? storedPass;
    if (profile.rememberPassword) {
      storedPass = await _credentialStorage.getPassword(
        connectionKey: profile.key,
        fallbackToDefault: false,
      );
    }
    if (!mounted) return;
    setState(() {
      _hostController.text = profile.host;
      _portController.text = profile.port.toString();
      _dbController.text = profile.database;
      _userController.text = profile.username;
      _passController.text = storedPass ?? '';
      _useSsl = profile.useSsl;
      _rememberPassword = profile.rememberPassword;
      _testResult = null;
    });
  }

  Future<void> _deleteSavedConnection(SavedConnectionProfile profile) async {
    setState(() {
      _savedConnections.removeWhere((p) => p.key == profile.key);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      savedConnectionsPrefKey,
      _savedConnections.map((p) => jsonEncode(p.toJson())).toList(),
    );
    await _credentialStorage.deletePassword(
      connectionKey: profile.key,
      onlyScoped: true,
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _dbController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final factory = widget.databaseServiceFactory ?? DatabaseService.new;
    final testService = factory(
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      database: _dbController.text.trim().isEmpty ? 'postgres' : _dbController.text.trim(),
      username: _userController.text.trim(),
      password: _passController.text, // Don't trim password
      sslMode: _useSsl ? SslMode.require : SslMode.disable,
    );

    final error = await testService.testConnection();
    await testService.close();
    
    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = error == null;
        _testResult = error ?? 'Connection successful!';
      });
    }
  }

  Future<void> _saveAndConnect() async {
    if (!_formKey.currentState!.validate()) return;

    final host = _hostController.text.trim();
    final portString = _portController.text.trim();
    final database = _dbController.text.trim().isEmpty ? 'postgres' : _dbController.text.trim();
    final username = _userController.text.trim();
    final password = _passController.text;
    final port = int.parse(portString);

    // Temporary service for validation
    final factory = widget.databaseServiceFactory ?? DatabaseService.new;
    final tempService = factory(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      sslMode: _useSsl ? SslMode.require : SslMode.disable,
    );

    final error = await tempService.testConnection();
    if (error != null) {
      await tempService.close();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot connect: $error')),
      );
      return;
    }

    // Security check: Check if superuser
    final isSuper = await tempService.isCurrentUserSuperuser();
    if (isSuper) {
      if (!mounted) {
        await tempService.close();
        return;
      }
      final newCreds = await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => CreateRoleAdminDialog(dbService: tempService),
      );

      await tempService.close();

      if (newCreds != null) {
        if (!mounted) return;
        
        // Show success screen with reminder
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const RoleAdminSuccessDialog(),
        );

        if (!mounted) return;

        // Automatically pre-fill the form with new credentials
        _userController.text = newCreds['user']!;
        _passController.text = newCreds['pass']!;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credentials updated. Please click Save & Connect.')),
        );
      }
      return;
    }

    await tempService.close();

    // Standard save logic
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('db_host', host);
    await prefs.setInt('db_port', port);
    await prefs.setString('db_name', database);
    final sslMode = _useSsl ? SslMode.require : SslMode.disable;
    await prefs.setString('db_user', username);
    await prefs.setBool('db_remember_pass', _rememberPassword);
    await prefs.setInt('db_ssl_mode', sslMode.index);

    final profile = SavedConnectionProfile(
      host: host,
      port: port,
      database: database,
      username: username,
      useSsl: _useSsl,
      rememberPassword: _rememberPassword,
    );
    _savedConnections.removeWhere((p) => p.key == profile.key);
    _savedConnections.insert(0, profile);
    if (_savedConnections.length > _maxSavedConnections) {
      _savedConnections = _savedConnections.sublist(0, _maxSavedConnections);
    }
    await prefs.setStringList(
      savedConnectionsPrefKey,
      _savedConnections.map((p) => jsonEncode(p.toJson())).toList(),
    );

    if (_rememberPassword) {
      await _credentialStorage.savePassword(password, connectionKey: profile.key);
    } else {
      await _credentialStorage.deletePassword(connectionKey: profile.key);
    }

    widget.dbService.host = host;
    widget.dbService.port = port;
    widget.dbService.database = database;
    widget.dbService.username = username;
    widget.dbService.password = password;
    widget.dbService.sslMode = sslMode;
    widget.dbService.resetCache();

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Settings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth > 500;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_savedConnections.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Saved Connections',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _savedConnections.map((profile) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: InputChip(
                              key: ValueKey('saved_conn_${profile.key}'),
                              avatar: Icon(
                                profile.useSsl ? Icons.lock_outline : Icons.storage_outlined,
                                size: 16,
                              ),
                              label: Text(profile.label),
                              tooltip: 'Load ${profile.label}',
                              onPressed: () => _selectSavedConnection(profile),
                              onDeleted: () => _deleteSavedConnection(profile),
                              deleteButtonTooltipMessage: 'Remove saved connection',
                              visualDensity: VisualDensity.compact,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _hostController,
                            decoration: const InputDecoration(
                              labelText: 'Hostname / IP',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) => v == null || int.tryParse(v) == null ? 'Invalid port' : null,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    TextFormField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Hostname / IP',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v == null || int.tryParse(v) == null ? 'Invalid port' : null,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dbController,
                    decoration: const InputDecoration(
                      labelText: 'Database',
                      hintText: 'postgres',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _userController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Remember password'),
                            subtitle: const Text('Save password securely in system keychain'),
                            value: _rememberPassword,
                            onChanged: (val) => setState(() => _rememberPassword = val),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Use SSL'),
                            subtitle: const Text('Encrypt connection to the database'),
                            value: _useSsl,
                            onChanged: (val) => setState(() => _useSsl = val),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Remember password'),
                      subtitle: const Text('Save password securely in system keychain'),
                      value: _rememberPassword,
                      onChanged: (val) => setState(() => _rememberPassword = val),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Use SSL'),
                      subtitle: const Text('Encrypt connection to the database'),
                      value: _useSsl,
                      onChanged: (val) => setState(() => _useSsl = val),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_testResult != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        _testResult!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _testSuccess ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (isWide)
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _isTesting ? null : _testConnection,
                              icon: _isTesting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.bolt),
                              label: const Text('Test Connection'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _saveAndConnect,
                              icon: const Icon(Icons.save),
                              label: const Text('Save & Connect'),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _isTesting ? null : _testConnection,
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.bolt),
                            label: const Text('Test Connection'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _saveAndConnect,
                            icon: const Icon(Icons.save),
                            label: const Text('Save & Connect'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
