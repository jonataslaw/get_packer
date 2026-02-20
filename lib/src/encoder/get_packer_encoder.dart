import 'dart:convert';
import 'dart:typed_data';

import '../enums/web_interop_mode.dart';
import '../errors/big_data_exception.dart';
import '../errors/unexpected_error_exception.dart';
import '../internal/numeric_runtime.dart';
import '../internal/packed_bool_list.dart';
import '../mixins/packed_model.dart';
import '../objects/ext_type.dart';
import '../objects/get_packer_config.dart';

class GetPackerEncoder {
  /// Stateful encoder that reuses its internal buffer
  ///
  /// Fast path when you're writing lots of small values
  GetPackerEncoder(
      {GetPackerConfig config = const GetPackerConfig(),
      bool trimOnFinish = true})
      : _p = _Packer(config, trimOnFinish: trimOnFinish);

  _Packer _p;

  Uint8List pack(dynamic value) {
    _p._offset = 0;
    _p._encode(value, 0);
    return _p._takeBytes();
  }

  void reset({GetPackerConfig? config, bool trimOnFinish = true}) {
    if (config != null) {
      _p = _Packer(config, trimOnFinish: trimOnFinish);
    } else {
      _p._offset = 0;
    }
  }
}

class _Packer {
  _Packer(this._cfg, {this.trimOnFinish = false})
      : _buffer = Uint8List(_cfg.initialCapacity),
        _utf8 = Utf8Encoder() {
    _bd = ByteData.sublistView(_buffer);
  }

  final GetPackerConfig _cfg;

  /// When true, return a copy sized exactly to the payload
  ///
  /// Leave it off on hot paths, turn it on when you want a self-contained blob
  final bool trimOnFinish;
  final Utf8Encoder _utf8;

  Uint8List _buffer;
  late ByteData _bd;
  int _offset = 0;

  final Float32List _f32 = Float32List(1);

  void _ensureBuffer(int additional) {
    final required = _offset + additional;
    if (required <= _buffer.length) return;
    int newLen = _buffer.isEmpty ? 64 : _buffer.length;
    while (newLen < required) {
      newLen = newLen << 1;
    }
    final nb = Uint8List(newLen);
    nb.setRange(0, _offset, _buffer);
    _buffer = nb;
    _bd = ByteData.sublistView(_buffer);
  }

  Uint8List _takeBytes() {
    final view = Uint8List.view(_buffer.buffer, 0, _offset);
    if (!trimOnFinish) return view;
    return Uint8List.fromList(view);
  }

  void _encode(dynamic value, int depth) {
    if (depth > _cfg.maxDepth) {
      throw UnexpectedError('Max depth exceeded (${_cfg.maxDepth})');
    }

    if (value == null) {
      _ensureBuffer(1);
      _buffer[_offset++] = 0xC0;
      return;
    }

    if (value is bool) {
      _ensureBuffer(1);
      _buffer[_offset++] = value ? 0xC3 : 0xC2;
      return;
    }
    if (value is int) {
      _encodeInt(value);
      return;
    }
    if (value is double) {
      _encodeDouble(value);
      return;
    }
    if (value is String) {
      _encodeString(value);
      return;
    }
    if (value is Uint8List) {
      _encodeBinary(value);
      return;
    }

    if (value is Int8List) {
      _encodeTypedListRaw(
          ExtType.int8List,
          value.length,
          value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          1);
      return;
    }
    if (value is Uint16List) {
      _encodeTypedListRaw(
          ExtType.uint16List,
          value.length,
          value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          2);
      return;
    }
    if (value is Int16List) {
      _encodeTypedListRaw(
          ExtType.int16List,
          value.length,
          value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          2);
      return;
    }
    if (value is Uint32List) {
      _encodeTypedListRaw(
          ExtType.uint32List,
          value.length,
          value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          4);
      return;
    }
    if (value is Int32List) {
      _encodeTypedListRaw(
          ExtType.int32List,
          value.length,
          value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          4);
      return;
    }
    if (value is Uint64List) {
      _encodeTypedListRaw(
          ExtType.uint64List,
          value.length,
          value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          8);
      return;
    }
    if (value is Int64List) {
      _encodeTypedListRaw(
          ExtType.int64List,
          value.length,
          value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          8);
      return;
    }
    if (value is Float32List) {
      _encodeTypedListRaw(
          ExtType.float32List,
          value.length,
          value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          4);
      return;
    }
    if (value is Float64List) {
      _encodeTypedListRaw(
          ExtType.float64List,
          value.length,
          value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          8);
      return;
    }
    if (value is BoolList) {
      _encodeBoolList(value);
      return;
    }

    if (value is DateTime) {
      _encodeDateTime(value);
      return;
    }
    if (value is Duration) {
      _encodeDuration(value);
      return;
    }
    if (value is BigInt) {
      _encodeBigInt(value);
      return;
    }
    if (value is PackedModel) {
      _encode(value.toJson(), depth + 1);
      return;
    }

    if (value is Set) {
      _encodeSet(value, depth);
      return;
    }
    if (value is Iterable) {
      _encodeArray(value, depth);
      return;
    }
    if (value is Map) {
      _encodeMap(value, depth);
      return;
    }
    if (value is Uri) {
      _encodeUri(value);
      return;
    }

    throw UnsupportedError('Unsupported type: ${value.runtimeType}');
  }

