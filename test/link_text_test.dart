import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/ui/link_text.dart';

List<String> _links(String text) => [
      for (final s in splitLinks(text))
        if (s.isLink) s.text,
    ];

String _plain(String text) => [
      for (final s in splitLinks(text))
        if (!s.isLink) s.text,
    ].join();

void main() {
  group('splitLinks', () {
    test('plain text yields a single non-link segment', () {
      final segs = splitLinks('Buy milk tomorrow');
      expect(segs, hasLength(1));
      expect(segs.single.isLink, isFalse);
    });

    test('detects https urls', () {
      expect(
        _links('Read https://example.com/docs today'),
        ['https://example.com/docs'],
      );
      expect(
        _plain('Read https://example.com/docs today'),
        'Read  today',
      );
    });

    test('detects http and www urls', () {
      expect(_links('go http://x.io/a'), ['http://x.io/a']);
      expect(_links('go www.example.com/a'), ['www.example.com/a']);
    });

    test('trims trailing punctuation', () {
      expect(
        _links('See https://x.io, then (www.y.io). Done!'),
        ['https://x.io', 'www.y.io'],
      );
    });

    test('handles multiple urls', () {
      expect(
        _links('a https://one.io b www.two.io c'),
        ['https://one.io', 'www.two.io'],
      );
    });

    test('empty text yields one empty segment', () {
      final segs = splitLinks('');
      expect(segs, hasLength(1));
      expect(segs.single.isLink, isFalse);
    });
  });
}
