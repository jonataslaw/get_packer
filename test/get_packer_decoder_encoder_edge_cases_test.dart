import 'dart:typed_data';

import 'package:get_packer/get_packer.dart';
import 'package:get_packer/src/internal/numeric_runtime.dart';
import 'package:test/test.dart';

Uint8List _u64BytesWithPrefix(int hi, int lo) {
  final bd = ByteData(9);
  bd.setUint8(0, 0xCF);
  bd.setUint32(1, hi, Endian.big);
  bd.setUint32(5, lo, Endian.big);
  return bd.buffer.asUint8List();
}

Uint8List _i64BytesWithPrefix(int value) {
  final bd = ByteData(9);
  bd.setUint8(0, 0xD3);
  bd.setInt64(1, value, Endian.big);
  return bd.buffer.asUint8List();
}

Uint8List _unalignedTypedListExt({
  required int extType,
  required int count,
  required int elemSize,
  required void Function(ByteData bd) writeData,
}) {
  final byteLen = count * elemSize;
  final payloadLength = 4 + byteLen;
  final out = Uint8List(2 + 1 + payloadLength);
  out[0] = 0xC7;
  out[1] = payloadLength;
  out[2] = extType;

  final bodyBd = ByteData.view(
    out.buffer,
    out.offsetInBytes + 3,
    payloadLength,
  );
  bodyBd.setUint32(0, count, Endian.big);
  final dataBd = ByteData.view(
    out.buffer,
    out.offsetInBytes + 3 + 4,
    byteLen,
  );
  writeData(dataBd);
  return out;
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

void main() {
  group('Targeted uncovered coverage (decoder)', () {
    test('uint64 smart boundary in requireBigIntForWide', () {
      const cfg = GetPackerConfig(
        intInteropMode: IntInteropMode.requireBigIntForWide,
      );

      // 2^53 - 1 (JS safe)
      final safe = _u64BytesWithPrefix(0x001FFFFF, 0xFFFFFFFF);
      final safeDecoded = GetPacker.unpack<dynamic>(safe, config: cfg);
      expect(safeDecoded, isA<int>());
      expect(safeDecoded, equals(9007199254740991));

      // 2^53 (unsafe => BigInt)
      final unsafe = _u64BytesWithPrefix(0x00200000, 0x00000000);
      final unsafeDecoded = GetPacker.unpack<dynamic>(unsafe, config: cfg);
      expect(unsafeDecoded, isA<BigInt>());
      expect(unsafeDecoded, equals(BigInt.from(9007199254740992)));

      // In IntInteropMode.off on the VM, we still return an int.
      final offDecoded = GetPacker.unpack<dynamic>(unsafe);
      expect(offDecoded, isA<int>());
      expect(offDecoded, equals(9007199254740992));
    });

    test('int64 smart boundary (positive and negative) in requireBigIntForWide',
        () {
      const cfg = GetPackerConfig(
        intInteropMode: IntInteropMode.requireBigIntForWide,
      );

      final posSafe = _i64BytesWithPrefix(9007199254740991); // 2^53 - 1
      final posSafeDecoded = GetPacker.unpack<dynamic>(posSafe, config: cfg);
      expect(posSafeDecoded, isA<int>());
      expect(posSafeDecoded, equals(9007199254740991));

      final posUnsafe = _i64BytesWithPrefix(9007199254740992); // 2^53
      final posUnsafeDecoded =
          GetPacker.unpack<dynamic>(posUnsafe, config: cfg);
      expect(posUnsafeDecoded, isA<BigInt>());
      expect(posUnsafeDecoded, equals(BigInt.from(9007199254740992)));

      final negSafe = _i64BytesWithPrefix(-9007199254740991);
      final negSafeDecoded = GetPacker.unpack<dynamic>(negSafe, config: cfg);
      expect(negSafeDecoded, isA<int>());
      expect(negSafeDecoded, equals(-9007199254740991));

      final negUnsafe = _i64BytesWithPrefix(-9007199254740992);
      final negUnsafeDecoded =
          GetPacker.unpack<dynamic>(negUnsafe, config: cfg);
      expect(negUnsafeDecoded, isA<BigInt>());
      expect(negUnsafeDecoded, equals(BigInt.from(-9007199254740992)));
    });

    test('ext payload length guards for DateTime/Duration/Set', () {
      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0xC7, 0x01, ExtType.dateTime, 0x00]),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0xC7, 0x01, ExtType.duration, 0x00]),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );

      expect(
        () => GetPacker.unpack<dynamic>(
          Uint8List.fromList([0xC7, 0x03, ExtType.set, 0x00, 0x00, 0x00]),
        ),
        throwsA(isA<GetPackerInvalidExtPayloadException>()),
      );
    });

    test('Set ext trailing bytes guard is enforced', () {
      final bytes = Uint8List.fromList([
        0xC7,
        0x05, // payloadLength = 5
        ExtType.set,
        0x00,
        0x00,
        0x00,
        0x00, // count = 0
        0xC0, // extra byte that should trigger trailing-bytes
      ]);

      expect(
        () => GetPacker.unpack<dynamic>(bytes),
        throwsA(isA<GetPackerTrailingBytesException>()),
      );
    });

    test('URI ext uses UTF-8 decoding for non-ASCII', () {
      // Manually craft an URI ext payload that contains non-ASCII UTF-8 bytes.
      // Uri.toString() normally percent-encodes these, so roundtripping via the
      // encoder would stay ASCII and not hit the UTF-8 decode branch.
      const raw = 'https://example.com/é';
      final rawBytes = Uint8List.fromList(raw.codeUnits);
      // Replace the last code unit with UTF-8 for é (0xC3 0xA9).
      final utf8Bytes = Uint8List.fromList([
        ...rawBytes.sublist(0, rawBytes.length - 1),
        0xC3,
        0xA9,
      ]);
      final payloadLen = utf8Bytes.length;
      final bytes = Uint8List.fromList([
        0xC8,
        (payloadLen >> 8) & 0xFF,
        payloadLen & 0xFF,
        ExtType.uri,
        ...utf8Bytes,
      ]);

      final decoded = GetPacker.unpack<dynamic>(bytes);
      expect(decoded, isA<Uri>());
      expect(decoded, equals(Uri.parse(raw)));
    });

    test('wideInt ext: negative and requireBigIntForWide behavior', () {
      const cfg =
          GetPackerConfig(intInteropMode: IntInteropMode.requireBigIntForWide);

      final negSmall = Uint8List.fromList([
        0xC7,
        0x02,
        ExtType.wideInt,
        0x01,
        0x2A,
      ]);
      final negSmallDecoded = GetPacker.unpack<dynamic>(negSmall, config: cfg);
      expect(negSmallDecoded, equals(-42));

      final unsafe = BigInt.from(9007199254740992); // 2^53
      final unsafeBytes = _bigIntToBytes(unsafe);
      final wideUnsafe = Uint8List.fromList([
        0xC7,
        0x01 + unsafeBytes.length,
        ExtType.wideInt,
        0x00,
        ...unsafeBytes,
      ]);
      final decodedUnsafe = GetPacker.unpack<dynamic>(wideUnsafe, config: cfg);
      expect(decodedUnsafe, isA<BigInt>());
      expect(decodedUnsafe, equals(unsafe));
    });

    test('unaligned typed list payloads take copy branches', () {
      final int16 = _unalignedTypedListExt(
        extType: ExtType.int16List,
        count: 2,
        elemSize: 2,
        writeData: (bd) {
          bd.setInt16(0, -1, host);
          bd.setInt16(2, 2, host);
        },
      );
      final int16Decoded = GetPacker.unpack<dynamic>(int16);
      expect(int16Decoded, isA<Int16List>());
      expect(int16Decoded, orderedEquals(Int16List.fromList([-1, 2])));

      final uint32 = _unalignedTypedListExt(
        extType: ExtType.uint32List,
        count: 2,
        elemSize: 4,
        writeData: (bd) {
          bd.setUint32(0, 1, host);
          bd.setUint32(4, 0xFFFFFFFF, host);
        },
      );
      final uint32Decoded = GetPacker.unpack<dynamic>(uint32);
      expect(uint32Decoded, isA<Uint32List>());
      expect(
          uint32Decoded, orderedEquals(Uint32List.fromList([1, 0xFFFFFFFF])));

      final int32 = _unalignedTypedListExt(
        extType: ExtType.int32List,
        count: 2,
        elemSize: 4,
        writeData: (bd) {
          bd.setInt32(0, -1, host);
          bd.setInt32(4, 123, host);
        },
      );
      final int32Decoded = GetPacker.unpack<dynamic>(int32);
      expect(int32Decoded, isA<Int32List>());
      expect(int32Decoded, orderedEquals(Int32List.fromList([-1, 123])));

      final int64 = _unalignedTypedListExt(
        extType: ExtType.int64List,
        count: 2,
        elemSize: 8,
        writeData: (bd) {
          bd.setInt64(0, -1, host);
          bd.setInt64(8, 42, host);
        },
      );
      final int64Decoded = GetPacker.unpack<dynamic>(int64);
      expect(int64Decoded, isA<Int64List>());
      expect(int64Decoded, orderedEquals(Int64List.fromList([-1, 42])));

      final uint64 = _unalignedTypedListExt(
        extType: ExtType.uint64List,
        count: 2,
        elemSize: 8,
        writeData: (bd) {
          bd.setUint64(0, 0, host);
          bd.setUint64(8, 1 << 62, host);
        },
      );
      final uint64Decoded = GetPacker.unpack<dynamic>(uint64);
      expect(uint64Decoded, isA<Uint64List>());
      expect(uint64Decoded, orderedEquals(Uint64List.fromList([0, 1 << 62])));

      final f64 = _unalignedTypedListExt(
        extType: ExtType.float64List,
        count: 2,
        elemSize: 8,
        writeData: (bd) {
          bd.setFloat64(0, 0.5, host);
          bd.setFloat64(8, 1.5, host);
        },
      );
      final f64Decoded = GetPacker.unpack<dynamic>(f64);
      expect(f64Decoded, isA<Float64List>());
      expect(f64Decoded, orderedEquals(Float64List.fromList([0.5, 1.5])));
    });
  });

  group('Targeted uncovered coverage (encoder)', () {
    test('scalar int16 branch encodes -200', () {
      expect(GetPacker.unpack<int>(GetPacker.pack(-200)), equals(-200));
    });

    test('encode Set via ext', () {
      final set = <dynamic>{1, 'two', 3};
      final decoded = GetPacker.unpack<dynamic>(GetPacker.pack(set));
      expect(decoded, isA<Set>());
      expect(decoded, equals(set));
    });

    // Dart VM `int` is fixed-width, so wideInt branches that require
    // `int.bitLength > 64` won't trigger in this runtime.

    test(
        'list<int> fallback array16/array32 headers in _encodeListOfIntsAsArray',
        () {
      const noPromotion =
          GetPackerConfig(numericListPromotionMinLength: 100000);

      final list16 = List<int>.filled(20, 1000);
      final decoded16 = GetPacker.unpack<dynamic>(
        GetPacker.pack(list16, config: noPromotion),
        config: noPromotion,
      );
      expect(decoded16, isA<List<dynamic>>());
      expect(decoded16, equals(list16));

      final list32 = List<int>.filled(70000, 1000);
      final decoded32 = GetPacker.unpack<dynamic>(
        GetPacker.pack(list32, config: noPromotion),
        config: noPromotion,
      );
      expect(decoded32, isA<List<dynamic>>());
      expect(decoded32.length, equals(list32.length));
      expect(decoded32[0], equals(1000));
      expect(decoded32[decoded32.length - 1], equals(1000));
    });

    test('typed list raw pad16/pad32 and reserve pad16 fillRange paths', () {
      // pad16 in _encodeTypedListRaw: make offset odd before typed list.
      final nestedPad16 = [200, Uint16List.fromList(List<int>.filled(200, 1))];
      final decodedPad16 = GetPacker.unpack<List<dynamic>>(
        GetPacker.pack(nestedPad16),
      );
      expect(decodedPad16[1], isA<Uint16List>());

      // pad32 in _encodeTypedListRaw: force ext32 by large payload.
      final nestedPad32 = [200, Uint64List.fromList(List<int>.filled(9000, 1))];
      final decodedPad32 = GetPacker.unpack<List<dynamic>>(
        GetPacker.pack(nestedPad32),
      );
      expect(decodedPad32[1], isA<Uint64List>());

      // pad16 in _typedListHeaderAndReserve via promoted int list.
      final nestedReservePad16 = [200, List<int>.filled(300, 1000)];
      final decodedReservePad16 = GetPacker.unpack<List<dynamic>>(
        GetPacker.pack(nestedReservePad16),
      );
      expect(decodedReservePad16[1], isA<Uint16List>());
    });
  });
}
