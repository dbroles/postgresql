import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:user_manager/services/credential_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('CredentialStorageService Tests', () {
    test('getPassword returns null when no password is saved', () async {
      final service = CredentialStorageService();
      final pass = await service.getPassword();
      expect(pass, isNull);
    });

    test('savePassword saves and getPassword retrieves password', () async {
      final service = CredentialStorageService();
      await service.savePassword('my_super_secret_pw');
      final pass = await service.getPassword();
      expect(pass, 'my_super_secret_pw');
    });

    test('deletePassword removes the stored password', () async {
      final service = CredentialStorageService();
      await service.savePassword('temporary_pw');
      expect(await service.getPassword(), 'temporary_pw');

      await service.deletePassword();
      expect(await service.getPassword(), isNull);
    });

    test('getPassword returns null when stored password is empty string', () async {
      final service = CredentialStorageService();
      await service.savePassword('');
      expect(await service.getPassword(), isNull);
    });

    test('AppMacOsOptions outputs legacy and modern key names for Swift compatibility', () {
      const options = AppMacOsOptions();
      final map = options.toMap();
      expect(map['usesDataProtectionKeychain'], 'false');
      expect(map['useDataProtectionKeyChain'], 'false');
      expect(map['useDataProtectionKeychain'], 'false');
    });
  });
}