  void _encodeInt(int v) {
    // On the VM we can safely carry 64-bit ints around
    // On the web, wide ints either become BigInt or precision bugs
    if (_cfg.webInteropMode == WebInteropMode.requireBigIntForWide &&
        (v > kMaxSafeJsInt || v < kMinSafeJsInt)) {
      throw ArgumentError(
          'Integers beyond ±2^53−1 require BigInt when webInteropMode=requireBigIntForWide: $v');
    }

    if (v >= 0) {
      if (v <= 0x7F) {
        _ensureBuffer(1);
        _buffer[_offset++] = v;
        return;
      }
      if (v <= 0xFF) {
        _ensureBuffer(2);
        _buffer[_offset++] = 0xCC;
        _buffer[_offset++] = v;
        return;
      }
      if (v <= 0xFFFF) {
        _ensureBuffer(3);
        _buffer[_offset++] = 0xCD;
        _bd.setUint16(_offset, v, Endian.big);
        _offset += 2;
        return;
      }
      if (v <= 0xFFFFFFFF) {
        _ensureBuffer(5);
        _buffer[_offset++] = 0xCE;
        _bd.setUint32(_offset, v, Endian.big);
        _offset += 4;
        return;
      }
      if (v.bitLength <= 64) {
        _ensureBuffer(9);
        _buffer[_offset++] = 0xCF;
        _bd.setUint64(_offset, v, Endian.big);
        _offset += 8;
        return;
      }

      if (_cfg.webInteropMode == WebInteropMode.promoteWideToBigInt) {
        _encodeBigInt(BigInt.from(v));
      } else {
        _encodeWideInt(v);
      }
      return;
    } else {
      if (v >= -32) {
        _ensureBuffer(1);
        _buffer[_offset++] = v & 0xFF;
        return;
      }
      if (v >= -128) {
        _ensureBuffer(2);
        _buffer[_offset++] = 0xD0;
        _bd.setInt8(_offset, v);
        _offset += 1;
        return;
      }
      if (v >= -32768) {
        _ensureBuffer(3);
        _buffer[_offset++] = 0xD1;
        _bd.setInt16(_offset, v, Endian.big);
        _offset += 2;
        return;
      }
      if (v >= -2147483648) {
        _ensureBuffer(5);
        _buffer[_offset++] = 0xD2;
        _bd.setInt32(_offset, v, Endian.big);
        _offset += 4;
        return;
      }
      if (v >= -0x8000000000000000) {
        _ensureBuffer(9);
        _buffer[_offset++] = 0xD3;
        _bd.setInt64(_offset, v, Endian.big);
        _offset += 8;
        return;
      }
      if (_cfg.webInteropMode == WebInteropMode.promoteWideToBigInt) {
        _encodeBigInt(BigInt.from(v));
      } else {
        _encodeWideInt(v);
      }
    }
  }

  void _encodeDouble(double v) {
    // float32 is a win when it roundtrips, otherwise pay the 64-bit cost
    if (_cfg.preferFloat32) {
      _f32[0] = v;
      if (!v.isNaN && _f32[0].toDouble() == v) {
        _ensureBuffer(5);
        _buffer[_offset++] = 0xCA;
        _bd.setFloat32(_offset, v, Endian.big);
        _offset += 4;
        return;
      }
    }
    _ensureBuffer(9);
    _buffer[_offset++] = 0xCB;
    _bd.setFloat64(_offset, v, Endian.big);
    _offset += 8;
  }

