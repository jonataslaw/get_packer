import 'dart:collection';
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

    group('IntInteropMode', () {
      test(
          'promoteWideToBigInt: wide List<int> decodes to BigInt elements (no typed-list bypass)',
          () {
        const cfg =
            GetPackerConfig(intInteropMode: IntInteropMode.promoteWideToBigInt);

        // > 2^53-1 (JS-safe int), still fits in int64 on the VM.
        const v = 1234567890123456789;
        final list = List<int>.filled(cfg.numericListPromotionMinLength, v);

        final packed = GetPacker.pack(list, config: cfg);
        final unpacked = GetPacker.unpack<List<dynamic>>(packed, config: cfg);

        expect(unpacked.length, equals(list.length));
        expect(unpacked.every((e) => e is BigInt), isTrue);
        expect(unpacked.first, equals(BigInt.from(v)));
      });

      test('requireBigIntForWide: rejects wide List<int> at encode time', () {
        const cfg = GetPackerConfig(
            intInteropMode: IntInteropMode.requireBigIntForWide);
        const v = 1234567890123456789;
        final list = List<int>.filled(cfg.numericListPromotionMinLength, v);

        expect(() => GetPacker.pack(list, config: cfg),
            throwsA(isA<ArgumentError>()));
      });
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

    group('String', () {
      test('encodes empty string', () {
        final str = '';
        expect(GetPacker.unpack(GetPacker.pack(str)), equals(str));
      });

      test('encodes short string (length <= 31)', () {
        final str = 'Hello';
        expect(GetPacker.unpack(GetPacker.pack(str)), equals(str));
      });

      test('encodes string with length 31', () {
        final str = 'a' * 31;
        expect(GetPacker.unpack(GetPacker.pack(str)), equals(str));
      });

      test('encodes string with length 32 (0xFF)', () {
        final str = 'a' * 32;
        expect(GetPacker.unpack(GetPacker.pack(str)), equals(str));
      });

      test('encodes string with length 255', () {
        final str = 'a' * 255;
        expect(GetPacker.unpack(GetPacker.pack(str)), equals(str));
      });

      test('encodes string with length 256 (0xFFFF)', () {
        final str = 'a' * 256;
        expect(GetPacker.unpack(GetPacker.pack(str)), equals(str));
      });

      test('encodes string with length 65535', () {
        final str = 'a' * 65535;
        expect(GetPacker.unpack(GetPacker.pack(str)), equals(str));
      });

      test('encodes string with length 65536 (0xFFFFFFFF)', () {
        final str = 'a' * 65536;
        expect(GetPacker.unpack(GetPacker.pack(str)), equals(str));
      });

      test('encodes string with length 16777216 (16MB)', () {
        final str = 'a' * 16777216;
        expect(GetPacker.unpack(GetPacker.pack(str)), equals(str));
      });

      test('throws BigDataException when string exceeds maxStringUtf8Bytes cap',
          () {
        const cfg = GetPackerConfig(maxStringUtf8Bytes: 3);
        expect(
          () => GetPacker.pack('abcd', config: cfg),
          throwsA(isA<GetPackerLimitExceededException>()),
        );
      });

      test(
          'throws BigDataException when UTF-8 string exceeds maxStringUtf8Bytes cap',
          () {
        const cfg = GetPackerConfig(maxStringUtf8Bytes: 3);
        expect(
          () => GetPacker.pack('🌍', config: cfg),
          throwsA(isA<GetPackerLimitExceededException>()),
        );
      });

      test('pack and unpack string with special characters', () {
        final testStrings = ['', 'hello', 'こんにちは', '🌍🌎🌏'];
        for (final s in testStrings) {
          expect(GetPacker.unpack(GetPacker.pack(s)), equals(s));
        }
      });
    });

    group('Binary', () {
      test('encodes empty binary', () {
        final data = Uint8List(0);
        expect(GetPacker.unpack(GetPacker.pack(data)), equals(data));
      });

      test('encodes short binary (length <= 31)', () {
        final data = Uint8List.fromList([0, 1, 2, 3, 4]);
        expect(GetPacker.unpack(GetPacker.pack(data)), equals(data));
      });

      test('encodes binary with length 31', () {
        final data = Uint8List(31);
        expect(GetPacker.unpack(GetPacker.pack(data)), equals(data));
      });

      test('encodes binary with length 32 (0xFF)', () {
        final data = Uint8List(32);
        expect(GetPacker.unpack(GetPacker.pack(data)), equals(data));
      });

      test('encodes binary with length 255', () {
        final data = Uint8List(255);
        expect(GetPacker.unpack(GetPacker.pack(data)), equals(data));
      });

      test('encodes binary with length 256 (0xFFFF)', () {
        final data = Uint8List(256);
        expect(GetPacker.unpack(GetPacker.pack(data)), equals(data));
      });

      test('encodes binary with length 65535', () {
        final data = Uint8List(65535);
        expect(GetPacker.unpack(GetPacker.pack(data)), equals(data));
      });

      test('encodes binary with length 65536 (0xFFFFFFFF)', () {
        final data = Uint8List(65536);
        expect(GetPacker.unpack(GetPacker.pack(data)), equals(data));
      });

      test('encodes binary with length 16777216 (16MB)', () {
        final data = Uint8List(16777216);
        expect(GetPacker.unpack(GetPacker.pack(data)), equals(data));
      });

      test('throws BigDataException when binary exceeds maxBinaryBytes cap',
          () {
        const cfg = GetPackerConfig(maxBinaryBytes: 3);
        final data = Uint8List(4);
        expect(
          () => GetPacker.pack(data, config: cfg),
          throwsA(isA<GetPackerLimitExceededException>()),
        );
      });
    });

    group('List', () {
      test('pack and unpack List with many types', () {
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
      test('encodes empty list', () {
        final list = <dynamic>[];
        expect(GetPacker.unpack(GetPacker.pack(list)), equals(list));
      });

      test('encodes short list (length <= 31)', () {
        final list = [1, 2, 3, 4, 5];
        expect(GetPacker.unpack(GetPacker.pack(list)), equals(list));
      });

      test('encodes list with length 31', () {
        final list = List.generate(31, (index) => index);
        expect(GetPacker.unpack(GetPacker.pack(list)), equals(list));
      });

      test('encodes list with length 32 (0xFF)', () {
        final list = List.generate(32, (index) => index);
        expect(GetPacker.unpack(GetPacker.pack(list)), equals(list));
      });

      test('encodes list with length 255', () {
        final list = List.generate(255, (index) => index);
        expect(GetPacker.unpack(GetPacker.pack(list)), equals(list));
      });

      test('encodes list with length 256 (0xFFFF)', () {
        final list = List.generate(256, (index) => index);
        expect(GetPacker.unpack(GetPacker.pack(list)), equals(list));
      });

      test('encodes list with length 65535', () {
        final list = List.generate(65535, (index) => index);
        expect(GetPacker.unpack(GetPacker.pack(list)), equals(list));
      });

      test('encodes list with length 65536 (0xFFFFFFFF)', () {
        final list = List.generate(65536, (index) => index);
        expect(GetPacker.unpack(GetPacker.pack(list)), equals(list));
      });

      test('throws BigDataException when iterable exceeds maxArrayLength cap',
          () {
        final largeIterable = LargeIterable();
        const cfg = GetPackerConfig(maxArrayLength: 16);
        expect(
          () => GetPacker.pack(largeIterable, config: cfg),
          throwsA(isA<GetPackerLimitExceededException>()),
        );
      });
    });

    group('Maps', () {
      test('encodes empty map', () {
        final map = <String, dynamic>{};
        expect(GetPacker.unpack(GetPacker.pack(map)), equals(map));
      });

      test('encodes short map (length <= 31)', () {
        final map = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5};
        expect(GetPacker.unpack(GetPacker.pack(map)), equals(map));
      });

      test('encodes map with length 31', () {
        final map = Map.fromEntries(
          List.generate(31, (index) => MapEntry('key$index', index)),
        );
        expect(GetPacker.unpack(GetPacker.pack(map)), equals(map));
      });

      test('encodes map with length 32 (0xFF)', () {
        final map = Map.fromEntries(
          List.generate(32, (index) => MapEntry('key$index', index)),
        );
        expect(GetPacker.unpack(GetPacker.pack(map)), equals(map));
      });

      test('encodes map with length 255', () {
        final map = Map.fromEntries(
          List.generate(255, (index) => MapEntry('key$index', index)),
        );
        expect(GetPacker.unpack(GetPacker.pack(map)), equals(map));
      });

      test('encodes map with length 256 (0xFFFF)', () {
        final map = Map.fromEntries(
          List.generate(256, (index) => MapEntry('key$index', index)),
        );
        expect(GetPacker.unpack(GetPacker.pack(map)), equals(map));
      });

      test('encodes map with length 65535', () {
        final map = Map.fromEntries(
          List.generate(65535, (index) => MapEntry('key$index', index)),
        );
        expect(GetPacker.unpack(GetPacker.pack(map)), equals(map));
      });

      test('encodes map with length 65536 (0xFFFFFFFF)', () {
        final map = Map.fromEntries(
          List.generate(65536, (index) => MapEntry('key$index', index)),
        );
        expect(GetPacker.unpack(GetPacker.pack(map)), equals(map));
      });

      test('throws BigDataException when map exceeds maxMapLength cap', () {
        const cfg = GetPackerConfig(maxMapLength: 16);
        expect(
          () => GetPacker.pack(LargeMap(), config: cfg),
          throwsA(isA<GetPackerLimitExceededException>()),
        );
      });

      test('pack and unpack complex Map', () {
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
    });

    group('BigInt', () {
      test('encodes empty BigInt', () {
        final bigInt = BigInt.zero;
        expect(GetPacker.unpack(GetPacker.pack(bigInt)), equals(bigInt));
      });

      test('encodes BigInt with value 1', () {
        final bigInt = BigInt.one;
        expect(GetPacker.unpack(GetPacker.pack(bigInt)), equals(bigInt));
      });

      test('encodes BigInt with value -1', () {
        final bigInt = BigInt.from(-1);
        expect(GetPacker.unpack(GetPacker.pack(bigInt)), equals(bigInt));
      });

      test('encodes BigInt with value 1000000', () {
        final bigInt = BigInt.from(1000000);
        expect(GetPacker.unpack(GetPacker.pack(bigInt)), equals(bigInt));
      });

      test('encodes BigInt with value -1000000', () {
        final bigInt = BigInt.from(-1000000);
        expect(GetPacker.unpack(GetPacker.pack(bigInt)), equals(bigInt));
      });

      test('encodes small positive BigInt', () {
        final value = BigInt.from(12345);
        final encoded = GetPacker.pack(value);
        expect(GetPacker.unpack(encoded), equals(value));
      });

      test('encodes small negative BigInt', () {
        final value = BigInt.from(-12345);
        final encoded = GetPacker.pack(value);
        expect(GetPacker.unpack(encoded), equals(value));
      });

      test('encodes large positive BigInt', () {
        final value = BigInt.parse('123456789012345678901234567890');
        final encoded = GetPacker.pack(value);
        expect(GetPacker.unpack(encoded), equals(value));
      });

      test('encodes large negative BigInt', () {
        final value = BigInt.parse('-123456789012345678901234567890');
        final encoded = GetPacker.pack(value);
        expect(GetPacker.unpack(encoded), equals(value));
      });

      test('encodes BigInt with length (1e+30)', () {
        final value = BigInt.from(1e+30); // 1000000000000000019884624838656

        final encoded = GetPacker.pack(value);
        expect(GetPacker.unpack(encoded), equals(value));
      });

      test('encodes BigInt with length => 0xFF (255)', () {
        final v = BigInt.from(1e+306);
        final value = v * v; // 256
        final encoded = GetPacker.pack(value);
        expect(GetPacker.unpack(encoded), equals(value));
      });

      test('encodes BigInt with length => 0xFFFF (65535)', () {
        final v = BigInt.from(1e+308);
        final value = v.pow(513); //65611

        expect(() => GetPacker.pack(value),
            throwsA(isA<GetPackerLimitExceededException>()));
      });
    });

    group('Datetime', () {
      test('encodes DateTime', () {
        final now = DateTime.now();
        final unpacked = GetPacker.unpack(GetPacker.pack(now));
        expect(unpacked, equals(now));
      });

      test('encodes DateTime with milliseconds', () {
        final now = DateTime.now().add(const Duration(milliseconds: 123));
        final unpacked = GetPacker.unpack(GetPacker.pack(now));
        expect(unpacked, equals(now));
      });

      test('encodes DateTime with microseconds', () {
        final now = DateTime.now().add(const Duration(microseconds: 123456));
        final unpacked = GetPacker.unpack(GetPacker.pack(now));
        expect(unpacked, equals(now));
      });

      test('encodes DateTime with negative milliseconds', () {
        final now = DateTime.now().subtract(const Duration(milliseconds: 123));
        final unpacked = GetPacker.unpack(GetPacker.pack(now));
        expect(unpacked, equals(now));
      });

      test('encodes DateTime with negative microseconds', () {
        final now =
            DateTime.now().subtract(const Duration(microseconds: 123456));
        final unpacked = GetPacker.unpack(GetPacker.pack(now));
        expect(unpacked, equals(now));
      });

      test('encodes DateTime with negative milliseconds and microseconds', () {
        final now = DateTime.now()
            .subtract(const Duration(milliseconds: 123, microseconds: 456789));
        final unpacked = GetPacker.unpack(GetPacker.pack(now));
        expect(unpacked, equals(now));
      });
    });

    test('pack and unpack Set', () {
      final set = {1, 'two', 3.0};
      final unpacked = GetPacker.unpack(GetPacker.pack(set));
      expect(unpacked, equals(set.toList()));
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
        // 'longString': 'This is a much longer string that contains multiple sentences. '
        //     'It can be used to test how the system handles larger text inputs. '
        //     'The string can contain various characters and punctuation marks!',
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
  });

  test('pack and unpack Model', () {
    final model = ModelSample(name: 'John Doe', age: 42);
    final packed = GetPacker.pack(model);
    final directPacket = model.pack();
    expect(packed, equals(directPacket));
    final unpacked = GetPacker.unpack(packed);
    final fetchedModel = ModelSample.fromJson(unpacked);
    expect(model.name, equals(fetchedModel.name));
    expect(model.age, equals(fetchedModel.age));
    expect(model, equals(fetchedModel)); // Due to equality operator
  });

  test('typed unpack with fromJson returns model', () {
    final model = ModelSample(name: 'John Doe', age: 42);
    final packed = GetPacker.pack(model);

    final unpacked = GetPacker.unpack<ModelSample>(
      packed,
      fromJson: ModelSample.fromJson,
    );

    expect(unpacked, equals(model));
  });

  test('typed unpack works with bytes produced by model.pack()', () {
    final model = ModelSample(name: 'John Doe', age: 42);
    final packed = model.pack();

    final unpacked = GetPacker.unpack(
      packed,
      fromJson: ModelSample.fromJson,
    );

    expect(unpacked, equals(model));
  });

  test('stateful decode accepts fromJson', () {
    final model = ModelSample(name: 'John Doe', age: 42);
    final packer = GetPacker();
    final packed = packer.encode(model);

    final unpacked = packer.decode<ModelSample>(
      packed,
      fromJson: ModelSample.fromJson,
    );

    expect(unpacked, equals(model));
  });

  test('typed unpack with fromJson throws when payload is not a map', () {
    final packed = GetPacker.pack(42);

    expect(
      () => GetPacker.unpack<ModelSample>(
        packed,
        fromJson: ModelSample.fromJson,
      ),
      throwsA(isA<GetPackerTypeMismatchException>()),
    );
  });

  test('try unpack with a unexpect entry', () {
    final value = Uint8List.fromList([]);
    expect(() => GetPacker.unpack(value),
        throwsA(isA<GetPackerTruncatedInputException>()));
  });

  test('pack and unpack Model with non-packed class', () {
    final model = ModelNotPacked(name: 'John Doe', age: 42);

    expect(() => GetPacker.pack(model),
        throwsA(isA<GetPackerUnsupportedTypeException>()));
  });

  test('try unpack unexpect binary', () {
    final data = Uint8List.fromList([0xCC]);
    final data2 = Uint8List.fromList([0xCD]);
    final data3 = Uint8List.fromList([0xCE]);
    final data4 = Uint8List.fromList([0xCF]);
    // final data5 = Uint8List.fromList([0xCA]);
    final list = [data, data2, data3, data4];
    for (final item in list) {
      expect(() => GetPacker.unpack(item),
          throwsA(isA<GetPackerTruncatedInputException>()));
    }
  });

  test('stringifies decode error', () {
    final data = Uint8List.fromList([0xD9]);

    try {
      GetPacker.unpack(data);
      // ignore: dead_code
      fail('Exception not thrown');
    } catch (e) {
      expect(e.toString(), contains('Unexpected end of input'));
    }
  });

  test('stringifies limit errors with code and details', () {
    final e = GetPackerLimitExceededException(
      limitName: 'maxStringUtf8Bytes',
      limit: 3,
      actual: 4,
      unit: 'bytes',
      valueType: 'String',
      message: 'String exceeds maxStringUtf8Bytes cap.',
    );
    final text = e.toString();
    expect(text, contains('encode.limit_exceeded'));
    expect(text, contains('maxStringUtf8Bytes'));
  });

  group('GetPacker Decode Error Cases', () {
    test('throws UnexpectedError when input ends unexpectedly in _readInt', () {
      final bytes = Uint8List.fromList(
          [0xD0]); // D0 expects 1 byte for int8, but none provided
      expect(() => GetPacker.unpack(bytes),
          throwsA(isA<GetPackerTruncatedInputException>()));
    });

    test('throws UnexpectedError when input ends unexpectedly in _readString',
        () {
      final bytes = Uint8List.fromList([
        0xD9,
        0x02
      ]); // D9 expects 2 bytes for string length but none provided
      expect(() => GetPacker.unpack(bytes),
          throwsA(isA<GetPackerTruncatedInputException>()));
    });

    test('throws UnexpectedError when input ends unexpectedly in _readBinary',
        () {
      final bytes = Uint8List.fromList([
        0xC4,
        0x02
      ]); // C4 expects 2 bytes for binary length but none provided
      expect(() => GetPacker.unpack(bytes),
          throwsA(isA<GetPackerTruncatedInputException>()));
    });

    test('throws UnexpectedError when input ends unexpectedly in _readExt', () {
      final bytes2 = Uint8List.fromList([
        0xC7,
        0xFF,
      ]);
      expect(() => GetPacker.unpack(bytes2),
          throwsA(isA<GetPackerTruncatedInputException>()));
    });

    test('throws UnexpectedError when input ends unexpectedly in _readDouble',
        () {
      final bytes = Uint8List.fromList(
          [0xCB]); // CB expects 8 bytes for float64, but none provided
      expect(() => GetPacker.unpack(bytes),
          throwsA(isA<GetPackerTruncatedInputException>()));
    });

    test('throws UnsupportedError for unknown prefix', () {
      // 0xC1 is reserved/invalid in MessagePack
      expect(() => GetPacker.unpack(Uint8List.fromList([0xC1])),
          throwsA(isA<GetPackerUnknownPrefixException>()));

      // 0xD4 is FixExt1, valid prefix, but truncated payload => decode error
      expect(() => GetPacker.unpack(Uint8List.fromList([0xD4])),
          throwsA(isA<GetPackerTruncatedInputException>()));
    });

    // test('throws UnexpectedError when input ends unexpectedly in _readFloat',
    //     () {
    //   final bytes = Uint8List.fromList(
    //       [0xCA]); // CA expects 4 bytes for float32, but none provided
    //   expect(() => GetPacker.unpack(bytes), throwsA(isA<UnexpectedError>()));
    // });

    test('throws StateError for invalid BigInt ext length', () {
      // Simulate invalid ext data for BigInt (type 0x01) with a length < 1
      final data =
          Uint8List.fromList([0xC7, 0x00, 0x01]); // ext 8 with 0 length
        expect(() => GetPacker.unpack(data),
          throwsA(isA<GetPackerInvalidExtPayloadException>()));
    });

    test('throws UnsupportedError for invalid DateTime ext length', () {
      // Simulate ext data for DateTime (type 0xFF) with invalid length
      final data = Uint8List.fromList(
          [0xC7, 0x05, 0xFF, 0, 0, 0, 0]); // ext 8 with invalid length (5)
      expect(() => GetPacker.unpack(data),
          throwsA(isA<GetPackerTruncatedInputException>()));
    });
  });

  // test('unpack float32', () {
  //   final lists = [0xCA, 0x42, 0x28, 0x00, 0x00];
  //   final bytes = Uint8List.fromList(lists);
  //   final data = GetPacker.unpack(bytes);
  //   expect(data, 42.0);
  // });

  test('handles unknown ext type with custom data', () {
    // Simulate an unknown ext type (not 0x01 or 0xFF)
    final data = Uint8List.fromList([
      0xC7,
      0x02,
      0x99,
      0xAA,
      0xBB
    ]); // ext 8 with type 0x99 and 2 bytes of data
    final unpacked = GetPacker.unpack(data);
    expect(unpacked, isA<ExtValue>());
    final ext = unpacked as ExtValue;
    expect(ext.type, equals(0x99));
    expect(ext.data, equals(Uint8List.fromList([0xAA, 0xBB])));
  });

  test('_decode handles FixArray (0x90 to 0x9F)', () {
    for (int i = 0; i <= 15; i++) {
      final prefix = 0x90 + i;
      final list = List.generate(i, (index) => index);
      final bytes = Uint8List.fromList([prefix, ...list.map((e) => e)]);
      final result = GetPacker.unpack(bytes);
      expect(result, equals(list), reason: 'Failed for array of length $i');
    }
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

class LargeMap extends MapBase<int, int> {
  @override
  int? operator [](Object? key) {
    // Just return the key as the value for simplicity
    if (key is int && key >= 0 && key < 0x100000000) {
      return key;
    }
    return null;
  }

  @override
  void operator []=(int key, int value) {
    // No-op, we don't actually store anything
  }

  @override
  void clear() {
    // No-op
  }

  @override
  Iterable<int> get keys => Iterable<int>.generate(0x100000000);

  @override
  int get length => 0x100000001; // Simulate a size larger than 0xFFFFFFFF

  @override
  int? remove(Object? key) {
    // No-op
    return null;
  }
}

class ModelSample with PackedModel {
  final String name;
  final int age;
  ModelSample({
    required this.name,
    required this.age,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'age': age,
    };
  }

  factory ModelSample.fromJson(Map<String, dynamic> map) {
    return ModelSample(
      name: map['name'] ?? '',
      age: map['age']?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ModelSample && other.name == name && other.age == age;
  }

  @override
  int get hashCode => name.hashCode ^ age.hashCode;
}

class ModelNotPacked {
  final String name;
  final int age;
  ModelNotPacked({
    required this.name,
    required this.age,
  });
}
