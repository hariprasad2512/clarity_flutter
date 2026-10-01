import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/auth/account_profile.dart';

void main() {
  group('AccountProfile.displayName', () {
    test('prefers full_name, then name, then given+family', () {
      expect(
        AccountProfile.displayName(
          metadata: {'full_name': 'Hari Prasad', 'name': 'Other'},
          email: 'h@example.com',
        ),
        'Hari Prasad',
      );
      expect(
        AccountProfile.displayName(
          metadata: {'name': 'Hari P'},
          email: 'h@example.com',
        ),
        'Hari P',
      );
      expect(
        AccountProfile.displayName(
          metadata: {'given_name': 'Hari', 'family_name': 'Prasad'},
          email: 'h@example.com',
        ),
        'Hari Prasad',
      );
    });

    test('falls back to email prefix, email, Local only', () {
      expect(
        AccountProfile.displayName(email: 'hprasad887@gmail.com'),
        'hprasad887',
      );
      expect(
        AccountProfile.displayName(metadata: {}, email: '  spaced@x.co '),
        'spaced',
      );
      expect(AccountProfile.displayName(), 'Local only');
      expect(
        AccountProfile.displayName(metadata: {'full_name': '  '}),
        'Local only',
      );
    });
  });

  group('AccountProfile.photoUrl', () {
    test('prefers avatar_url, then picture, else null', () {
      expect(
        AccountProfile.photoUrl({
          'avatar_url': 'https://a.img',
          'picture': 'https://b.img',
        }),
        'https://a.img',
      );
      expect(
        AccountProfile.photoUrl({'picture': 'https://b.img'}),
        'https://b.img',
      );
      expect(AccountProfile.photoUrl({}), isNull);
      expect(AccountProfile.photoUrl(null), isNull);
      expect(
        AccountProfile.photoUrl({'avatar_url': '  '}),
        isNull,
      );
    });
  });

  group('AccountProfile.initial', () {
    test('uppercases first letter, placeholder when blank', () {
      expect(AccountProfile.initial('hari'), 'H');
      expect(AccountProfile.initial(' Hari '), 'H');
      expect(AccountProfile.initial(''), '○');
    });
  });
}
