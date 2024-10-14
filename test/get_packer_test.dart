import 'dart:typed_data';

import 'package:get_packer/get_packer.dart';
import 'package:test/test.dart';

void main() {
  group('GetPacker', () {
    test('pack and unpack null', () {
      final packed = GetPacker.pack(null);
      final unpacked = GetPacker.unpack(packed);
      expect(unpacked, isNull);
    });

    test('pack and unpack bool', () {
      expect(GetPacker.unpack(GetPacker.pack(true)), isTrue);
      expect(GetPacker.unpack(GetPacker.pack(false)), isFalse);
    });

    test('pack and unpack int', () {
      final testInts = [-1000000, -1, 0, 1, 1000000];
      for (final i in testInts) {
        expect(GetPacker.unpack(GetPacker.pack(i)), equals(i));
      }
    });

    test('pack and unpack double', () {
      final testDoubles = [-3.14, 0.0, 3.14, double.infinity, double.nan];
      for (final d in testDoubles) {
        final unpacked = GetPacker.unpack(GetPacker.pack(d));
        if (d.isNaN) {
          expect(unpacked.isNaN, isTrue);
        } else {
          expect(unpacked, equals(d));
        }
      }
    });

    test('pack and unpack string', () {
      final testStrings = ['', 'hello', 'こんにちは', '🌍🌎🌏'];
      for (final s in testStrings) {
        expect(GetPacker.unpack(GetPacker.pack(s)), equals(s));
      }
    });

    test('pack and unpack Uint8List', () {
      final data = Uint8List.fromList([0, 1, 2, 3, 4]);
      final unpacked = GetPacker.unpack(GetPacker.pack(data));
      expect(unpacked, equals(data));
    });

    test('pack and unpack List', () {
      final list = [
        1,
        'two',
        3.0,
        [4, 5],
        {'six': 6}
      ];
      final unpacked = GetPacker.unpack(GetPacker.pack(list));
      expect(unpacked, equals(list));
    });

    test('pack and unpack Set', () {
      final set = {1, 'two', 3.0};
      final unpacked = GetPacker.unpack(GetPacker.pack(set));
      expect(unpacked, equals(set.toList()));
    });

    test('pack and unpack Map', () {
      final map = {
        'int': 1,
        'string': 'two',
        'double': 3.0,
        'list': [4, 5],
        'map': {'six': 6}
      };
      final unpacked = GetPacker.unpack(GetPacker.pack(map));
      expect(unpacked, equals(map));
    });

    test('pack and unpack DateTime', () {
      final now = DateTime.now();
      final DateTime unpacked = GetPacker.unpack(GetPacker.pack(now));
      expect(unpacked, equals(now));
    });

    test('pack and unpack BigInt', () {
      final testBigInts = [
        BigInt.from(-1000000),
        BigInt.from(-1),
        BigInt.zero,
        BigInt.one,
        BigInt.from(1000000)
      ];
      for (final i in testBigInts) {
        expect(GetPacker.unpack(GetPacker.pack(i)), equals(i));
      }
    });

    test('pack and unpack complex data', () {
      final Map<String, dynamic> testData = {
        'nullValue': null,
        'boolean': true,
        'integer': 42,
        'negativeInteger': -42,
        'double': 3.14159,
        'string': 'Hello, World!',
        'binary': Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        'array': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        'map': {'key1': 'value1', 'key2': 'value2', 'key3': 'value3'},
        'nestedArray': [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9]
        ],
        'nestedMap': {
          'outer1': {'inner1': 'value1', 'inner2': 'value2'},
          'outer2': {'inner3': 'value3', 'inner4': 'value4'}
        },
        'mixedArray': [
          1,
          'two',
          3.0,
          true,
          null,
          {'key': 'value'}
        ],
        'complexObject': {
          'id': 1001,
          'name': 'Complex Object',
          'attributes': ['attr1', 'attr2', 'attr3'],
          'metadata': {
            'created': '2023-09-30T12:00:00Z',
            'updated': '2023-09-30T14:30:00Z',
            'tags': ['tag1', 'tag2', 'tag3']
          }
        },
        'longString': 'This is a much longer string that contains multiple sentences. '
            'It can be used to test how the system handles larger text inputs. '
            'The string can contain various characters and punctuation marks!',
        'dateTime': DateTime.now(),
        'largeInteger': 1234567890123456789,
        'negativeDouble': -273.15,
        'emptyStructures': {
          'emptyArray': [],
          'emptyMap': {},
          'emptyString': ''
        },
        'deeplyNestedStructure': {
          'level1': {
            'level2': {
              'level3': {
                'level4': {'level5': 'Deep value'}
              }
            }
          }
        },
        'repeatingData': List.generate(
            5,
            (index) => {
                  'id': index,
                  'name': 'Item ${index + 1}',
                  'isEven': index % 2 == 0
                }),
      };

      final packed = GetPacker.pack(testData);
      final unpacked = GetPacker.unpack(packed);

      expect(unpacked, equals(testData));
    });

    test('handle BigDataException', () {
      // Create a custom Iterable that pretends to be very large
      final largeIterable = LargeIterable();

      expect(
        () => GetPacker.pack(largeIterable),
        throwsA(isA<BigDataException>()),
      );
    });
  });
}

class LargeIterable extends Iterable<int> {
  @override
  Iterator<int> get iterator => LargeIterator();
}

class LargeIterator implements Iterator<int> {
  int _current = -1;

  @override
  int get current => _current;

  @override
  bool moveNext() {
    if (_current >= 0x100000000 - 1) return false;
    _current++;
    return true;
  }
}
