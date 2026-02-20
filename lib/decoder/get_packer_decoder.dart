import 'dart:convert';
import 'dart:typed_data';

import '../enums/web_interop_mode.dart';
import '../errors/unexpected_error_exception.dart';
import '../internal/numeric_runtime.dart';
import '../objects/ext_type.dart';
import '../objects/get_packer_config.dart';

class GetPackerDecoder {
  /// Stateful decoder that reuses its scratch state
  GetPackerDecoder({GetPackerConfig config = const GetPackerConfig()})
      : _u = _Unpacker(Uint8List(0), config);

  final _Unpacker _u;

  void reset(Uint8List bytes) => _u.setInput(bytes);
  T unpack<T>() => _u._decodeRoot<T>();
}

class _Unpacker {
  _Unpacker(Uint8List bytes, this._cfg)
      : _utf8 = Utf8Decoder(allowMalformed: _cfg.allowMalformedUtf8) {
    setInput(bytes);
  }

  final GetPackerConfig _cfg;
  late Uint8List _bytes;
  late ByteData _bd;
  final Utf8Decoder _utf8;

  int _offset = 0;

  void setInput(Uint8List bytes) {
    _bytes = bytes;
    _bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    _offset = 0;
  }

  @pragma('vm:prefer-inline')
  void _need(int n) {
    if (_offset + n > _bytes.length) {
      throw UnexpectedError('Unexpected end of input; need $n bytes',
          offset: _offset);
    }
  }

  T _decodeRoot<T>() => _decode(0) as T;

  void skipValue() => _skip(0);

  @pragma('vm:prefer-inline')
  bool _isStrPrefix(int p) =>
      (p >= 0xA0 && p <= 0xBF) || p == 0xD9 || p == 0xDA || p == 0xDB;

  String _readStringViaPrefix() {
    final prefix = _bytes[_offset++];
    if (prefix >= 0xA0 && prefix <= 0xBF) return _readString(prefix & 0x1F);
    if (prefix == 0xD9) return _readString(_readUint8());
    if (prefix == 0xDA) return _readString(_readUint16());
    if (prefix == 0xDB) return _readString(_readUint32());
    throw UnexpectedError(
        'Map key is not a string (prefix 0x${prefix.toRadixString(16)})',
        offset: _offset - 1);
  }

  dynamic _decode(int depth) {
    if (depth > _cfg.maxDepth) {
      throw UnexpectedError('Max depth exceeded (${_cfg.maxDepth})',
          offset: _offset);
    }
    if (_offset >= _bytes.length) {
      throw UnexpectedError('Unexpected end of input', offset: _offset);
    }

    final int prefix = _bytes[_offset++];

    if (prefix <= 0x7F) return prefix;

    if (prefix >= 0x80 && prefix <= 0x8F) return _readMap(prefix & 0x0F, depth);

    if (prefix >= 0x90 && prefix <= 0x9F) {
      return _readArray(prefix & 0x0F, depth);
    }

    if (prefix >= 0xA0 && prefix <= 0xBF) return _readString(prefix & 0x1F);

    if (prefix >= 0xE0) return prefix - 256;

    switch (prefix) {
      case 0xC0:
        return null;
      case 0xC2:
        return false;
      case 0xC3:
        return true;

      case 0xC4:
        return _readBinary(_readUint8());
      case 0xC5:
        return _readBinary(_readUint16());
      case 0xC6:
        return _readBinary(_readUint32());

      case 0xC7:
        return _readExt(_readUint8(), depth);
      case 0xC8:
        return _readExt(_readUint16(), depth);
      case 0xC9:
        return _readExt(_readUint32(), depth);

      case 0xCA:
        return _readFloat32();
      case 0xCB:
        return _readFloat64();

      case 0xCC:
        return _readUint8();
      case 0xCD:
        return _readUint16();
      case 0xCE:
        return _readUint32();
      case 0xCF:
        return _readUint64Smart();

      case 0xD0:
        return _readInt8();
      case 0xD1:
        return _readInt16();
      case 0xD2:
        return _readInt32();
      case 0xD3:
        return _readInt64Smart();

      case 0xD4:
        return _readExtFixed(1, depth);
      case 0xD5:
        return _readExtFixed(2, depth);
      case 0xD6:
        return _readExtFixed(4, depth);
      case 0xD7:
        return _readExtFixed(8, depth);
      case 0xD8:
        return _readExtFixed(16, depth);

      case 0xD9:
        return _readString(_readUint8());
      case 0xDA:
        return _readString(_readUint16());
      case 0xDB:
        return _readString(_readUint32());

      case 0xDC:
        return _readArray(_readUint16(), depth);
      case 0xDD:
        return _readArray(_readUint32(), depth);

      case 0xDE:
        return _readMap(_readUint16(), depth);
      case 0xDF:
        return _readMap(_readUint32(), depth);

      default:
        throw UnsupportedError(
            'Unknown prefix: 0x${prefix.toRadixString(16)} at offset ${_offset - 1}');
    }
  }

