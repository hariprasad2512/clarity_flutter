import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/sync/delete_outbox.dart';

void main() {
  group('DeleteOutbox codec', () {
    test('round-trips id sets', () {
      const ids = {'a', 'b', 'c'};
      expect(DeleteOutbox.decode(DeleteOutbox.encode(ids)), ids);
    });

    test('drops empty ids on encode', () {
      expect(
        DeleteOutbox.decode(DeleteOutbox.encode({'a', '', 'b'})),
        {'a', 'b'},
      );
    });

    test('drops malformed input on decode', () {
      expect(DeleteOutbox.decode(null), isEmpty);
      expect(DeleteOutbox.decode(''), isEmpty);
      expect(DeleteOutbox.decode('not-json'), isEmpty);
      expect(DeleteOutbox.decode('{"a":1}'), isEmpty);
      expect(DeleteOutbox.decode('[1, null, "", "x"]'), {'x'});
    });

    test('empty set encodes to empty list', () {
      expect(DeleteOutbox.decode(DeleteOutbox.encode({})), isEmpty);
    });
  });
}