  void _encodeString(String s) {
    // Single-pass ASCII fast path (check + copy in one loop).
    // If we hit non-ASCII, rollback and go through UTF-8.
    final int n = s.length;
    if (n > 0xFFFFFFFF) {
      throw BigDataException(s,
          reason: 'string length $n exceeds 2^32-1 bytes');
    }

    final int start = _offset;

    // Reserve header + n bytes (ASCII => byteLen == codeUnit length).
    if (n <= 31) {
      _ensureBuffer(1 + n);
      _buffer[_offset++] = 0xA0 | n;
    } else if (n <= 0xFF) {
      _ensureBuffer(2 + n);
      _buffer[_offset++] = 0xD9;
      _buffer[_offset++] = n;
    } else if (n <= 0xFFFF) {
      _ensureBuffer(3 + n);
      _buffer[_offset++] = 0xDA;
      _bd.setUint16(_offset, n, Endian.big);
      _offset += 2;
    } else {
      _ensureBuffer(5 + n);
      _buffer[_offset++] = 0xDB;
      _bd.setUint32(_offset, n, Endian.big);
      _offset += 4;
    }

    final int dataStart = _offset;
    for (int i = 0; i < n; i++) {
      final cu = s.codeUnitAt(i);
      if (cu > 0x7F) {
        // Not ASCII — rollback and do UTF-8.
        _offset = start;
        _encodeStringUtf8(s);
        return;
      }
      _buffer[dataStart + i] = cu;
    }
    _offset = dataStart + n;
  }

