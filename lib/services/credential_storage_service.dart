import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Workaround subclass for flutter_secure_storage_darwin key naming mismatch
/// where native Swift expects 'useDataProtectionKeyChain' while Dart sends 'usesDataProtectionKeychain'.
class const AppMacOsOptions({
  super.accountName,
  super.accessibility = .first_unlock,
  super.synchronizable,
  super.useSecureEnclave,
  super.usesDataProtectionKeychain = false,
  super.groupId,
}) extends MacOsOptions {
  @override
  Map<String, String> toMap() {
    final map = super.toMap();
    final value = map['usesDataProtectionKeychain'];
    if (value != null) {
      map['useDataProtectionKeyChain'] = value;
      map['useDataProtectionKeychain'] = value;
    }
    if (map.containsKey('useSecureEnclave')) {
      map['usesSecureEnclave'] = map['useSecureEnclave']!;
    }
    return map;
  }
}

/// Service responsible for managing database credentials securely
/// via the operating system's native keychain/credential manager.
class CredentialStorageService({FlutterSecureStorage? storage}) {
  static const String _dbPassKey = 'db_pass';
  static const MacOsOptions _macOsOptions = AppMacOsOptions();

  final FlutterSecureStorage _storage = storage ??
      const FlutterSecureStorage(
        mOptions: _macOsOptions,
      );

  /// Builds a canonical key for scoping credentials to a specific connection.
  static String connectionStorageKey({
    required String host,
    required int port,
    required String database,
    required String username,
  }) =>
      '$host:$port:$username:$database';

  static String _scopedKey(String connectionKey) => '${_dbPassKey}_$connectionKey';

  /// Retrieves the stored database password, or `null` if not found or on error.
  /// If [connectionKey] is provided, checks the connection-specific key first
  /// and falls back to the active default password key.
  Future<String?> getPassword({String? connectionKey, bool fallbackToDefault = true}) async {
    try {
      if (connectionKey != null && connectionKey.isNotEmpty) {
        final scopedValue = await _storage.read(
          key: _scopedKey(connectionKey),
          mOptions: _macOsOptions,
        );
        if (scopedValue != null && scopedValue.isNotEmpty) {
          return scopedValue;
        }
        if (!fallbackToDefault) {
          return null;
        }
      }
      final value = await _storage.read(key: _dbPassKey, mOptions: _macOsOptions);
      if (value == null || value.isEmpty) {
        return null;
      }
      return value;
    } catch (e, st) {
      developer.log('Error reading password from secure storage', error: e, stackTrace: st);
      return null;
    }
  }

  /// Securely stores the database password.
  Future<void> savePassword(String password, {String? connectionKey}) async {
    try {
      await _storage.write(key: _dbPassKey, value: password, mOptions: _macOsOptions);
      if (connectionKey != null && connectionKey.isNotEmpty) {
        await _storage.write(
          key: _scopedKey(connectionKey),
          value: password,
          mOptions: _macOsOptions,
        );
      }
    } catch (e, st) {
      developer.log('Error saving password to secure storage', error: e, stackTrace: st);
    }
  }

  Future<void> _deleteSingleKey(String key) async {
    try {
      await _storage.write(key: key, value: '', mOptions: _macOsOptions);
    } catch (e, st) {
      developer.log('Error clearing password in secure storage', error: e, stackTrace: st);
    }

    try {
      await _storage.delete(key: key, mOptions: _macOsOptions);
    } on PlatformException catch (e, st) {
      if (e.code == '-34018' ||
          e.details == -34018 ||
          e.message?.contains('-34018') == true) {
        return;
      }
      developer.log('Error deleting password from secure storage', error: e, stackTrace: st);
    } catch (e, st) {
      developer.log('Error deleting password from secure storage', error: e, stackTrace: st);
    }
  }

  /// Deletes the stored database password from secure storage.
  Future<void> deletePassword({String? connectionKey, bool onlyScoped = false}) async {
    if (!onlyScoped) {
      await _deleteSingleKey(_dbPassKey);
    }
    if (connectionKey != null && connectionKey.isNotEmpty) {
      await _deleteSingleKey(_scopedKey(connectionKey));
    }
  }
}
