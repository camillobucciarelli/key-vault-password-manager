import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/presentation/widgets/database/drive_picker_sheet.dart';

void main() {
  group('driveOpenErrorMessage', () {
    test('keeps the platform code and description of an unrecognized '
        'Google failure so field reports are diagnosable', () {
      final message = driveOpenErrorMessage(
        Exception(
          'Google sign-in failed (uiUnavailable): No Activity is available',
        ),
      );

      expect(message, contains('uiUnavailable'));
      expect(message, contains('No Activity is available'));
      expect(message, isNot(startsWith('Exception:')));
    });

    test('recognized failures keep their existing copy', () {
      expect(
        driveOpenErrorMessage(Exception('Google sign-in cancelled.')),
        'Google sign-in was cancelled during authorization. Please try again and grant Drive permissions.',
      );
      expect(
        driveOpenErrorMessage(Exception('something else entirely')),
        'Unable to open database from Google Drive.',
      );
    });
  });
}
