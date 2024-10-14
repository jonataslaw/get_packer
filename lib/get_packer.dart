library get_packer;

import 'dart:convert';
import 'dart:typed_data';

/// Custom exception for indicating data that's too large to process.
class BigDataException implements Exception {
  BigDataException(this.data);
  final dynamic data;

  @override
  String toString() => 'Data $data is too big to process';
}

/// The main interface for packing and unpacking data.
class GetPacker {
  /// Encodes the given value into a GetPacker format.
  static Uint8List pack(dynamic value) {
    final _Packer encoder = _Packer();
    encoder._encode(value);
    return encoder._takeBytes();
  }

  /// Decodes the given GetPacker-formatted bytes into Dart objects.
  static T unpack<T>(Uint8List bytes) {
    final _Unpacker decoder = _Unpacker(bytes);
    return decoder._decode();
  }
}

/// Mixin for classes that can be packed and unpacked.
mixin PackedModel {
  Uint8List pack() => GetPacker.pack(toJson());

  Map<String, dynamic> toJson();
  T fromJson<T extends PackedModel>(Map<String, dynamic> data);
}

/// Internal class for encoding data into GetPacker format.
class _Packer {
  final Uint8List _buffer = Uint8List(1024 * 8); // Start with 8KB buffer
  int _offset = 0;

  final ByteData _byteData = ByteData(8); // Reusable ByteData for numbers

  void _ensureBuffer(int length) {
    if (_offset + length > _buffer.length) {
      // Double the buffer size until it fits
      int newSize = _buffer.length * 2;
      while (_offset + length > newSize) {
        newSize *= 2;
      }
      final newBuffer = Uint8List(newSize);
      newBuffer.setRange(0, _offset, _buffer);
      _buffer.setAll(0, newBuffer);
    }
  }

  void _encode(dynamic value) {
    if (value == null) {
      _ensureBuffer(1);
      _buffer[_offset++] = 0xC0;
    } else if (value is bool) {
      _ensureBuffer(1);
      _buffer[_offset++] = value ? 0xC3 : 0xC2;
    } else if (value is int) {
      _encodeInt(value);
    } else if (value is double) {
      _encodeDouble(value);
    } else if (value is String) {
      _encodeString(value);
    } else if (value is Uint8List) {
      _encodeBinary(value);
    } else if (value is Iterable) {
      _encodeArray(value);
    } else if (value is Map) {
      _encodeMap(value);
    } else if (value is DateTime) {
      _encodeDateTime(value);
    } else if (value is BigInt) {
      _encodeBigInt(value);
    } else if (value is PackedModel) {
      _encode(value.toJson());
    } else {
      throw UnsupportedError('Unsupported type: ${value.runtimeType}');
    }
  }

  void _encodeInt(int value) {
    if (value >= 0 && value <= 0x7F) {
      _ensureBuffer(1);
      _buffer[_offset++] = value;
    } else if (value < 0 && value >= -32) {
      _ensureBuffer(1);
      _buffer[_offset++] = 0xE0 | (value + 32);
    } else if (value >= -128 && value <= 127) {
      _ensureBuffer(2);
      _buffer[_offset++] = 0xD0;
      _buffer[_offset++] = value & 0xFF;
    } else if (value >= -32768 && value <= 32767) {
      _ensureBuffer(3);
      _buffer[_offset++] = 0xD1;
      _byteData.setInt16(0, value, Endian.big);
      _buffer[_offset++] = _byteData.getUint8(0);
      _buffer[_offset++] = _byteData.getUint8(1);
    } else if (value >= -2147483648 && value <= 2147483647) {
      _ensureBuffer(5);
      _buffer[_offset++] = 0xD2;
      _byteData.setInt32(0, value, Endian.big);
      _buffer[_offset++] = _byteData.getUint8(0);
      _buffer[_offset++] = _byteData.getUint8(1);
      _buffer[_offset++] = _byteData.getUint8(2);
      _buffer[_offset++] = _byteData.getUint8(3);
    } else {
      _ensureBuffer(9);
      _buffer[_offset++] = 0xD3;
      _byteData.setInt64(0, value, Endian.big);
      for (int i = 0; i < 8; i++) {
        _buffer[_offset++] = _byteData.getUint8(i);
      }
    }
  }

