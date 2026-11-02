import 'package:flutter_test/flutter_test.dart';
import 'package:user_manager/models/pg_role.dart';
import 'package:user_manager/services/database_service.dart';

void main() {
  group('PgRole validUntil parsing and formatting', () {
    test('formatDate formats DateTime as YYYY-MM-DD', () {
      expect(PgRole.formatDate(DateTime(2026, 3, 5)), '2026-03-05');
      expect(PgRole.formatDate(DateTime(2026, 12, 31, 14, 30)), '2026-12-31');
    });

    test('fromRow parses valid_until string column into date-only DateTime', () {
      final row = [
        101,
        'temp_user',
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        'Temporary contractor',
        true,
        true,
        '2027-06-15',
      ];
      final role = PgRole.fromRow(row);
      expect(role.validUntil, DateTime(2027, 6, 15));
      expect(role.validUntilDateString, '2027-06-15');
    });

    test('fromRow handles null valid_until column', () {
      final row = [
        102,
        'perm_user',
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        null,
        true,
        true,
        null,
      ];
      final role = PgRole.fromRow(row);
      expect(role.validUntil, isNull);
      expect(role.validUntilDateString, isNull);
      expect(role.isValid, isTrue);
      expect(role.isExpiringSoon, isFalse);
    });

    test('fromRow parses is_valid and is_expiring_soon columns', () {
      final row = [
        103,
        'expiring_user',
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        null,
        true,
        true,
        '2026-11-05',
        true,
        true,
      ];
      final role = PgRole.fromRow(row);
      expect(role.validUntilDateString, '2026-11-05');
      expect(role.isValid, isTrue);
      expect(role.isExpiringSoon, isTrue);
    });
  });

  group('DatabaseService SQL Escaping Utilities', () {
    group('escapeIdentifier', () {
      test('correctly quotes simple identifier', () {
        expect(DatabaseService.escapeIdentifier('alice'), '"alice"');
        expect(DatabaseService.escapeIdentifier('dbroles'), '"dbroles"');
      });

      test('correctly escapes embedded double quotes by doubling them', () {
        expect(DatabaseService.escapeIdentifier('alice"admin'), '"alice""admin"');
        expect(DatabaseService.escapeIdentifier('test""role'), '"test""""role"');
        expect(DatabaseService.escapeIdentifier('"'), '""""');
      });

      test('handles spaces, punctuation, and uppercase characters', () {
        expect(DatabaseService.escapeIdentifier('Engineering Team'), '"Engineering Team"');
        expect(DatabaseService.escapeIdentifier('role-with-dashes'), '"role-with-dashes"');
        expect(DatabaseService.escapeIdentifier('MyRole_123'), '"MyRole_123"');
      });

      test('safely quotes PostgreSQL reserved keywords', () {
        expect(DatabaseService.escapeIdentifier('select'), '"select"');
        expect(DatabaseService.escapeIdentifier('user'), '"user"');
        expect(DatabaseService.escapeIdentifier('table'), '"table"');
        expect(DatabaseService.escapeIdentifier('drop'), '"drop"');
      });

      test('throws ArgumentError on null byte character in identifier', () {
        expect(
          () => DatabaseService.escapeIdentifier('alice\u0000admin'),
          throwsArgumentError,
        );
      });
    });

    group('escapeLiteral', () {
      test('correctly quotes simple literal', () {
        expect(DatabaseService.escapeLiteral('secret123'), "'secret123'");
        expect(DatabaseService.escapeLiteral(''), "''");
      });

      test('correctly escapes embedded single quotes by doubling them', () {
        expect(DatabaseService.escapeLiteral("p@ss'word"), "'p@ss''word'");
        expect(DatabaseService.escapeLiteral("O'Reilly"), "'O''Reilly'");
        expect(DatabaseService.escapeLiteral("'''"), "''''''''");
      });

      test('handles backslashes and double quotes inside string literals', () {
        expect(DatabaseService.escapeLiteral(r'path\to\something'), r"'path\to\something'");
        expect(DatabaseService.escapeLiteral('has"quotes"inside'), "'has\"quotes\"inside'");
      });

      test('safely escapes multiline descriptions or comments', () {
        const comment = "Role for HR's department & team";
        expect(DatabaseService.escapeLiteral(comment), "'Role for HR''s department & team'");
      });

      test('throws ArgumentError on null byte character in string literal', () {
        expect(
          () => DatabaseService.escapeLiteral('pass\u0000word'),
          throwsArgumentError,
        );
      });
    });
  });
}
