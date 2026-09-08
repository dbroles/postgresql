import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Workaround subclass for flutter_secure_storage_darwin key naming mismatch
/// where native Swift expects 'useDataProtectionKeyChain' while Dart sends 'usesDataProtectionKeychain'.
class AppMacOsOptions extends MacOsOptions {
  const AppMacOsOptions({
    super.accountName,
    super.accessibility = KeychainAccessibility.first_unlock,
    super.synchronizable,
    super.useSecureEnclave,
    super.usesDataProtectionKeychain = false,
    super.groupId,
  });

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
class CredentialStorageService {
  static const String _dbPassKey = 'db_pass';
  static const MacOsOptions _macOsOptions = AppMacOsOptions();

  final FlutterSecureStorage _storage;

  CredentialStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: _macOsOptions,
            );

  /// Retrieves the stored database password, or `null` if not found or on error.
  Future<String?> getPassword() async {
    try {
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
  Future<void> savePassword(String password) async {
    try {
      await _storage.write(key: _dbPassKey, value: password, mOptions: _macOsOptions);
    } catch (e, st) {
      developer.log('Error saving password to secure storage', error: e, stackTrace: st);
    }
  }

  /// Deletes the stored database password from secure storage.
  Future<void> deletePassword() async {
    try {
      // Overwrite the password with an empty string first so that the sensitive
      // value is cleared immediately even if Keychain deletion encounters a platform error.
      await _storage.write(key: _dbPassKey, value: '', mOptions: _macOsOptions);
    } catch (e, st) {
      developer.log('Error clearing password in secure storage', error: e, stackTrace: st);
    }

    try {
      await _storage.delete(key: _dbPassKey, mOptions: _macOsOptions);
    } on PlatformException catch (e, st) {
      // On macOS without iCloud Keychain entitlements, SecItemDelete checks
      // synchronizable items first, returning -34018 (errSecMissingEntitlement)
      // if the item is not found or synchronizable is unsupported.
      // Since the password has already been cleared, ignore -34018.
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
}