  void _encodeDouble(double value) {
    _ensureBuffer(9);
    _buffer[_offset++] = 0xCB;
    _byteData.setFloat64(0, value, Endian.big);
    for (int i = 0; i < 8; i++) {
      _buffer[_offset++] = _byteData.getUint8(i);
    }
  }

  void _encodeString(String value) {
    final encoded = utf8.encode(value);
    final length = encoded.length;
    if (length <= 31) {
      _ensureBuffer(1 + length);
      _buffer[_offset++] = 0xA0 | length;
    } else if (length <= 0xFF) {
      _ensureBuffer(2 + length);
      _buffer[_offset++] = 0xD9;
      _buffer[_offset++] = length;
    } else if (length <= 0xFFFF) {
      _ensureBuffer(3 + length);
      _buffer[_offset++] = 0xDA;
      _byteData.setUint16(0, length, Endian.big);
      _buffer[_offset++] = _byteData.getUint8(0);
      _buffer[_offset++] = _byteData.getUint8(1);
    } else if (length <= 0xFFFFFFFF) {
      _ensureBuffer(5 + length);
      _buffer[_offset++] = 0xDB;
      _byteData.setUint32(0, length, Endian.big);
      for (int i = 0; i < 4; i++) {
        _buffer[_offset++] = _byteData.getUint8(i);
      }
    } else {
      throw BigDataException(value);
    }
    _ensureBuffer(length);
    _buffer.setRange(_offset, _offset + length, encoded);
    _offset += length;
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
      _byteData.setUint16(0, length, Endian.big);
      _buffer[_offset++] = _byteData.getUint8(0);
      _buffer[_offset++] = _byteData.getUint8(1);
    } else if (length <= 0xFFFFFFFF) {
      _ensureBuffer(5 + length);
      _buffer[_offset++] = 0xC6;
      _byteData.setUint32(0, length, Endian.big);
      for (int i = 0; i < 4; i++) {
        _buffer[_offset++] = _byteData.getUint8(i);
      }
    } else {
      throw BigDataException(data);
    }
    _ensureBuffer(length);
    _buffer.setRange(_offset, _offset + length, data);
    _offset += length;
  }

  void _encodeArray(Iterable iterable) {
    final length = iterable.length;
    if (length <= 0xF) {
      _ensureBuffer(1);
      _buffer[_offset++] = 0x90 | length;
    } else if (length <= 0xFFFF) {
      _ensureBuffer(3);
      _buffer[_offset++] = 0xDC;
      _byteData.setUint16(0, length, Endian.big);
      _buffer[_offset++] = _byteData.getUint8(0);
      _buffer[_offset++] = _byteData.getUint8(1);
    } else if (length <= 0xFFFFFFFF) {
      _ensureBuffer(5);
      _buffer[_offset++] = 0xDD;
      _byteData.setUint32(0, length, Endian.big);
      for (int i = 0; i < 4; i++) {
        _buffer[_offset++] = _byteData.getUint8(i);
      }
    } else {
      throw BigDataException(iterable);
    }
    for (final item in iterable) {
      _encode(item);
    }
  }

  void _encodeMap(Map<dynamic, dynamic> map) {
    final length = map.length;
    if (length <= 0xF) {
      _ensureBuffer(1);
      _buffer[_offset++] = 0x80 | length;
    } else if (length <= 0xFFFF) {
      _ensureBuffer(3);
      _buffer[_offset++] = 0xDE;
      _byteData.setUint16(0, length, Endian.big);
      _buffer[_offset++] = _byteData.getUint8(0);
      _buffer[_offset++] = _byteData.getUint8(1);
    } else if (length <= 0xFFFFFFFF) {
      _ensureBuffer(5);
      _buffer[_offset++] = 0xDF;
      _byteData.setUint32(0, length, Endian.big);
      for (int i = 0; i < 4; i++) {
        _buffer[_offset++] = _byteData.getUint8(i);
      }
    } else {
      throw BigDataException(map);
    }
    for (final key in map.keys) {
      _encode(key);
      _encode(map[key]);
    }
  }

  void _encodeDateTime(DateTime value) {
    _ensureBuffer(1 + 1 + 1 + 12);
    _buffer[_offset++] = 0xC7; // ext 8
    _buffer[_offset++] = 12; // 12 bytes of data
    _buffer[_offset++] = 0xFF; // Type for DateTime
    _byteData.setInt64(0, value.millisecondsSinceEpoch, Endian.big);
    for (int i = 0; i < 8; i++) {
      _buffer[_offset++] = _byteData.getUint8(i);
    }
    _byteData.setInt32(0, value.microsecond, Endian.big);
    for (int i = 0; i < 4; i++) {
      _buffer[_offset++] = _byteData.getUint8(i);
    }
  }

  void _encodeBigInt(BigInt value) {
    final isNegative = value.isNegative;
    final magnitudeBytes = _bigIntToBytes(value.abs());
    final length = 1 + magnitudeBytes.length; // 1 byte for sign

    int headerSize = 0;
    if (length <= 0xFF) {
      headerSize = 2;
      _ensureBuffer(headerSize + length);
      _buffer[_offset++] = 0xC7; // ext 8
      _buffer[_offset++] = length;
    } else if (length <= 0xFFFF) {
      headerSize = 3;
      _ensureBuffer(headerSize + length);
      _buffer[_offset++] = 0xC8; // ext 16
      _byteData.setUint16(0, length, Endian.big);
      _buffer[_offset++] = _byteData.getUint8(0);
      _buffer[_offset++] = _byteData.getUint8(1);
    } else if (length <= 0xFFFFFFFF) {
      headerSize = 5;
      _ensureBuffer(headerSize + length);
      _buffer[_offset++] = 0xC9; // ext 32
      _byteData.setUint32(0, length, Endian.big);
      for (int i = 0; i < 4; i++) {
        _buffer[_offset++] = _byteData.getUint8(i);
      }
    } else {
      throw BigDataException(value);
    }
    _buffer[_offset++] = 0x01; // Type code for BigInt
    _buffer[_offset++] = isNegative ? 0x01 : 0x00; // Sign byte
    _buffer.setRange(_offset, _offset + magnitudeBytes.length, magnitudeBytes);
    _offset += magnitudeBytes.length;
  }

  Uint8List _bigIntToBytes(BigInt value) {
    // Convert BigInt to minimal big-endian byte array
    int bytesNeeded = (value.bitLength + 7) >> 3;
    final result = Uint8List(bytesNeeded);
    BigInt temp = value;
    for (int i = bytesNeeded - 1; i >= 0; i--) {
      result[i] = (temp & BigInt.from(0xFF)).toInt();
      temp = temp >> 8;
    }
    return result;
  }

  Uint8List _takeBytes() => Uint8List.view(_buffer.buffer, 0, _offset);
}

