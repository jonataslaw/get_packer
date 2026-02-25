import 'dart:typed_data';

import 'package:get_packer/get_packer.dart';
import 'package:get_packer/src/internal/int_coercion.dart';
import 'package:get_packer/src/internal/numeric_runtime.dart';
import 'package:get_packer/src/internal/packed_bool_list.dart';
import 'package:get_packer/src/internal/web_wide_int_encoding.dart';
import 'package:test/test.dart';

void main() {
  group('API and internals', () {
    test('stateful GetPacker encode/decode works', () {
      final packer = GetPacker();
      final encoded = packer.encode({'k': 'v', 'n': 42});
      final decoded = packer.decode<Map<dynamic, dynamic>>(encoded);
      expect(decoded, equals({'k': 'v', 'n': 42}));
    });

    test('GetPackerEncoder reset paths keep encoder reusable', () {
      final encoder = GetPackerEncoder(trimOnFinish: false);
      final first = encoder.pack(1);
      expect(GetPacker.unpack<int>(first), equals(1));

      encoder.reset();
      final second = encoder.pack(2);
      expect(GetPacker.unpack<int>(second), equals(2));

      encoder.reset(config: const GetPackerConfig(preferFloat32: false));
      final third = encoder.pack(3.25);
      expect(GetPacker.unpack<double>(third), equals(3.25));
    });

    test('GetPackerDecoder offset/isDone reflect decode progress', () {
      final decoder = GetPackerDecoder();
      decoder.reset(Uint8List.fromList([0x01, 0x02]));

      expect(decoder.offset, equals(0));
      expect(decoder.isDone, isFalse);

      expect(decoder.unpack<int>(), equals(1));
      expect(decoder.offset, equals(1));
      expect(decoder.isDone, isFalse);

      decoder.skipValue();
      expect(decoder.offset, equals(2));
      expect(decoder.isDone, isTrue);
    });

    test('BoolList supports packing, mutation and view recreation', () {
      final list = BoolList(10);
      list[0] = true;
      list[3] = true;
      list[9] = true;

      expect(list[0], isTrue);
      expect(list[1], isFalse);
      expect(list[3], isTrue);
      expect(list[9], isTrue);
      expect(list.asBytesView().length, equals(2));
      expect(() => list.length = 11, throwsUnsupportedError);

      final fromList = BoolList.fromList(
        [true, false, true, false, true, false, true, false, true],
      );
      final packed = fromList.asBytesView();
      final unpacked = BoolList.fromPacked(packed, fromList.length);
      expect(unpacked, orderedEquals(fromList));

      expect(
        () => BoolList.fromPacked(Uint8List(0), 1),
        throwsArgumentError,
      );
    });

    test('numeric runtime constants and host are initialized', () {
      expect(kMaxSafeJsInt, equals(9007199254740991));
      expect(kMinSafeJsInt, equals(-9007199254740991));
      expect(kMinInt64Big < BigInt.zero, isTrue);
      expect(kMaxInt64Big > BigInt.zero, isTrue);
      expect(kMaxUint64Big > kMaxInt64Big, isTrue);
      expect(kMask32, equals((BigInt.one << 32) - BigInt.one));
      expect(kMask8, equals(BigInt.from(0xFF)));
      expect(kMinSafeJsBig, equals(BigInt.from(kMinSafeJsInt)));
      expect(kMaxSafeJsBig, equals(BigInt.from(kMaxSafeJsInt)));
      expect(kIsWeb, isFalse);
      expect(host == Endian.little || host == Endian.big, isTrue);
    });

    test('ExtValue toString contains type and byte length', () {
      final ext = ExtValue(0x99, Uint8List.fromList([0xAA, 0xBB, 0xCC]));
      final text = ext.toString();
      expect(text, contains('0x99'));
      expect(text, contains('3'));
    });

    test('GetPackerException toString includes code and context', () {
      final e = GetPackerTruncatedInputException(
        neededBytes: 1,
        offset: 10,
        inputLength: 10,
        context: 'value prefix',
      );
      final text = e.toString();
      expect(text, contains('decode.truncated_input'));
      expect(text, contains('offset=10'));
      expect(text, contains('Unexpected end of input'));
    });
  });

  group('config and ext paths', () {
    test('allowMalformedUtf8 controls decoder behavior', () {
      final malformed = Uint8List.fromList([0xD9, 0x01, 0xFF]);

      expect(
        () => GetPacker.unpack<String>(malformed),
        throwsA(isA<FormatException>()),
      );

      final relaxed = GetPacker.unpack<String>(
        malformed,
        config: const GetPackerConfig(allowMalformedUtf8: true),
      );
      expect(relaxed, isNotEmpty);
    });

    test('deterministicMaps gives stable bytes across insertion order', () {
      final mapA = {'b': 2, 'a': 1};
      final mapB = {'a': 1, 'b': 2};

      final deterministic = const GetPackerConfig(deterministicMaps: true);
      final packedA = GetPacker.pack(mapA, config: deterministic);
      final packedB = GetPacker.pack(mapB, config: deterministic);
      expect(packedA, equals(packedB));

      final nonDeterministic = const GetPackerConfig(deterministicMaps: false);
      final packedANonDet = GetPacker.pack(mapA, config: nonDeterministic);
      final packedBNonDet = GetPacker.pack(mapB, config: nonDeterministic);
      expect(packedANonDet, isNot(equals(packedBNonDet)));
    });

    test('maxDepth limits both encode and decode nesting', () {
      final nested = [
        [
          ['x']
        ]
      ];

      expect(
        () => GetPacker.pack(
          nested,
          config: const GetPackerConfig(maxDepth: 1),
        ),
        throwsA(isA<GetPackerMaxDepthExceededException>()),
      );

      final packed = GetPacker.pack(nested);
      expect(
        () => GetPacker.unpack<dynamic>(
          packed,
          config: const GetPackerConfig(maxDepth: 1),
        ),
        throwsA(isA<GetPackerMaxDepthExceededException>()),
      );
    });

    test('intInteropMode requireBigIntForWide rejects wide int', () {
      const cfg = GetPackerConfig(
        intInteropMode: IntInteropMode.requireBigIntForWide,
      );
      expect(() => GetPacker.pack(1 << 60, config: cfg), throwsArgumentError);
    });

    test('wide integers roundtrip via BigInt as configured', () {
      final huge = 1 << 60;

      const promote = GetPackerConfig(
        intInteropMode: IntInteropMode.promoteWideToBigInt,
      );
      final promoted = GetPacker.unpack<dynamic>(
        GetPacker.pack(huge, config: promote),
        config: promote,
      );
      expect(promoted, isA<BigInt>());
      expect(promoted, equals(BigInt.from(huge)));

      const off = GetPackerConfig(intInteropMode: IntInteropMode.off);
      final offDecoded = GetPacker.unpack<dynamic>(
        GetPacker.pack(huge, config: off),
        config: off,
      );
      expect(offDecoded, equals(huge));
    });

    test('URI and Duration ext values roundtrip', () {
      final input = {
        'uri': Uri.parse('https://example.com/path?q=1#frag'),
        'duration': const Duration(days: 1, seconds: 2, microseconds: 3),
      };
      final decoded = GetPacker.unpack<Map<dynamic, dynamic>>(
        GetPacker.pack(input),
      );
      expect(decoded['uri'], equals(input['uri']));
      expect(decoded['duration'], equals(input['duration']));
    });

    test('size caps: string/binary/array/map/set/uri/ext payload guards throw',
        () {
      expect(
        () => GetPacker.pack('abcd',
            config: const GetPackerConfig(maxStringUtf8Bytes: 3)),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      expect(
        () => GetPacker.pack('🌍',
            config: const GetPackerConfig(maxStringUtf8Bytes: 3)),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      expect(
        () => GetPacker.pack(Uint8List(4),
            config: const GetPackerConfig(maxBinaryBytes: 3)),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      // List<int> byte path uses maxBinaryBytes.
      expect(
        () => GetPacker.pack(
          <int>[0, 1, 2, 3],
          config: const GetPackerConfig(maxBinaryBytes: 3),
        ),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      // Force List<int> to use array encoding so maxArrayLength applies there.
      expect(
        () => GetPacker.pack(
          List<int>.generate(17, (i) => 256 + i),
          config: const GetPackerConfig(
            maxArrayLength: 16,
            numericListPromotionMinLength: 100,
          ),
        ),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      expect(
        () => GetPacker.pack(
          <dynamic>[1, 2],
          config: const GetPackerConfig(maxArrayLength: 1),
        ),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      expect(
        () => GetPacker.pack(
          <String, int>{'a': 1, 'b': 2},
          config: const GetPackerConfig(maxMapLength: 1),
        ),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      expect(
        () => GetPacker.pack(
          <int>{1, 2},
          config: const GetPackerConfig(maxArrayLength: 1),
        ),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      expect(
        () => GetPacker.pack(
          Uri.parse('https://example.com'),
          config: const GetPackerConfig(maxUriUtf8Bytes: 1),
        ),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      expect(
        () => GetPacker.pack(BigInt.one,
            config: const GetPackerConfig(maxExtPayloadBytes: 1)),
        throwsA(isA<GetPackerLimitExceededException>()),
      );

      expect(
        () => GetPacker.pack(BigInt.one << 80,
            config: const GetPackerConfig(maxExtPayloadBytes: 1)),
        throwsA(isA<GetPackerLimitExceededException>()),
      );
    });
  });

  group('encoder internals', () {
    test('BigInt ext header covers ext8/ext16/ext32', () {
      final ext8 = GetPacker.pack(BigInt.one);
      expect(GetPacker.unpack<BigInt>(ext8), equals(BigInt.one));

      final big16 = BigInt.one << (8 * 300);
      final ext16 = GetPacker.pack(
        big16,
        config: const GetPackerConfig(maxBigIntMagnitudeBytes: 1024),
      );
      expect(GetPacker.unpack<BigInt>(ext16), equals(big16));

      final big32 = BigInt.one << (8 * 65535);
      final ext32 = GetPacker.pack(
        big32,
        config: const GetPackerConfig(maxBigIntMagnitudeBytes: 70000),
      );
      expect(
        GetPacker.unpack<BigInt>(
          ext32,
          config: const GetPackerConfig(maxBigIntMagnitudeBytes: 70000),
        ),
        equals(big32),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('decoder web-only helpers', () {
    test('_uint64FromParts returns BigInt on web for unsafe values', () {
      // 0x0020_0000 << 32 == 2^53, i.e. just past JS safe integer range.
      const hi = 0x00200000;
      const lo = 1;

      final webValue = uint64FromParts(
        hi,
        lo,
        isWeb: true,
        mode: IntInteropMode.off,
      );
      expect(webValue, isA<BigInt>());

      final vmValue = uint64FromParts(
        hi,
        lo,
        isWeb: false,
        mode: IntInteropMode.off,
      );
      expect(vmValue, isA<int>());
    });

    test('_uint64FromParts covers high-half > 0x7FFFFFFF on VM', () {
      const hi = 0x80000000; // > 0x7FFFFFFF → value = 2^63 (exceeds int64)
      const lo = 0;

      final result = uint64FromParts(
        hi,
        lo,
        isWeb: false,
        mode: IntInteropMode.off,
      );
      // 2^63 exceeds signed int64, so BigInt is returned
      expect(result, isA<BigInt>());
      expect(result, equals(BigInt.from(hi) << 32));
    });

    test('_int64FromParts returns BigInt on web for unsafe negative values',
        () {
      const hiU = 0x80000000; // -2^63
      const lo = 0;

      final webValue = int64FromParts(
        hiU,
        lo,
        isWeb: true,
        mode: IntInteropMode.off,
      );
      expect(webValue, isA<BigInt>());

      final vmValue = int64FromParts(
        hiU,
        lo,
        isWeb: false,
        mode: IntInteropMode.off,
      );
      expect(vmValue, isA<int>());
    });

    test('_coerceWideInt follows web/VM coercion rules', () {
      final safeJs = BigInt.from(kMaxSafeJsInt);
      final unsafeJs = BigInt.from(kMaxSafeJsInt) + BigInt.one;

      final webSafe = coerceWideInt(
        safeJs,
        isWeb: true,
        mode: IntInteropMode.off,
      );
      expect(webSafe, isA<int>());

      final webUnsafe = coerceWideInt(
        unsafeJs,
        isWeb: true,
        mode: IntInteropMode.off,
      );
      expect(webUnsafe, isA<BigInt>());

      final vmSafeInt64 = coerceWideInt(
        kMaxInt64Big,
        isWeb: false,
        mode: IntInteropMode.off,
      );
      expect(vmSafeInt64, isA<int>());

      final vmWide = coerceWideInt(
        kMaxInt64Big + BigInt.one,
        isWeb: false,
        mode: IntInteropMode.off,
      );
      expect(vmWide, isA<BigInt>());
    });
  });

  group('web wide-int helpers', () {
    test('tryEncodeWebWideInt requires web and outside-native flags', () {
      int called = 0;

      final noWeb = tryEncodeWebWideInt(
        isWeb: false,
        outsideNative64BitRange: true,
        mode: IntInteropMode.off,
        value: 0,
        encode: (_, __) => called++,
      );
      expect(noWeb, isFalse);
      expect(called, equals(0));

      final inRange = tryEncodeWebWideInt(
        isWeb: true,
        outsideNative64BitRange: false,
        mode: IntInteropMode.off,
        value: 0,
        encode: (_, __) => called++,
      );
      expect(inRange, isFalse);
      expect(called, equals(0));
    });

    test('tryEncodeWebWideInt chooses ext type by interop mode', () {
      int? extType;

      final promote = tryEncodeWebWideInt(
        isWeb: true,
        outsideNative64BitRange: true,
        mode: IntInteropMode.promoteWideToBigInt,
        value: 123,
        encode: (ext, _) => extType = ext,
      );
      expect(promote, isTrue);
      expect(extType, equals(ExtType.bigInt));

      final off = tryEncodeWebWideInt(
        isWeb: true,
        outsideNative64BitRange: true,
        mode: IntInteropMode.off,
        value: 123,
        encode: (ext, _) => extType = ext,
      );
      expect(off, isTrue);
      expect(extType, equals(ExtType.wideInt));
    });

    test('tryEncodeWebWideIntListAsArray invokes callback only when needed',
        () {
      int called = 0;

      final noWeb = tryEncodeWebWideIntListAsArray(
        isWeb: false,
        min: 0,
        bigMin: BigInt.zero,
        bigMax: BigInt.from(1),
        list: const <int>[1],
        encodeAsArray: (_) => called++,
      );
      expect(noWeb, isFalse);
      expect(called, equals(0));

      final inRange = tryEncodeWebWideIntListAsArray(
        isWeb: true,
        min: 0,
        bigMin: BigInt.zero,
        bigMax: BigInt.from(1),
        list: const <int>[1],
        encodeAsArray: (_) => called++,
      );
      expect(inRange, isFalse);
      expect(called, equals(0));

      final fallback = tryEncodeWebWideIntListAsArray(
        isWeb: true,
        min: -1,
        bigMin: BigInt.from(-1),
        bigMax: BigInt.one << 90,
        list: const <int>[1],
        encodeAsArray: (_) => called++,
      );
      expect(fallback, isTrue);
      expect(called, equals(1));
    });
  });
  test('typed lists and promoted lists decode to typed values', () {
    final typedValues = <dynamic>[
      Int8List.fromList([-1, 0, 1, 2]),
      Uint16List.fromList([1, 2, 65535]),
      Int16List.fromList([-32768, 0, 32767]),
      Uint32List.fromList([0, 42, 0xFFFFFFFF]),
      Int32List.fromList([-2147483648, 0, 2147483647]),
      Uint64List.fromList([0, 42, 1 << 40]),
      Int64List.fromList([-(1 << 40), 0, 1 << 40]),
      Float32List.fromList([1.5, 2.5, 3.5]),
      Float64List.fromList([0.1, 0.2, 0.3]),
    ];

    for (final value in typedValues) {
      final decoded = GetPacker.unpack<dynamic>(GetPacker.pack(value));
      expect(
        (value is Int8List && decoded is Int8List) ||
            (value is Uint16List && decoded is Uint16List) ||
            (value is Int16List && decoded is Int16List) ||
            (value is Uint32List && decoded is Uint32List) ||
            (value is Int32List && decoded is Int32List) ||
            (value is Uint64List && decoded is Uint64List) ||
            (value is Int64List && decoded is Int64List) ||
            (value is Float32List && decoded is Float32List) ||
            (value is Float64List && decoded is Float64List),
        isTrue,
      );
      expect(decoded, orderedEquals(value));
    }

    final promotedUint8 = GetPacker.unpack<dynamic>(
        GetPacker.pack(List<int>.generate(12, (i) => i)));
    expect(promotedUint8, isA<Uint8List>());

    final promotedInt8 = GetPacker.unpack<dynamic>(
      GetPacker.pack(List<int>.generate(12, (i) => i - 6)),
    );
    expect(promotedInt8, isA<Int8List>());

    final promotedUint16 = GetPacker.unpack<dynamic>(
      GetPacker.pack(List<int>.filled(20, 1000)),
    );
    expect(promotedUint16, isA<Uint16List>());

    final promotedInt16 = GetPacker.unpack<dynamic>(
      GetPacker.pack(List<int>.filled(20, -1000)),
    );
    expect(promotedInt16, isA<Int16List>());

    final promotedInt32 = GetPacker.unpack<dynamic>(
      GetPacker.pack(List<int>.filled(20, -100000)),
    );
    expect(promotedInt32, isA<Int32List>());

    final promotedInt64 = GetPacker.unpack<dynamic>(
      GetPacker.pack(List<int>.filled(20, -(1 << 40))),
    );
    expect(promotedInt64, isA<Int64List>());

    final promotedUint16Ext32 = GetPacker.unpack<dynamic>(
      GetPacker.pack(List<int>.filled(40000, 1000)),
    );
    expect(promotedUint16Ext32, isA<Uint16List>());
    expect((promotedUint16Ext32 as Uint16List).length, equals(40000));

    final promotedFloat32 = GetPacker.unpack<dynamic>(
      GetPacker.pack(List<double>.filled(12, 42.5)),
    );
    expect(promotedFloat32, isA<Float32List>());

    final promotedFloat64 = GetPacker.unpack<dynamic>(
      GetPacker.pack(List<double>.filled(12, 0.1)),
    );
    expect(promotedFloat64, isA<Float64List>());

    final promotedBool = GetPacker.unpack<dynamic>(
      GetPacker.pack(List<bool>.generate(16, (i) => i.isEven)),
    );
    expect(promotedBool, isA<BoolList>());

    final nonPromotedShort = GetPacker.unpack<dynamic>(
      GetPacker.pack([1000, 1001, 1002]),
    );
    expect(nonPromotedShort, isA<List<dynamic>>());
  });

  test('typed list ext8/ext16/ext32 and URI ext8/ext16/ext32 roundtrip', () {
    final ext8Int8 = Int8List.fromList(List<int>.generate(20, (i) => i - 10));
    final ext16U16 = Uint16List.fromList(List<int>.generate(20000, (i) => i));
    final ext32I8 = Int8List(70000)..fillRange(0, 70000, 7);

    expect(GetPacker.unpack(GetPacker.pack(ext8Int8)), orderedEquals(ext8Int8));
    expect(GetPacker.unpack(GetPacker.pack(ext16U16)), orderedEquals(ext16U16));
    expect(GetPacker.unpack(GetPacker.pack(ext32I8)), orderedEquals(ext32I8));

    final uri8 = Uri.parse('https://a.co/x');
    final uri16 = Uri.parse('https://example.com/${'a' * 300}');
    final uri32 = Uri.parse('https://example.com/${'b' * 70000}');

    expect(GetPacker.unpack(GetPacker.pack(uri8)), equals(uri8));
    expect(GetPacker.unpack(GetPacker.pack(uri16)), equals(uri16));
    expect(GetPacker.unpack(GetPacker.pack(uri32)), equals(uri32));
  });

  test('set and bool list ext roundtrip through root API', () {
    final asSet = {1, 2, 3, 4};
    final decodedSet = GetPacker.unpack<dynamic>(GetPacker.pack(asSet));
    expect(decodedSet, equals(asSet));

    final boolList = BoolList.fromList(
      List<bool>.generate(64, (i) => (i % 3) == 0),
    );
    final decodedBoolList = GetPacker.unpack<dynamic>(GetPacker.pack(boolList));
    expect(decodedBoolList, isA<BoolList>());
    expect(decodedBoolList, orderedEquals(boolList));
  });

  group('decoder skip logic', () {
    test('skipValue supports all major prefix categories', () {
      final decoder = GetPackerDecoder();
      final cases = <List<int>>[
        [0x01, 0x02],
        [0xFF, 0x02],
        [0xA1, 0x61, 0x02],
        [0xD9, 0x01, 0x61, 0x02],
        [0xDA, 0x00, 0x01, 0x61, 0x02],
        [0xDB, 0x00, 0x00, 0x00, 0x01, 0x61, 0x02],
        [0x90, 0x02],
        [0x92, 0x01, 0x01, 0x02],
        [0x80, 0x02],
        [0x81, 0xA1, 0x6B, 0x01, 0x02],
        [0xC0, 0x02],
        [0xC2, 0x02],
        [0xC3, 0x02],
        [0xCC, 0xFF, 0x02],
        [0xCD, 0x00, 0x2A, 0x02],
        [0xCE, 0x00, 0x00, 0x00, 0x2A, 0x02],
        [0xCF, 0, 0, 0, 0, 0, 0, 0, 42, 0x02],
        [0xD0, 0xFE, 0x02],
        [0xD1, 0xFF, 0xFE, 0x02],
        [0xD2, 0xFF, 0xFF, 0xFF, 0xFE, 0x02],
        [0xD3, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE, 0x02],
        [0xCA, 0x3F, 0x80, 0x00, 0x00, 0x02],
        [0xCB, 0x3F, 0xF0, 0, 0, 0, 0, 0, 0, 0x02],
        [0xC4, 0x01, 0xAA, 0x02],
        [0xC5, 0x00, 0x01, 0xAA, 0x02],
        [0xC6, 0x00, 0x00, 0x00, 0x01, 0xAA, 0x02],
        [0xDC, 0x00, 0x01, 0x01, 0x02],
        [0xDD, 0x00, 0x00, 0x00, 0x01, 0x01, 0x02],
        [0xDE, 0x00, 0x01, 0xA1, 0x6B, 0x01, 0x02],
        [0xDF, 0x00, 0x00, 0x00, 0x01, 0xA1, 0x6B, 0x01, 0x02],
        [0xD4, 0x01, 0xAA, 0x02],
        [0xD5, 0x01, 0xAA, 0xBB, 0x02],
        [0xD6, 0x01, 0xAA, 0xBB, 0xCC, 0xDD, 0x02],
        [0xD7, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0x02],
        [0xD8, 0x01, ...List<int>.filled(16, 0xAB), 0x02],
        [0xC7, 0x01, 0x01, 0xAA, 0x02],
        [0xC8, 0x00, 0x01, 0x01, 0xAA, 0x02],
        [0xC9, 0x00, 0x00, 0x00, 0x01, 0x01, 0xAA, 0x02],
      ];

      for (final payload in cases) {
        decoder.reset(Uint8List.fromList(payload));
        expect(
          () => decoder.skipValue(),
          returnsNormally,
          reason: 'skip failed for payload: $payload',
        );
      }
    });

    test('skipValue throws for malformed data and unknown prefix', () {
      final decoder = GetPackerDecoder();

      expect(
        () => GetPacker.unpack<dynamic>(Uint8List.fromList([0xD9, 0x02, 0x61])),
        throwsA(isA<GetPackerTruncatedInputException>()),
      );

      decoder.reset(Uint8List.fromList([0xC1]));
      expect(
        () => decoder.skipValue(),
        throwsA(isA<GetPackerUnknownPrefixException>()),
      );

      decoder.reset(Uint8List(0));
      expect(
        () => decoder.skipValue(),
        throwsA(isA<GetPackerTruncatedInputException>()),
      );
    });

    test('unaligned typed payloads use copy fallback branches', () {
      final unalignedUint16 = Uint8List.fromList([
        0xC7,
        0x06,
        ExtType.uint16List,
        0x00,
        0x00,
        0x00,
        0x01,
        0x01,
        0x00,
      ]);
      final u16 = GetPacker.unpack<dynamic>(unalignedUint16);
      expect(u16, isA<Uint16List>());
      expect((u16 as Uint16List).length, equals(1));

      final unalignedFloat32 = Uint8List.fromList([
        0xC7,
        0x08,
        ExtType.float32List,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x80,
        0x3F,
      ]);
      final f32 = GetPacker.unpack<dynamic>(unalignedFloat32);
      expect(f32, isA<Float32List>());
      expect((f32 as Float32List).length, equals(1));

      final unalignedInt32 = Uint8List.fromList([
        0xC7,
        0x09,
        ExtType.int32List,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      final i32 = GetPacker.unpack<dynamic>(unalignedInt32);
      expect(i32, isA<Int32List>());
      expect((i32 as Int32List).length, equals(1));

      final unalignedUint32 = Uint8List.fromList([
        0xC7,
        0x09,
        ExtType.uint32List,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      final u32 = GetPacker.unpack<dynamic>(unalignedUint32);
      expect(u32, isA<Uint32List>());
      expect((u32 as Uint32List).length, equals(1));

      final unalignedInt64 = Uint8List.fromList([
        0xC7,
        0x0D,
        ExtType.int64List,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      final i64 = GetPacker.unpack<dynamic>(unalignedInt64);
      expect(i64, isA<Int64List>());
      expect((i64 as Int64List).length, equals(1));

      final unalignedUint64 = Uint8List.fromList([
        0xC7,
        0x0D,
        ExtType.uint64List,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      final u64 = GetPacker.unpack<dynamic>(unalignedUint64);
      expect(u64, isA<Uint64List>());
      expect((u64 as Uint64List).length, equals(1));

      final unalignedFloat64 = Uint8List.fromList([
        0xC7,
        0x0D,
        ExtType.float64List,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      final f64 = GetPacker.unpack<dynamic>(unalignedFloat64);
      expect(f64, isA<Float64List>());
      expect((f64 as Float64List).length, equals(1));

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0xC7, 0x03, ExtType.float32List, 0, 0, 0]),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([
            0xC7,
            0x14,
            ExtType.float64List,
            0x00,
            0x00,
            0x00,
            0x01,
            ...List<int>.filled(16, 0),
          ]),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );
    });

    test('map string-key prefixes decode through fast path', () {
      final encoded = Uint8List.fromList([
        0x83,
        0xD9,
        0x01,
        0x61,
        0x01,
        0xDA,
        0x00,
        0x01,
        0x62,
        0x02,
        0xDB,
        0x00,
        0x00,
        0x00,
        0x01,
        0x63,
        0x03,
      ]);

      final decoded = GetPacker.unpack<Map<dynamic, dynamic>>(encoded);
      expect(decoded, equals({'a': 1, 'b': 2, 'c': 3}));
    });

    test('decoder handles fixed ext family and int boundary prefixes', () {
      final fixedExtPayloads = <List<int>>[
        [0xD4, 0x55, 0x01],
        [0xD5, 0x55, 0x01, 0x02],
        [0xD6, 0x55, 0x01, 0x02, 0x03, 0x04],
        [0xD7, 0x55, ...List<int>.filled(8, 0xAA)],
        [0xD8, 0x55, ...List<int>.filled(16, 0xBB)],
      ];

      for (final bytes in fixedExtPayloads) {
        final decoded = GetPacker.unpack<dynamic>(Uint8List.fromList(bytes));
        expect(decoded, isA<ExtValue>());
      }

      expect(GetPacker.unpack<int>(Uint8List.fromList([0xD1, 0xFF, 0xFE])), -2);
      expect(
        GetPacker.unpack<int>(
            Uint8List.fromList([0xD2, 0xFF, 0xFF, 0xFF, 0xFE])),
        -2,
      );

      const promote = GetPackerConfig(
        intInteropMode: IntInteropMode.promoteWideToBigInt,
      );
      final uint64Unsafe = Uint8List.fromList([
        0xCF,
        0x00,
        0x20,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      expect(
        GetPacker.unpack<dynamic>(uint64Unsafe, config: promote),
        isA<BigInt>(),
      );

      final int64UnsafeNeg = Uint8List.fromList([
        0xD3,
        0xFF,
        0xE0,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      expect(
        GetPacker.unpack<dynamic>(int64UnsafeNeg, config: promote),
        isA<BigInt>(),
      );
    });

    test('decoder map fallback and typed-list error branches', () {
      final mixedKeyMap = Uint8List.fromList([
        0x82,
        0xA1,
        0x61,
        0x01,
        0x02,
        0x03,
      ]);
      final decoded = GetPacker.unpack<Map<dynamic, dynamic>>(mixedKeyMap);
      expect(decoded['a'], 1);
      expect(decoded[2], 3);

      final dynamicMap = GetPacker.unpack<Map<dynamic, dynamic>>(
        Uint8List.fromList([0x81, 0x01, 0x02]),
      );
      expect(dynamicMap[1], 2);

      final badTypedPayloadShort = Uint8List.fromList([
        0xC7,
        0x03,
        ExtType.uint16List,
        0x00,
        0x00,
        0x00,
      ]);
      expect(
        () => GetPacker.unpack<dynamic>(badTypedPayloadShort),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );

      final badTypedPayloadMismatch = Uint8List.fromList([
        0xC7,
        0x04,
        ExtType.uint16List,
        0x00,
        0x00,
        0x00,
        0x02,
      ]);
      expect(
        () => GetPacker.unpack<dynamic>(badTypedPayloadMismatch),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );
    });

    test('decoder malformed map and ext payload guards', () {
      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0x82, 0xA1, 0x61, 0x01]),
        ),
        throwsA(isA<GetPackerTruncatedInputException>()),
      );

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0xC7, 0x00, ExtType.bigInt]),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0xC7, 0x03, ExtType.bigInt, 0x00, 0x01, 0x00]),
          config: const GetPackerConfig(maxBigIntMagnitudeBytes: 1),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0xC7, 0x00, ExtType.wideInt]),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0xC7, 0x03, ExtType.wideInt, 0x00, 0x01, 0x00]),
          config: const GetPackerConfig(maxBigIntMagnitudeBytes: 1),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0xC7, 0x03, ExtType.boolList, 0x00, 0x00, 0x00]),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([
            0xC7,
            0x05,
            ExtType.boolList,
            0x00,
            0x00,
            0x00,
            0x10,
            0xFF,
          ]),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );
    });

    test('decoder wideInt ext returns int or BigInt per mode and magnitude',
        () {
      final smallWide = Uint8List.fromList([
        0xC7,
        0x02,
        ExtType.wideInt,
        0x00,
        0x2A,
      ]);
      expect(GetPacker.unpack<dynamic>(smallWide), equals(42));
      expect(
        GetPacker.unpack<dynamic>(
          smallWide,
          config: const GetPackerConfig(
            intInteropMode: IntInteropMode.promoteWideToBigInt,
          ),
        ),
        equals(42),
      );

      final huge = BigInt.one << 80;
      final hugeBytes = _bigIntToBytes(huge);
      final hugeWide = Uint8List.fromList([
        0xC8,
        0x00,
        hugeBytes.length + 1,
        ExtType.wideInt,
        0x00,
        ...hugeBytes,
      ]);

      expect(GetPacker.unpack<dynamic>(hugeWide), equals(huge));
      expect(
        GetPacker.unpack<dynamic>(
          hugeWide,
          config: const GetPackerConfig(
            intInteropMode: IntInteropMode.promoteWideToBigInt,
          ),
        ),
        equals(huge),
      );
    });
  });

  group('encoder edge branches', () {
    test('utf8 string branches choose str8/str16/str32', () {
      final s8 = 'é' * 40;
      final s16 = 'é' * 400;
      final s32 = 'é' * 40000;

      expect(GetPacker.unpack(GetPacker.pack(s8)), equals(s8));
      expect(GetPacker.unpack(GetPacker.pack(s16)), equals(s16));
      expect(GetPacker.unpack(GetPacker.pack(s32)), equals(s32));
    });

    test('int list auto path covers empty and wide range promotions', () {
      final emptyDecoded = GetPacker.unpack<dynamic>(GetPacker.pack(<int>[]));
      expect(emptyDecoded, isA<Uint8List>());

      final asUint32 = GetPacker.unpack<dynamic>(
        GetPacker.pack(List<int>.filled(16, 3000000000)),
      );
      expect(asUint32, isA<Uint32List>());

      final asUint64 = GetPacker.unpack<dynamic>(
        GetPacker.pack(List<int>.filled(16, 5000000000)),
      );
      expect(asUint64, isA<Uint64List>());

      final rollbackToInt32 = GetPacker.unpack<dynamic>(
        GetPacker.pack([1, 2, 3, 4, 5, 6, 7, -500000]),
      );
      expect(rollbackToInt32, isA<Int32List>());
    });

    test('bool list chooses ext16 and ext32 payload headers', () {
      final ext16Bools = List<bool>.generate(6000, (i) => i.isEven);
      final ext32Bools = List<bool>.generate(530000, (i) => (i % 3) == 0);

      expect(GetPacker.unpack(GetPacker.pack(ext16Bools)), isA<BoolList>());
      expect(GetPacker.unpack(GetPacker.pack(ext32Bools)), isA<BoolList>());
    });

    test('generic list and iterable branches encode with array16/array32', () {
      final list16 = List<dynamic>.filled(20, null);
      final list32 = List<dynamic>.filled(70000, null);
      expect(GetPacker.unpack(GetPacker.pack(list16)), isA<List<dynamic>>());
      expect(GetPacker.unpack(GetPacker.pack(list32)), isA<List<dynamic>>());

      final iterable = CountingIterable(40);
      final decoded = GetPacker.unpack<List<dynamic>>(GetPacker.pack(iterable));
      expect(decoded.length, 40);
      expect(decoded.first, 0);
      expect(decoded.last, 39);

      final iterableFix = CountingIterable(5);
      final decodedFix =
          GetPacker.unpack<List<dynamic>>(GetPacker.pack(iterableFix));
      expect(decodedFix.length, 5);

      final iterable16 = CountingIterable(1000);
      final decoded16 =
          GetPacker.unpack<List<dynamic>>(GetPacker.pack(iterable16));
      expect(decoded16.length, 1000);

      final iterable32 = CountingIterable(70000);
      final decoded32 =
          GetPacker.unpack<List<dynamic>>(GetPacker.pack(iterable32));
      expect(decoded32.length, 70000);
    });

    test('map dynamic-key branch and BigInt ext16/ext32 branches', () {
      final dynamicKeyMap = {1: 'one', 'two': 2};
      final decodedMap = GetPacker.unpack<Map<dynamic, dynamic>>(
          GetPacker.pack(dynamicKeyMap));
      expect(decodedMap[1], 'one');
      expect(decodedMap['two'], 2);

      final mediumBig = BigInt.one << (8 * 300);
      final hugeBig = BigInt.one << (8 * 70000);
      const relaxedBigCfg = GetPackerConfig(maxBigIntMagnitudeBytes: 100000);
      expect(GetPacker.unpack(GetPacker.pack(mediumBig)), equals(mediumBig));
      final packedHuge = GetPacker.pack(hugeBig, config: relaxedBigCfg);
      expect(
        GetPacker.unpack(packedHuge, config: relaxedBigCfg),
        equals(hugeBig),
      );

      final strictCfg = const GetPackerConfig(maxBigIntMagnitudeBytes: 1);
      expect(
        () => GetPacker.pack(BigInt.from(65536), config: strictCfg),
        throwsA(isA<GetPackerLimitExceededException>()),
      );
    });

    test('encoder int64 and binary branches', () {
      final maxI64 = 9223372036854775807;
      final minI64 = -9223372036854775808;

      expect(GetPacker.unpack<dynamic>(GetPacker.pack(maxI64)), equals(maxI64));
      expect(GetPacker.unpack<dynamic>(GetPacker.pack(minI64)), equals(minI64));

      final bin16 =
          Uint8List.fromList(List<int>.generate(300, (i) => i & 0xFF));
      final bin32 =
          Uint8List.fromList(List<int>.generate(70000, (i) => i & 0xFF));
      expect(GetPacker.unpack(GetPacker.pack(bin16)), orderedEquals(bin16));
      expect(GetPacker.unpack(GetPacker.pack(bin32)), orderedEquals(bin32));
    });

    test('int list rollback branches cover array fallback and signed widths',
        () {
      final fallbackShort =
          GetPacker.unpack<dynamic>(GetPacker.pack([1, 2, 1000]));
      expect(fallbackShort, isA<List<dynamic>>());

      final noPromotionCfg =
          const GetPackerConfig(numericListPromotionMinLength: 100000);
      final array16 = GetPacker.unpack<dynamic>(
        GetPacker.pack(List<int>.filled(20, 7), config: noPromotionCfg),
      );
      expect(array16, isA<List<dynamic>>());

      final array32 = GetPacker.unpack<dynamic>(
        GetPacker.pack(List<int>.filled(70000, 7), config: noPromotionCfg),
      );
      expect(array32, isA<List<dynamic>>());

      final rollbackInt8 = GetPacker.unpack<dynamic>(
        GetPacker.pack([1, 2, 3, 4, 5, 6, 7, -1]),
      );
      expect(rollbackInt8, isA<Int8List>());

      final rollbackInt16 = GetPacker.unpack<dynamic>(
        GetPacker.pack([1, 2, 3, 4, 5, 6, 7, -200]),
      );
      expect(rollbackInt16, isA<Int16List>());

      final rollbackUint32 = GetPacker.unpack<dynamic>(
        GetPacker.pack([1, 2, 3, 4, 5, 6, 7, 3000000000]),
      );
      expect(rollbackUint32, isA<Uint32List>());

      final rollbackUint64 = GetPacker.unpack<dynamic>(
        GetPacker.pack([1, 2, 3, 4, 5, 6, 7, 5000000000]),
      );
      expect(rollbackUint64, isA<Uint64List>());

      final rollbackInt64 = GetPacker.unpack<dynamic>(
        GetPacker.pack([1, 2, 3, 4, 5, 6, 7, -5000000000]),
      );
      expect(rollbackInt64, isA<Int64List>());

      final fallbackHuge = GetPacker.unpack<dynamic>(
        GetPacker.pack([1, 2, 3, 4, 5, 6, 7, BigInt.one << 80]),
      );
      expect(fallbackHuge, isA<List<dynamic>>());
    });

    test('typed list ext16/ext32 header reserve and pad paths', () {
      final nestedTyped16 = [0, Uint16List.fromList(List<int>.filled(130, 1))];
      final decodedTyped16 = GetPacker.unpack<List<dynamic>>(
        GetPacker.pack(nestedTyped16),
      );
      expect(decodedTyped16[1], isA<Uint16List>());

      final nestedTyped32 = [
        0,
        Uint16List.fromList(List<int>.filled(40000, 1))
      ];
      final decodedTyped32 = GetPacker.unpack<List<dynamic>>(
        GetPacker.pack(nestedTyped32),
      );
      expect(decodedTyped32[1], isA<Uint16List>());

      final nestedList16 = [0, List<int>.filled(130, 1000)];
      final decodedList16 = GetPacker.unpack<List<dynamic>>(
        GetPacker.pack(nestedList16),
      );
      expect(decodedList16[1], isA<Uint16List>());

      // pad32 in _typedListHeaderAndReserve: promoted int list needing ext32.
      // The leading 200 makes _offset odd so pad32 != 0.
      final nestedReservePad32 = [200, List<int>.filled(40000, 1000)];
      final decodedReservePad32 = GetPacker.unpack<List<dynamic>>(
        GetPacker.pack(nestedReservePad32),
      );
      expect(decodedReservePad32[1], isA<Uint16List>());
      expect((decodedReservePad32[1] as Uint16List).length, equals(40000));
    });

    test(
        'int list rollback path: requireBigIntForWide and promoteWideToBigInt with wide values',
        () {
      // First elements fit uint8, then element triggers rollback to wide range.
      final wideList = [0, 0, 0, 0, 0, 0, 0, 1 << 60];

      // requireBigIntForWide: rollback path throws ArgumentError.
      expect(
        () => GetPacker.pack(
          wideList,
          config: const GetPackerConfig(
              intInteropMode: IntInteropMode.requireBigIntForWide),
        ),
        throwsA(isA<ArgumentError>()),
      );

      // promoteWideToBigInt: rollback path falls back to array encoding.
      const promoteCfg =
          GetPackerConfig(intInteropMode: IntInteropMode.promoteWideToBigInt);
      final decoded = GetPacker.unpack<List<dynamic>>(
        GetPacker.pack(wideList, config: promoteCfg),
        config: promoteCfg,
      );
      expect(decoded.length, equals(8));
      expect(decoded.last, isA<BigInt>());
    });
  });
}

Uint8List _bigIntToBytes(BigInt value) {
  final mag = value.isNegative ? -value : value;
  if (mag == BigInt.zero) return Uint8List(0);

  final length = (mag.bitLength + 7) >> 3;
  final out = Uint8List(length);
  var current = mag;
  for (int i = length - 1; i >= 0; i--) {
    out[i] = (current & BigInt.from(0xFF)).toInt();
    current = current >> 8;
  }
  return out;
}

class CountingIterable extends Iterable<int> {
  CountingIterable(this.count);
  final int count;

  @override
  Iterator<int> get iterator => _CountingIterator(count);
}

class _CountingIterator implements Iterator<int> {
  _CountingIterator(this.count);
  final int count;
  int _value = -1;

  @override
  int get current => _value;

  @override
  bool moveNext() {
    if (_value + 1 >= count) return false;
    _value++;
    return true;
  }
}