  void _encodeStringUtf8(String s) {
    final enc = _utf8.convert(s);
    final m = enc.length;
    if (m <= 31) {
      _ensureBuffer(1 + m);
      _buffer[_offset++] = 0xA0 | m;
    } else if (m <= 0xFF) {
      _ensureBuffer(2 + m);
      _buffer[_offset++] = 0xD9;
      _buffer[_offset++] = m;
    } else if (m <= 0xFFFF) {
      _ensureBuffer(3 + m);
      _buffer[_offset++] = 0xDA;
      _bd.setUint16(_offset, m, Endian.big);
      _offset += 2;
    } else if (m <= 0xFFFFFFFF) {
      _ensureBuffer(5 + m);
      _buffer[_offset++] = 0xDB;
      _bd.setUint32(_offset, m, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(s, reason: 'UTF-8 length $m exceeds 2^32-1 bytes');
    }
    _buffer.setRange(_offset, _offset + m, enc);
    _offset += m;
  }

  void _encodeBinary(Uint8List data) {
    final length = data.length;
    if (length <= 0xFF) {
      _ensureBuffer(2 + length);
      _buffer[_offset++] = 0xC4;
      _buffer[_offset++] = length;
    } else if (length <= 0xFFFF) {
      _ensureBuffer(3 + length);
      _buffer[_offset++] = 0xC5;
      _bd.setUint16(_offset, length, Endian.big);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      _ensureBuffer(5 + length);
      _buffer[_offset++] = 0xC6;
      _bd.setUint32(_offset, length, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(data);
    }
    _buffer.setRange(_offset, _offset + length, data);
    _offset += length;
  }

  void _encodeListOfIntsAsArray(List<int> list) {
    final length = list.length;
    if (length <= 0xF) {
      _ensureBuffer(1);
      _buffer[_offset++] = 0x90 | length;
    } else if (length <= 0xFFFF) {
      _ensureBuffer(3);
      _buffer[_offset++] = 0xDC;
      _bd.setUint16(_offset, length, Endian.big);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      _ensureBuffer(5);
      _buffer[_offset++] = 0xDD;
      _bd.setUint32(_offset, length, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(list);
    }
    for (int i = 0; i < length; i++) {
      _encodeInt(list[i]);
    }
  }

  void _encodeIntListAuto(List<int> list) {
    // Lists of ints are common (ids, offsets, counters)
    // When it pays off, store them as typed payloads so decode can hand back a
    // view instead of N tagged integers
    final int n = list.length;

    if (n == 0) {
      _ensureBuffer(2);
      _buffer[_offset++] = 0xC4;
      _buffer[_offset++] = 0;
      return;
    }

    final int v0 = list[0];
    if (v0 < 0 || v0 > 255) {
      int min = v0, max = v0;
      for (int i = 1; i < n; i++) {
        final v = list[i];
        if (v < min) min = v;
        if (v > max) max = v;
      }
      if (n < _cfg.numericListPromotionMinLength) {
        _encodeListOfIntsAsArray(list);
        return;
      }

      if (min >= -128 && max <= 127) {
        _encodeIntListDirect(ExtType.int8List, list, 1);
        return;
      }
      if (min >= 0 && max <= 0xFFFF) {
        _encodeIntListDirect(ExtType.uint16List, list, 2);
        return;
      }
      if (min >= -32768 && max <= 32767) {
        _encodeIntListDirect(ExtType.int16List, list, 2);
        return;
      }
      if (min >= 0 && max <= 0xFFFFFFFF) {
        _encodeIntListDirect(ExtType.uint32List, list, 4);
        return;
      }
      if (min >= -2147483648 && max <= 2147483647) {
        _encodeIntListDirect(ExtType.int32List, list, 4);
        return;
      }

      final bigMin = BigInt.from(min);
      final bigMax = BigInt.from(max);
      if (min >= 0 && bigMax <= kMaxUint64Big) {
        _encodeIntListDirect(ExtType.uint64List, list, 8);
        return;
      }
      if (bigMin >= kMinInt64Big && bigMax <= kMaxInt64Big) {
        _encodeIntListDirect(ExtType.int64List, list, 8);
        return;
      }

      _encodeListOfIntsAsArray(list);
      return;
    }

    final start = _offset;

    if (n <= 0xFF) {
      _ensureBuffer(2 + n);
      _buffer[_offset++] = 0xC4;
      _buffer[_offset++] = n;
    } else if (n <= 0xFFFF) {
      _ensureBuffer(3 + n);
      _buffer[_offset++] = 0xC5;
      _bd.setUint16(_offset, n, Endian.big);
      _offset += 2;
    } else if (n <= 0xFFFFFFFF) {
      _ensureBuffer(5 + n);
      _buffer[_offset++] = 0xC6;
      _bd.setUint32(_offset, n, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(list);
    }

    final dataStart = _offset;

    int min = v0, max = v0;
    _buffer[dataStart] = v0;

    for (int i = 1; i < n; i++) {
      final v = list[i];
      if (v < 0 || v > 255) {
        _offset = start;

        for (int j = i; j < n; j++) {
          final w = list[j];
          if (w < min) min = w;
          if (w > max) max = w;
        }
        if (n < _cfg.numericListPromotionMinLength) {
          _encodeListOfIntsAsArray(list);
          return;
        }
        if (min >= -128 && max <= 127) {
          _encodeIntListDirect(ExtType.int8List, list, 1);
          return;
        }
        if (min >= 0 && max <= 0xFFFF) {
          _encodeIntListDirect(ExtType.uint16List, list, 2);
          return;
        }
        if (min >= -32768 && max <= 32767) {
          _encodeIntListDirect(ExtType.int16List, list, 2);
          return;
        }
        if (min >= 0 && max <= 0xFFFFFFFF) {
          _encodeIntListDirect(ExtType.uint32List, list, 4);
          return;
        }
        if (min >= -2147483648 && max <= 2147483647) {
          _encodeIntListDirect(ExtType.int32List, list, 4);
          return;
        }
        final bigMin = BigInt.from(min);
        final bigMax = BigInt.from(max);
        if (min >= 0 && bigMax <= kMaxUint64Big) {
          _encodeIntListDirect(ExtType.uint64List, list, 8);
          return;
        }
        if (bigMin >= kMinInt64Big && bigMax <= kMaxInt64Big) {
          _encodeIntListDirect(ExtType.int64List, list, 8);
          return;
        }
        _encodeListOfIntsAsArray(list);
        return;
      }
      if (v < min) min = v;
      if (v > max) max = v;
      _buffer[dataStart + i] = v;
    }

    _offset = dataStart + n;
  }

  void _encodeTypedListRaw(int type, int count, Uint8List raw, int elemSize) {
    final int align = elemSize.clamp(1, 8);

    // Try ext8 first
    const int s8 = 7;
    final int pad8 = (-(_offset + s8)) & (align - 1);
    final int dataLen8 = 4 + pad8 + raw.length;
    if (dataLen8 <= 0xFF) {
      _ensureBuffer(s8 + pad8 + raw.length);
      _buffer[_offset++] = 0xC7;
      _buffer[_offset++] = dataLen8;
      _buffer[_offset++] = type;
      _bd.setUint32(_offset, count, Endian.big);
      _offset += 4;
      if (pad8 != 0) {
        _buffer.fillRange(_offset, _offset + pad8, 0);
        _offset += pad8;
      }
      _buffer.setRange(_offset, _offset + raw.length, raw);
      _offset += raw.length;
      return;
    }

    // ext16
    const int s16 = 8;
    final int pad16 = (-(_offset + s16)) & (align - 1);
    final int dataLen16 = 4 + pad16 + raw.length;
    if (dataLen16 <= 0xFFFF) {
      _ensureBuffer(s16 + pad16 + raw.length);
      _buffer[_offset++] = 0xC8;
      _bd.setUint16(_offset, dataLen16, Endian.big);
      _offset += 2;
      _buffer[_offset++] = type;
      _bd.setUint32(_offset, count, Endian.big);
      _offset += 4;
      if (pad16 != 0) {
        _buffer.fillRange(_offset, _offset + pad16, 0);
        _offset += pad16;
      }
      _buffer.setRange(_offset, _offset + raw.length, raw);
      _offset += raw.length;
      return;
    }

    // ext32
    const int s32 = 10;
    final int pad32 = (-(_offset + s32)) & (align - 1);
    final int dataLen32 = 4 + pad32 + raw.length;

    _ensureBuffer(s32 + pad32 + raw.length);
    _buffer[_offset++] = 0xC9;
    _bd.setUint32(_offset, dataLen32, Endian.big);
    _offset += 4;
    _buffer[_offset++] = type;
    _bd.setUint32(_offset, count, Endian.big);
    _offset += 4;
    if (pad32 != 0) {
      _buffer.fillRange(_offset, _offset + pad32, 0);
      _offset += pad32;
    }
    _buffer.setRange(_offset, _offset + raw.length, raw);
    _offset += raw.length;
  }

  int _typedListHeaderAndReserve(
      int type, int count, int elemSize, int rawLen) {
    // Same layout as _encodeTypedListRaw(), but lets callers write directly into
    // the reserved payload slice
    final int align = elemSize.clamp(1, 8);
    const int s8 = 7, s16 = 8, s32 = 10;

    final pad8 = (-(_offset + s8)) & (align - 1);
    final pad16 = (-(_offset + s16)) & (align - 1);
    final pad32 = (-(_offset + s32)) & (align - 1);

    final dataLen8 = 4 + pad8 + rawLen;
    final dataLen16 = 4 + pad16 + rawLen;
    final dataLen32 = 4 + pad32 + rawLen;

    if (dataLen8 <= 0xFF) {
      _ensureBuffer(s8 + pad8 + rawLen);
      _buffer[_offset++] = 0xC7;
      _buffer[_offset++] = dataLen8;
      _buffer[_offset++] = type;
      _bd.setUint32(_offset, count, Endian.big);
      _offset += 4;
      if (pad8 != 0) {
        _buffer.fillRange(_offset, _offset + pad8, 0);
        _offset += pad8;
      }
      final start = _offset;
      _offset += rawLen;
      return start;
    }
    if (dataLen16 <= 0xFFFF) {
      _ensureBuffer(s16 + pad16 + rawLen);
      _buffer[_offset++] = 0xC8;
      _bd.setUint16(_offset, dataLen16, Endian.big);
      _offset += 2;
      _buffer[_offset++] = type;
      _bd.setUint32(_offset, count, Endian.big);
      _offset += 4;
      if (pad16 != 0) {
        _buffer.fillRange(_offset, _offset + pad16, 0);
        _offset += pad16;
      }
      final start = _offset;
      _offset += rawLen;
      return start;
    }
    _ensureBuffer(s32 + pad32 + rawLen);
    _buffer[_offset++] = 0xC9;
    _bd.setUint32(_offset, dataLen32, Endian.big);
    _offset += 4;
    _buffer[_offset++] = type;
    _bd.setUint32(_offset, count, Endian.big);
    _offset += 4;
    if (pad32 != 0) {
      _buffer.fillRange(_offset, _offset + pad32, 0);
      _offset += pad32;
    }
    final start = _offset;
    _offset += rawLen;
    return start;
  }

  void _encodeIntListDirect(int extType, List<int> list, int elemSize) {
    // Write values in host endian so the decoder can use TypedData.view()
    // without per-element byte swapping
    final n = list.length;
    final start =
        _typedListHeaderAndReserve(extType, n, elemSize, n * elemSize);

    if (elemSize == 1) {
      for (int i = 0; i < n; i++) {
        _buffer[start + i] = list[i] & 0xFF;
      }
      return;
    }
    int p = start;
    if (elemSize == 2) {
      final signed = extType == ExtType.int16List;
      for (int i = 0; i < n; i++, p += 2) {
        final v = list[i];
        signed ? _bd.setInt16(p, v, host) : _bd.setUint16(p, v, host);
      }
      return;
    }
    if (elemSize == 4) {
      final signed = extType == ExtType.int32List;
      for (int i = 0; i < n; i++, p += 4) {
        final v = list[i];
        signed ? _bd.setInt32(p, v, host) : _bd.setUint32(p, v, host);
      }
      return;
    }
    if (elemSize == 8) {
      final signed = extType == ExtType.int64List;
      for (int i = 0; i < n; i++, p += 8) {
        final v = list[i];
        signed ? _bd.setInt64(p, v, host) : _bd.setUint64(p, v, host);
      }
      return;
    }
  }

  void _encodeDoubleListDirect(int extType, List<double> list, int elemSize) {
    final n = list.length;
    final start =
        _typedListHeaderAndReserve(extType, n, elemSize, n * elemSize);

    int p = start;
    if (elemSize == 4) {
      for (int i = 0; i < n; i++, p += 4) {
        _bd.setFloat32(p, list[i], host);
      }
    } else {
      for (int i = 0; i < n; i++, p += 8) {
        _bd.setFloat64(p, list[i], host);
      }
    }
  }

  void _encodeBoolList(BoolList list) {
    final count = list.length;
    final packed = list.asBytesView();
    final byteLen = packed.length;

    int headerBytes;
    if (4 + byteLen <= 0xFF) {
      headerBytes = 1 + 1 + 1;

      _ensureBuffer(headerBytes + 4 + byteLen);
      _buffer[_offset++] = 0xC7;
      _buffer[_offset++] = 4 + byteLen;
      _buffer[_offset++] = ExtType.boolList;
    } else if (4 + byteLen <= 0xFFFF) {
      headerBytes = 1 + 2 + 1;

      _ensureBuffer(headerBytes + 4 + byteLen);
      _buffer[_offset++] = 0xC8;
      _bd.setUint16(_offset, 4 + byteLen, Endian.big);
      _offset += 2;
      _buffer[_offset++] = ExtType.boolList;
    } else {
      headerBytes = 1 + 4 + 1;

      _ensureBuffer(headerBytes + 4 + byteLen);
      _buffer[_offset++] = 0xC9;
      _bd.setUint32(_offset, 4 + byteLen, Endian.big);
      _offset += 4;
      _buffer[_offset++] = ExtType.boolList;
    }
    _bd.setUint32(_offset, count, Endian.big);
    _offset += 4;
    _buffer.setRange(_offset, _offset + byteLen, packed);
    _offset += byteLen;
  }

  bool _tryPromoteDoubleListToTypedDirect(List<double> list) {
    final n = list.length;
    if (n < _cfg.numericListPromotionMinLength) return false;

    if (_cfg.preferFloat32) {
      bool allF32 = true;
      for (int i = 0; i < n; i++) {
        final v = list[i];
        _f32[0] = v;
        if (v.isNaN || _f32[0].toDouble() != v) {
          allF32 = false;
          break;
        }
      }
      if (allF32) {
        _encodeDoubleListDirect(ExtType.float32List, list, 4);
        return true;
      }
    }
    _encodeDoubleListDirect(ExtType.float64List, list, 8);
    return true;
  }

  bool _tryPromoteBoolList(List<bool> list) {
    final n = list.length;
    if (n < _cfg.numericListPromotionMinLength) return false;

    final bl = BoolList(n);
    for (int i = 0; i < n; i++) {
      bl[i] = list[i];
    }
    _encodeBoolList(bl);
    return true;
  }

  void _encodeArray(Iterable it, int depth) {
    if (it is Set) {
      _encodeSet(it, depth);
      return;
    }

    if (it is List) {
      if (it is List<int>) {
        _encodeIntListAuto(it);
        return;
      } else if (it is List<double>) {
        if (_tryPromoteDoubleListToTypedDirect(it)) return;
      } else if (it is List<bool>) {
        if (_tryPromoteBoolList(it)) return;
      }

      final length = it.length;
      if (length <= 0xF) {
        _ensureBuffer(1);
        _buffer[_offset++] = 0x90 | length;
      } else if (length <= 0xFFFF) {
        _ensureBuffer(3);
        _buffer[_offset++] = 0xDC;
        _bd.setUint16(_offset, length, Endian.big);
        _offset += 2;
      } else if (length <= 0xFFFFFFFF) {
        _ensureBuffer(5);
        _buffer[_offset++] = 0xDD;
        _bd.setUint32(_offset, length, Endian.big);
        _offset += 4;
      } else {
        throw BigDataException(it);
      }
      for (int i = 0; i < length; i++) {
        _encode(it[i], depth + 1);
      }
      return;
    }

    var length = 0;
    for (final _ in it) {
      length++;
      if (length > 0xFFFFFFFF) throw BigDataException(it);
    }
    if (length <= 0xF) {
      _ensureBuffer(1);
      _buffer[_offset++] = 0x90 | length;
    } else if (length <= 0xFFFF) {
      _ensureBuffer(3);
      _buffer[_offset++] = 0xDC;
      _bd.setUint16(_offset, length, Endian.big);
      _offset += 2;
    } else {
      _ensureBuffer(5);
      _buffer[_offset++] = 0xDD;
      _bd.setUint32(_offset, length, Endian.big);
      _offset += 4;
    }
    for (final item in it) {
      _encode(item, depth + 1);
    }
  }

  void _encodeSet(Set set, int depth) {
    final count = set.length;
    _ensureBuffer(1 + 4 + 1 + 4);
    _buffer[_offset++] = 0xC9;
    final lenPos = _offset;
    _bd.setUint32(_offset, 0, Endian.big);
    _offset += 4;
    _buffer[_offset++] = ExtType.set;
    _bd.setUint32(_offset, count, Endian.big);
    _offset += 4;

    for (final item in set) {
      _encode(item, depth + 1);
    }

    final payloadLen = _offset - (lenPos + 4 + 1);
    _bd.setUint32(lenPos, payloadLen, Endian.big);
  }

  void _encodeMap(Map<dynamic, dynamic> map, int depth) {
    final length = map.length;

    if (length <= 0xF) {
      _ensureBuffer(1);
      _buffer[_offset++] = 0x80 | length;
    } else if (length <= 0xFFFF) {
      _ensureBuffer(3);
      _buffer[_offset++] = 0xDE;
      _bd.setUint16(_offset, length, Endian.big);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      _ensureBuffer(5);
      _buffer[_offset++] = 0xDF;
      _bd.setUint32(_offset, length, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(map);
    }

    if (length == 0) return;

    if (_cfg.deterministicMaps) {
      // Only sort when keys are all strings
      // Anything else gets hairy fast (ordering semantics and cross-runtime stability)
      bool allString = true;
      final keys = List<String>.filled(length, '', growable: false);
      int i = 0;
      for (final k in map.keys) {
        if (k is String) {
          keys[i++] = k;
        } else {
          allString = false;
          break;
        }
      }
      if (allString) {
        keys.sort();
        for (int j = 0; j < length; j++) {
          final k = keys[j];
          _encodeString(k);
          _encode(map[k], depth + 1);
        }
        return;
      }
    }

    if (map is Map<String, Object?>) {
      map.forEach((k, v) {
        _encodeString(k);
        _encode(v, depth + 1);
      });
      return;
    }

    map.forEach((k, v) {
      if (k is String) {
        _encodeString(k);
      } else {
        _encode(k, depth + 1);
      }
      _encode(v, depth + 1);
    });
    return;
  }

  void _encodeDateTime(DateTime value) {
    const payloadLen = 9;
    _ensureBuffer(1 + 1 + 1 + payloadLen);
    _buffer[_offset++] = 0xC7;
    _buffer[_offset++] = payloadLen;
    _buffer[_offset++] = ExtType.dateTime;
    _buffer[_offset++] = value.isUtc ? 1 : 0;
    _bd.setInt64(_offset, value.microsecondsSinceEpoch, Endian.big);
    _offset += 8;
  }

  void _encodeDuration(Duration value) {
    _ensureBuffer(1 + 1 + 8);
    _buffer[_offset++] = 0xD7;
    _buffer[_offset++] = ExtType.duration;
    _bd.setInt64(_offset, value.inMicroseconds, Endian.big);
    _offset += 8;
  }

  void _encodeUri(Uri value) {
    final enc = _utf8.convert(value.toString());
    final m = enc.length;

    if (m <= 0xFF) {
      _ensureBuffer(1 + 1 + 1 + m);
      _buffer[_offset++] = 0xC7;
      _buffer[_offset++] = m;
      _buffer[_offset++] = ExtType.uri;
    } else if (m <= 0xFFFF) {
      _ensureBuffer(1 + 2 + 1 + m);
      _buffer[_offset++] = 0xC8;
      _bd.setUint16(_offset, m, Endian.big);
      _offset += 2;
      _buffer[_offset++] = ExtType.uri;
    } else if (m <= 0xFFFFFFFF) {
      _ensureBuffer(1 + 4 + 1 + m);
      _buffer[_offset++] = 0xC9;
      _bd.setUint32(_offset, m, Endian.big);
      _offset += 4;
      _buffer[_offset++] = ExtType.uri;
    } else {
      throw BigDataException(value,
          reason: 'URI UTF-8 length $m exceeds 2^32-1 bytes');
    }

    _buffer.setRange(_offset, _offset + m, enc);
    _offset += m;
  }

  void _encodeBigInt(BigInt value) {
    // BigInt is the correctness-first path
    // Keep it bounded so payloads can't force pathological allocations
    final bool neg = value.isNegative;
    final BigInt mag = neg ? -value : value;
    final int magBytes = mag == BigInt.zero ? 0 : (mag.bitLength + 7) >> 3;
    if (magBytes > _cfg.maxBigIntMagnitudeBytes) {
      throw BigDataException(value,
          reason:
              'BigInt magnitude ${magBytes}B exceeds cap ${_cfg.maxBigIntMagnitudeBytes}B');
    }
    final payloadLength = 1 + magBytes;

    if (payloadLength <= 0xFF) {
      _ensureBuffer(1 + 1 + 1 + payloadLength);
      _buffer[_offset++] = 0xC7;
      _buffer[_offset++] = payloadLength;
    } else if (payloadLength <= 0xFFFF) {
      _ensureBuffer(1 + 2 + 1 + payloadLength);
      _buffer[_offset++] = 0xC8;
      _bd.setUint16(_offset, payloadLength, Endian.big);
      _offset += 2;
    } else if (payloadLength <= 0xFFFFFFFF) {
      _ensureBuffer(1 + 4 + 1 + payloadLength);
      _buffer[_offset++] = 0xC9;
      _bd.setUint32(_offset, payloadLength, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(value);
    }

    _buffer[_offset++] = ExtType.bigInt;
    _buffer[_offset++] = neg ? 0x01 : 0x00;

    final int dst = _offset;
    _offset += magBytes;
    _writeBigIntMagnitudeBE(mag, dst, magBytes);
  }

  void _writeBigIntMagnitudeBE(BigInt magnitude, int dst, int byteLen) {
    // Big-endian magnitude keeps the wire format stable
    if (byteLen == 0) return;
    final int headBytes = byteLen & 3;
    final int tailWords = byteLen >> 2;
    var v = magnitude;

    int pos = dst + byteLen;
    for (int i = 0; i < tailWords; i++) {
      pos -= 4;
      final int w = (v & kMask32).toInt();
      _bd.setUint32(pos, w, Endian.big);
      v = v >> 32;
    }
    for (int i = headBytes - 1; i >= 0; i--) {
      _buffer[dst + i] = (v & kMask8).toInt();
      v = v >> 8;
    }
  }

  void _encodeWideInt(int value) {
    // wideInt exists so we can keep `int` on the VM without losing values
    // On decode we may return int or BigInt depending on platform and mode
    final bool neg = value.isNegative;
    final BigInt mag = BigInt.from(neg ? -value : value);
    final int magBytes = mag == BigInt.zero ? 0 : (mag.bitLength + 7) >> 3;
    if (magBytes > _cfg.maxBigIntMagnitudeBytes) {
      throw BigDataException(value,
          reason:
              'wideInt magnitude ${magBytes}B exceeds cap ${_cfg.maxBigIntMagnitudeBytes}B');
    }
    final int payloadLength = 1 + magBytes;

    if (payloadLength <= 0xFF) {
      _ensureBuffer(1 + 1 + 1 + payloadLength);
      _buffer[_offset++] = 0xC7;
      _buffer[_offset++] = payloadLength;
    } else if (payloadLength <= 0xFFFF) {
      _ensureBuffer(1 + 2 + 1 + payloadLength);
      _buffer[_offset++] = 0xC8;
      _bd.setUint16(_offset, payloadLength, Endian.big);
      _offset += 2;
    } else {
      _ensureBuffer(1 + 4 + 1 + payloadLength);
      _buffer[_offset++] = 0xC9;
      _bd.setUint32(_offset, payloadLength, Endian.big);
      _offset += 4;
    }

    _buffer[_offset++] = ExtType.wideInt;
    _buffer[_offset++] = neg ? 0x01 : 0x00;

    final int dst = _offset;
    _offset += magBytes;
    _writeBigIntMagnitudeBE(mag, dst, magBytes);
  }
}