/// Internal class for decoding GetPacker-formatted bytes.
class _Unpacker {
  _Unpacker(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;
  final ByteData _byteData = ByteData(8); // Reusable ByteData for numbers

  BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (var byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  dynamic _decode() {
    if (_offset >= _bytes.length) {
      throw StateError('Unexpected end of input');
    }

    final int prefix = _bytes[_offset++];

    if (prefix <= 0x7F) {
      return prefix; // Positive FixInt
    } else if (prefix >= 0xE0) {
      return prefix - 256; // Negative FixInt
    } else if (prefix >= 0xA0 && prefix <= 0xBF) {
      return _readString(prefix & 0x1F);
    } else if (prefix >= 0x90 && prefix <= 0x9F) {
      return _readArray(prefix & 0x0F);
    } else if (prefix >= 0x80 && prefix <= 0x8F) {
      return _readMap(prefix & 0x0F);
    } else {
      switch (prefix) {
        case 0xC0:
          return null;
        case 0xC2:
          return false;
        case 0xC3:
          return true;
        case 0xCC:
          return _readUint(1);
        case 0xCD:
          return _readUint(2);
        case 0xCE:
          return _readUint(4);
        case 0xCF:
          return _readUint(8);
        case 0xD0:
          return _readInt(1);
        case 0xD1:
          return _readInt(2);
        case 0xD2:
          return _readInt(4);
        case 0xD3:
          return _readInt(8);
        case 0xCA:
          return _readFloat();
        case 0xCB:
          return _readDouble();
        case 0xD9:
          return _readString(_readUint(1));
        case 0xDA:
          return _readString(_readUint(2));
        case 0xDB:
          return _readString(_readUint(4));
        case 0xC4:
          return _readBinary(_readUint(1));
        case 0xC5:
          return _readBinary(_readUint(2));
        case 0xC6:
          return _readBinary(_readUint(4));
        case 0xDC:
          return _readArray(_readUint(2));
        case 0xDD:
          return _readArray(_readUint(4));
        case 0xDE:
          return _readMap(_readUint(2));
        case 0xDF:
          return _readMap(_readUint(4));
        case 0xC7: // ext 8
          final length = _bytes[_offset++];
          return _readExt(length);
        case 0xC8: // ext 16
          final length = _readUint(2);
          return _readExt(length);
        case 0xC9: // ext 32
          final length = _readUint(4);
          return _readExt(length);
        default:
          throw UnsupportedError(
              'Unknown prefix: 0x${prefix.toRadixString(16)}');
      }
    }
  }

  int _readUint(int byteCount) {
    if (_offset + byteCount > _bytes.length) {
      throw StateError('Unexpected end of input');
    }
    int value = 0;
    for (int i = 0; i < byteCount; i++) {
      value = (value << 8) | _bytes[_offset++];
    }
    return value;
  }

  int _readInt(int byteCount) {
    if (_offset + byteCount > _bytes.length) {
      throw StateError('Unexpected end of input');
    }
    for (int i = 0; i < byteCount; i++) {
      _byteData.setUint8(i, _bytes[_offset++]);
    }
    int value = 0;
    switch (byteCount) {
      case 1:
        value = _byteData.getInt8(0);
        break;
      case 2:
        value = _byteData.getInt16(0, Endian.big);
        break;
      case 4:
        value = _byteData.getInt32(0, Endian.big);
        break;
      case 8:
        value = _byteData.getInt64(0, Endian.big);
        break;
    }
    return value;
  }

  double _readFloat() {
    if (_offset + 4 > _bytes.length) {
      throw StateError('Unexpected end of input');
    }
    for (int i = 0; i < 4; i++) {
      _byteData.setUint8(i, _bytes[_offset++]);
    }
    return _byteData.getFloat32(0, Endian.big);
  }

  double _readDouble() {
    if (_offset + 8 > _bytes.length) {
      throw StateError('Unexpected end of input');
    }
    for (int i = 0; i < 8; i++) {
      _byteData.setUint8(i, _bytes[_offset++]);
    }
    return _byteData.getFloat64(0, Endian.big);
  }

  String _readString(int length) {
    if (_offset + length > _bytes.length) {
      throw StateError('Unexpected end of input');
    }
    final str = utf8.decode(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return str;
  }

  Uint8List _readBinary(int length) {
    if (_offset + length > _bytes.length) {
      throw StateError('Unexpected end of input');
    }
    final result =
        Uint8List.view(_bytes.buffer, _bytes.offsetInBytes + _offset, length);
    _offset += length;
    return result;
  }

  List<dynamic> _readArray(int length) {
    final list = List<dynamic>.filled(length, null, growable: false);
    for (int i = 0; i < length; i++) {
      list[i] = _decode();
    }
    return list;
  }

  Map<dynamic, dynamic> _readMap(int length) {
    final map = <dynamic, dynamic>{};
    for (int i = 0; i < length; i++) {
      final key = _decode();
      final value = _decode();
      map[key] = value;
    }
    return map;
  }

  dynamic _readExt(int length) {
    if (_offset + length > _bytes.length) {
      throw StateError('Unexpected end of input');
    }
    final type = _bytes[_offset++];
    if (type == 0x01) {
      // BigInt type code
      if (length < 1) {
        throw StateError('Invalid length for BigInt ext');
      }
      final signByte = _bytes[_offset++];
      final isNegative = signByte == 0x01;
      final magnitudeLength = length - 1; // Subtract sign byte length
      final magnitudeBytes =
          Uint8List.sublistView(_bytes, _offset, _offset + magnitudeLength);
      _offset += magnitudeLength;
      final magnitude = _bytesToBigInt(magnitudeBytes);
      final value = isNegative ? -magnitude : magnitude;
      return value;
    } else if (type == 0xFF) {
      // DateTime type code
      if (length != 12) {
        throw UnsupportedError('Unexpected ext length for DateTime: $length');
      }
      final millisecondsSinceEpoch = _readInt(8);
      final microsecond = _readInt(4);
      return DateTime.fromMicrosecondsSinceEpoch(
        millisecondsSinceEpoch * 1000 + microsecond,
        isUtc: false,
      );
    } else {
      // Handle other ext types or throw an error
      final data = Uint8List.sublistView(_bytes, _offset, _offset + length - 1);
      _offset += length - 1;
      return {'type': type, 'data': data};
    }
  }
}