  @pragma('vm:prefer-inline')
  int _readUint8() {
    _need(1);
    return _bytes[_offset++];
  }

  @pragma('vm:prefer-inline')
  int _readUint16() {
    _need(2);
    final v = _bd.getUint16(_offset, Endian.big);
    _offset += 2;
    return v;
  }

  @pragma('vm:prefer-inline')
  int _readUint32() {
    _need(4);
    final v = _bd.getUint32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  @pragma('vm:prefer-inline')
  int _readInt8() {
    _need(1);
    final v = _bd.getInt8(_offset);
    _offset += 1;
    return v;
  }

  @pragma('vm:prefer-inline')
  int _readInt16() {
    _need(2);
    final v = _bd.getInt16(_offset, Endian.big);
    _offset += 2;
    return v;
  }

  @pragma('vm:prefer-inline')
  int _readInt32() {
    _need(4);
    final v = _bd.getInt32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  @pragma('vm:prefer-inline')
  int _readInt64() {
    _need(8);
    final v = _bd.getInt64(_offset, Endian.big);
    _offset += 8;
    return v;
  }

  dynamic _readUint64Smart() {
    _need(8);
    final hi = _bd.getUint32(_offset, Endian.big);
    final lo = _bd.getUint32(_offset + 4, Endian.big);
    _offset += 8;

    final safe = hi <= 0x001FFFFF;
    switch (_cfg.webInteropMode) {
      case WebInteropMode.off:
        if (kIsWeb && !safe) return (BigInt.from(hi) << 32) | BigInt.from(lo);
        return hi * 4294967296 + lo;
      case WebInteropMode.promoteWideToBigInt:
      case WebInteropMode.requireBigIntForWide:
        if (safe) return hi * 4294967296 + lo;
        return (BigInt.from(hi) << 32) | BigInt.from(lo);
    }
  }

  dynamic _readInt64Smart() {
    _need(8);
    final hiU = _bd.getUint32(_offset, Endian.big);
    final lo = _bd.getUint32(_offset + 4, Endian.big);
    _offset += 8;

    final neg = (hiU & 0x80000000) != 0;

    final bool safe = !neg
        ? (hiU <= 0x001FFFFF)
        : ((hiU > 0xFFE00000) || (hiU == 0xFFE00000 && lo != 0));

    switch (_cfg.webInteropMode) {
      case WebInteropMode.off:
        if (kIsWeb && !safe) {
          final hiSignedBig = BigInt.from(neg ? (hiU - 0x100000000) : hiU);
          return (hiSignedBig << 32) + BigInt.from(lo);
        }
        final hiSigned = neg ? (hiU - 0x100000000) : hiU;
        return hiSigned * 4294967296 + lo;
      case WebInteropMode.promoteWideToBigInt:
      case WebInteropMode.requireBigIntForWide:
        if (safe) {
          final hiSigned = neg ? (hiU - 0x100000000) : hiU;
          return hiSigned * 4294967296 + lo;
        }
        final hiSignedBig = BigInt.from(neg ? (hiU - 0x100000000) : hiU);
        return (hiSignedBig << 32) + BigInt.from(lo);
    }
  }

  @pragma('vm:prefer-inline')
  double _readFloat32() {
    _need(4);
    final v = _bd.getFloat32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  @pragma('vm:prefer-inline')
  double _readFloat64() {
    _need(8);
    final v = _bd.getFloat64(_offset, Endian.big);
    _offset += 8;
    return v;
  }

  String _readString(int length) {
    _need(length);
    final bytes = _bytes;
    final start = _offset;
    final end = start + length;

    int i = start;
    while (i < end && (bytes[i] & 0x80) == 0) {
      i++;
    }

    _offset = end;

    return (i == end)
        ? String.fromCharCodes(bytes, start, end)
        : _utf8.convert(bytes, start, end);
  }

  Uint8List _readBinary(int length) {
    _need(length);
    final result =
        Uint8List.view(_bytes.buffer, _bytes.offsetInBytes + _offset, length);
    _offset += length;
    return result;
  }

  List<dynamic> _readArray(int length, int depth) {
    if (length == 0) return <dynamic>[];
    final list = List<dynamic>.filled(length, null, growable: false);
    for (int i = 0; i < length; i++) {
      list[i] = _decode(depth + 1);
    }
    return list;
  }

  Map<dynamic, dynamic> _readMap(int length, int depth) {
    if (length == 0) return <dynamic, dynamic>{};

    if (_offset < _bytes.length && _isStrPrefix(_bytes[_offset])) {
      final sMap = <String, dynamic>{};

      int i = 0;

      while (i < length) {
        if (_offset >= _bytes.length) {
          throw UnexpectedError('Unexpected end of input', offset: _offset);
        }
        if (!_isStrPrefix(_bytes[_offset])) break;

        final key = _readStringViaPrefix();
        final value = _decode(depth + 1);
        sMap[key] = value;
        i++;
      }

      if (i == length) {
        return sMap;
      }

      final dyn = <dynamic, dynamic>{}..addAll(sMap);
      for (; i < length; i++) {
        final key = _decode(depth + 1);
        final value = _decode(depth + 1);
        dyn[key] = value;
      }
      return dyn;
    }

    final dyn = <dynamic, dynamic>{};
    for (int i = 0; i < length; i++) {
      final key = _decode(depth + 1);
      final value = _decode(depth + 1);
      dyn[key] = value;
    }
    return dyn;
  }

  dynamic _readExtFixed(int payloadLength, int depth) =>
      _readExt(payloadLength, depth);

  BigInt _bytesToBigIntRange(int start, int length) {
    if (length <= 0) return BigInt.zero;
    int p = start;
    final end = start + length;
    BigInt result = BigInt.zero;

    final headBytes = length & 3;
    if (headBytes != 0) {
      int head = 0;
      for (int i = 0; i < headBytes; i++) {
        head = (head << 8) | _bytes[p++];
      }
      result = BigInt.from(head);
    }
    while (p + 4 <= end) {
      final int w = _bd.getUint32(p, Endian.big);
      p += 4;
      result = (result << 32) | BigInt.from(w);
    }
    return result;
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    final len = bytes.length;
    if (len == 0) return BigInt.zero;
    int p = 0;
    BigInt result = BigInt.zero;

    final headBytes = len & 3;
    if (headBytes != 0) {
      int head = 0;
      for (int i = 0; i < headBytes; i++) {
        head = (head << 8) | bytes[p++];
      }
      result = BigInt.from(head);
    }
    while (p + 4 <= len) {
      final int w = (bytes[p] << 24) |
          (bytes[p + 1] << 16) |
          (bytes[p + 2] << 8) |
          (bytes[p + 3]);
      p += 4;
      result = (result << 32) | BigInt.from(w);
    }
    return result;
  }

  dynamic _readExt(int payloadLength, int depth) {
    // Ext payloads start with a 1-byte type tag, then a type-specific body
    // For typed lists we also allow a few padding bytes so views stay aligned
    _need(payloadLength + 1);
    final type = _bytes[_offset++];
    final payloadStart = _offset;
    final endOfPayload = payloadStart + payloadLength;

    if (type == ExtType.dateTime) {
      if (payloadLength != 9) {
        throw UnexpectedError('Bad DateTime payload length: $payloadLength',
            offset: _offset);
      }
      final isUtc = _bytes[_offset++] != 0;
      final micros = _readInt64();
      if (_offset != endOfPayload) {
        throw UnexpectedError('Trailing bytes in DateTime ext',
            offset: _offset);
      }
      return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: isUtc);
    }

    if (type == ExtType.duration) {
      if (payloadLength != 8) {
        throw UnexpectedError('Bad Duration payload length: $payloadLength',
            offset: _offset);
      }
      final micros = _readInt64();
      if (_offset != endOfPayload) {
        throw UnexpectedError('Trailing bytes in Duration ext',
            offset: _offset);
      }
      return Duration(microseconds: micros);
    }

    if (type == ExtType.bigInt) {
      if (payloadLength < 1) {
        throw UnexpectedError('Bad BigInt payload length: $payloadLength',
            offset: _offset);
      }
      final negative = _bytes[_offset++] == 0x01;
      final magLen = payloadLength - 1;
      if (magLen > _cfg.maxBigIntMagnitudeBytes) {
        throw UnexpectedError(
            'BigInt magnitude ${magLen}B exceeds cap ${_cfg.maxBigIntMagnitudeBytes}B',
            offset: _offset);
      }
      final start = _offset;
      _offset += magLen;
      if (_offset != endOfPayload) {
        throw UnexpectedError('Trailing bytes in BigInt ext', offset: _offset);
      }
      final magnitude = _bytesToBigIntRange(start, magLen);
      return negative ? -magnitude : magnitude;
    }

    if (type == ExtType.wideInt) {
      if (payloadLength < 1) {
        throw UnexpectedError('Bad wideInt payload length: $payloadLength',
            offset: _offset);
      }
      final negative = _bytes[_offset++] == 0x01;
      final magLen = payloadLength - 1;
      if (magLen > _cfg.maxBigIntMagnitudeBytes) {
        throw UnexpectedError('wideInt magnitude too large: $magLen bytes',
            offset: _offset);
      }
      _need(magLen);
      final magBytes =
          Uint8List.view(_bytes.buffer, _bytes.offsetInBytes + _offset, magLen);
      _offset += magLen;
      if (_offset != endOfPayload) {
        throw UnexpectedError('Trailing bytes in wideInt ext', offset: _offset);
      }

      final magnitude = _bytesToBigInt(magBytes);
      final big = negative ? -magnitude : magnitude;

      switch (_cfg.webInteropMode) {
        case WebInteropMode.off:
          if (kIsWeb) {
            if (big >= kMinSafeJsBig && big <= kMaxSafeJsBig) {
              return big.toInt();
            }
            return big;
          } else {
            if (big >= kMinInt64Big && big <= kMaxInt64Big) {
              return big.toInt();
            }
            return big;
          }
        case WebInteropMode.promoteWideToBigInt:
        case WebInteropMode.requireBigIntForWide:
          if (big >= kMinSafeJsBig && big <= kMaxSafeJsBig) {
            return big.toInt();
          }
          return big;
      }
    }

    if (type == ExtType.boolList) {
      if (payloadLength < 4) {
        throw UnexpectedError('Bad boolList payload length', offset: _offset);
      }
      final count = _readUint32();
      final bytesLen = payloadLength - 4;
      _need(bytesLen);
      final data = Uint8List.view(
          _bytes.buffer, _bytes.offsetInBytes + _offset, bytesLen);
      _offset += bytesLen;
      if (_offset != endOfPayload) {
        throw UnexpectedError('Trailing bytes in boolList ext',
            offset: _offset);
      }
      return BoolList.fromPacked(data, count);
    }

    if (type == ExtType.int8List) {
      return _readTypedListInt(1, true, payloadLength, endOfPayload);
    }
    if (type == ExtType.uint16List || type == ExtType.int16List) {
      final signed = type == ExtType.int16List;
      return _readTypedListInt(2, signed, payloadLength, endOfPayload);
    }
    if (type == ExtType.uint32List || type == ExtType.int32List) {
      final signed = type == ExtType.int32List;
      return _readTypedListInt(4, signed, payloadLength, endOfPayload);
    }
    if (type == ExtType.uint64List || type == ExtType.int64List) {
      final signed = type == ExtType.int64List;
      return _readTypedListInt(8, signed, payloadLength, endOfPayload);
    }
    if (type == ExtType.float32List) {
      return _readTypedListFloat(4, payloadLength, endOfPayload);
    }
    if (type == ExtType.float64List) {
      return _readTypedListFloat(8, payloadLength, endOfPayload);
    }

    if (type == ExtType.set) {
      if (payloadLength < 4) {
        throw UnexpectedError('Bad Set payload length: $payloadLength',
            offset: _offset);
      }
      final count = _readUint32();
      final result = <dynamic>{};
      for (int i = 0; i < count; i++) {
        result.add(_decode(depth + 1));
      }
      if (_offset != endOfPayload) {
        throw UnexpectedError('Trailing bytes in Set ext', offset: _offset);
      }
      return result;
    }

    if (type == ExtType.uri) {
      final bytes = _bytes;
      final start = _offset;
      final end = start + payloadLength;

      int i = start;
      while (i < end && (bytes[i] & 0x80) == 0) {
        i++;
      }

      final s = (i == end)
          ? String.fromCharCodes(bytes, start, end)
          : _utf8.convert(bytes, start, end);

      _offset = end;

      if (_offset != endOfPayload) {
        throw UnexpectedError('Trailing bytes in URI ext', offset: _offset);
      }
      return Uri.parse(s);
    }

    _need(payloadLength);
    final data = Uint8List.view(
        _bytes.buffer, _bytes.offsetInBytes + _offset, payloadLength);
    _offset = endOfPayload;
    return ExtValue(type, data);
  }

  dynamic _readTypedListInt(
      int elemSize, bool signed, int payloadLength, int endOfPayload) {
    // If the payload is aligned, return a zero-copy TypedData view
    // Otherwise fall back to a copy
    if (payloadLength < 4) {
      throw UnexpectedError('Bad typed list payload', offset: _offset);
    }
    final count = _readUint32();
    final byteLen = count * elemSize;
    final pad = payloadLength - 4 - byteLen;
    if (pad < 0 || pad > 7) {
      throw UnexpectedError('Typed list payload length mismatch',
          offset: _offset);
    }
    if (pad != 0) {
      _need(pad);
      _offset += pad;
    }
    _need(byteLen);
    final data =
        Uint8List.view(_bytes.buffer, _bytes.offsetInBytes + _offset, byteLen);
    final dataAbs = _bytes.offsetInBytes + _offset;
    _offset += byteLen;

    final aligned = (elemSize == 1) || ((dataAbs & (elemSize - 1)) == 0);
    if (aligned) {
      final o = data.offsetInBytes;
      switch (elemSize) {
        case 1:
          return Int8List.view(data.buffer, o, count);
        case 2:
          return signed
              ? Int16List.view(data.buffer, o, count)
              : Uint16List.view(data.buffer, o, count);
        case 4:
          return signed
              ? Int32List.view(data.buffer, o, count)
              : Uint32List.view(data.buffer, o, count);
        case 8:
          return signed
              ? Int64List.view(data.buffer, o, count)
              : Uint64List.view(data.buffer, o, count);
      }
    }

    switch (elemSize) {
      case 1:
        final out = Int8List(count);
        out.buffer
            .asUint8List(out.offsetInBytes, byteLen)
            .setRange(0, byteLen, data);
        return out;
      case 2:
        if (signed) {
          final out = Int16List(count);
          out.buffer
              .asUint8List(out.offsetInBytes, byteLen)
              .setRange(0, byteLen, data);
          return out;
        } else {
          final out = Uint16List(count);
          out.buffer
              .asUint8List(out.offsetInBytes, byteLen)
              .setRange(0, byteLen, data);
          return out;
        }
      case 4:
        if (signed) {
          final out = Int32List(count);
          out.buffer
              .asUint8List(out.offsetInBytes, byteLen)
              .setRange(0, byteLen, data);
          return out;
        } else {
          final out = Uint32List(count);
          out.buffer
              .asUint8List(out.offsetInBytes, byteLen)
              .setRange(0, byteLen, data);
          return out;
        }
      case 8:
        if (signed) {
          final out = Int64List(count);
          out.buffer
              .asUint8List(out.offsetInBytes, byteLen)
              .setRange(0, byteLen, data);
          return out;
        } else {
          final out = Uint64List(count);
          out.buffer
              .asUint8List(out.offsetInBytes, byteLen)
              .setRange(0, byteLen, data);
          return out;
        }
    }
    throw UnexpectedError('Unsupported elemSize $elemSize', offset: _offset);
  }

  dynamic _readTypedListFloat(
      int elemSize, int payloadLength, int endOfPayload) {
    // Same deal as ints, views when aligned, copies when not
    if (payloadLength < 4) {
      throw UnexpectedError('Bad typed list payload', offset: _offset);
    }
    final count = _readUint32();
    final byteLen = count * elemSize;
    final pad = payloadLength - 4 - byteLen;
    if (pad < 0 || pad > 7) {
      throw UnexpectedError('Typed list payload length mismatch',
          offset: _offset);
    }
    if (pad != 0) {
      _need(pad);
      _offset += pad;
    }
    _need(byteLen);
    final data =
        Uint8List.view(_bytes.buffer, _bytes.offsetInBytes + _offset, byteLen);
    final dataAbs = _bytes.offsetInBytes + _offset;
    _offset += byteLen;

    final aligned = (dataAbs & (elemSize - 1)) == 0;
    if (aligned) {
      final o = data.offsetInBytes;
      return elemSize == 4
          ? Float32List.view(data.buffer, o, count)
          : Float64List.view(data.buffer, o, count);
    }

    if (elemSize == 4) {
      final out = Float32List(count);
      out.buffer
          .asUint8List(out.offsetInBytes, byteLen)
          .setRange(0, byteLen, data);
      return out;
    } else {
      final out = Float64List(count);
      out.buffer
          .asUint8List(out.offsetInBytes, byteLen)
          .setRange(0, byteLen, data);
      return out;
    }
  }

  void _skip(int depth) {
    if (_offset >= _bytes.length) {
      throw UnexpectedError('Unexpected end of input', offset: _offset);
    }
    final int prefix = _bytes[_offset++];

    if (prefix <= 0x7F || prefix >= 0xE0) return;

    if (prefix >= 0xA0 && prefix <= 0xBF) {
      final len = prefix & 0x1F;
      _offset += len;
      _need(0);
      return;
    }
    if (prefix >= 0x90 && prefix <= 0x9F) {
      final len = prefix & 0x0F;
      for (int i = 0; i < len; i++) {
        _skip(depth + 1);
      }
      return;
    }
    if (prefix >= 0x80 && prefix <= 0x8F) {
      final len = prefix & 0x0F;
      for (int i = 0; i < len; i++) {
        _skip(depth + 1);
        _skip(depth + 1);
      }
      return;
    }

    switch (prefix) {
      case 0xC0:
      case 0xC2:
      case 0xC3:
        return;
      case 0xCC:
      case 0xD0:
        _offset += 1;
        _need(0);
        return;
      case 0xCD:
      case 0xD1:
        _offset += 2;
        _need(0);
        return;
      case 0xCE:
      case 0xD2:
      case 0xCA:
        _offset += 4;
        _need(0);
        return;
      case 0xCF:
      case 0xD3:
      case 0xCB:
        _offset += 8;
        _need(0);
        return;
      case 0xD4:
        _offset += 1 + 1;
        _need(0);
        return;
      case 0xD5:
        _offset += 1 + 2;
        _need(0);
        return;
      case 0xD6:
        _offset += 1 + 4;
        _need(0);
        return;
      case 0xD7:
        _offset += 1 + 8;
        _need(0);
        return;
      case 0xD8:
        _offset += 1 + 16;
        _need(0);
        return;

      case 0xD9:
        _offset += _readUint8();
        _need(0);
        return;
      case 0xDA:
        _offset += _readUint16();
        _need(0);
        return;
      case 0xDB:
        _offset += _readUint32();
        _need(0);
        return;

      case 0xC4:
        _offset += _readUint8();
        _need(0);
        return;
      case 0xC5:
        _offset += _readUint16();
        _need(0);
        return;
      case 0xC6:
        _offset += _readUint32();
        _need(0);
        return;

      case 0xDC:
        {
          final len = _readUint16();
          for (int i = 0; i < len; i++) {
            _skip(depth + 1);
          }
          return;
        }
      case 0xDD:
        {
          final len = _readUint32();
          for (int i = 0; i < len; i++) {
            _skip(depth + 1);
          }
          return;
        }
      case 0xDE:
        {
          final len = _readUint16();
          for (int i = 0; i < len; i++) {
            _skip(depth + 1);
            _skip(depth + 1);
          }
          return;
        }
      case 0xDF:
        {
          final len = _readUint32();
          for (int i = 0; i < len; i++) {
            _skip(depth + 1);
            _skip(depth + 1);
          }
          return;
        }

      case 0xC7:
        _offset += 1 + _readUint8();
        _need(0);
        return;
      case 0xC8:
        _offset += 1 + _readUint16();
        _need(0);
        return;
      case 0xC9:
        _offset += 1 + _readUint32();
        _need(0);
        return;

      default:
        throw UnsupportedError(
            'Unknown prefix for skip: 0x${prefix.toRadixString(16)} at $_offset');
    }
  }
}
