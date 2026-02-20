/// A highly efficient serializer and deserializer for Dart.
///
/// This library provides tools to convert Dart objects into a compact
/// binary format and vice-versa. It's designed for high performance and
/// low memory overhead. It supports a wide range of standard Dart types not
/// supported by json encoder/decoder, like `DateTime` and `BigInt`, and
/// user-defined objects via the `PackedModel` mixin.
///
/// The serialization format is based on MessagePack, a binary format that is
/// more compact than JSON.
library get_packer;

import 'dart:convert';
import 'dart:typed_data';

/// Exception thrown when attempting to pack data that exceeds the supported
/// size limits of the MessagePack format.
///
/// For example, this can occur if a list, map, or string has more than
/// 2^32 - 1 elements.
class BigDataException implements Exception {
  BigDataException(this.data);
  final dynamic data;

  @override
  String toString() => 'Data $data is too big to process';
}

/// Exception thrown during unpacking when the byte data is malformed,
/// incomplete, or doesn't conform to the expected MessagePack format.
class UnexpectedError implements Exception {
  UnexpectedError(this.message);
  final String message;

  @override
  String toString() => 'Unexpected error: $message';
}

/// The main entry point for packing (serializing) and unpacking (deserializing) data.
///
/// This class provides static methods to handle the conversion between Dart objects
/// and their MessagePack binary representation.
class GetPacker {
  /// Serializes a given Dart `value` into a `Uint8List` using the MessagePack format.
  ///
  /// Supported types include `null`, `bool`, `int`, `double`, `String`, `Uint8List`,
  /// `Iterable` (List), `Map`, `DateTime`, `BigInt`, and objects using the `PackedModel` mixin.
  ///
  /// Throws `UnsupportedError` if the `value` is of a type that cannot be serialized.
  static Uint8List pack(dynamic value) {
    final _Packer encoder = _Packer();
    encoder._encode(value);
    return encoder._takeBytes();
  }

  /// Deserializes a `Uint8List` of MessagePack data back into a Dart object of type `T`.
  ///
  /// The method will infer the type based on the encoded data.
  ///
  /// Throws `UnexpectedError` if the byte data is invalid or incomplete.
  /// Throws `UnsupportedError` if the byte data contains an unknown type prefix.
  static T unpack<T>(Uint8List bytes) {
    final _Unpacker decoder = _Unpacker(bytes);
    return decoder._decode();
  }
}


/// Internal class responsible for the decoding (unpacking) process.
/// It reads from a `Uint8List` and reconstructs Dart objects.
class _Unpacker {
  _Unpacker(this._bytes);

  /// The byte data to be unpacked.
  final Uint8List _bytes;

  /// The current read position in the `_bytes`.
  int _offset = 0;

  /// A `ByteData` view over the bytes to facilitate reading multi-byte values.
  ByteData get _byteDataView => _bytes.buffer.asByteData(_bytes.offsetInBytes);

  /// Converts a `Uint8List` in big-endian format back to a `BigInt`.
  BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (var byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  /// Decodes the next object from the byte stream.
  ///
  /// This method reads the next byte (prefix) to determine the type and length
  /// of the data that follows, then dispatches to the appropriate `_read*` method.
  dynamic _decode() {
    if (_offset >= _bytes.length) {
      throw UnexpectedError('Unexpected end of input');
    }

    final int prefix = _bytes[_offset++];

    // positive fixint (0xxxxxxx)
    if (prefix <= 0x7F) {
      return prefix;
    }
    // negative fixint (111xxxxx)
    else if (prefix >= 0xE0) {
      return prefix - 256;
    }
    // fixstr (101xxxxx)
    else if (prefix >= 0xA0 && prefix <= 0xBF) {
      return _readString(prefix & 0x1F);
    }
    // fixarray (1001xxxx)
    else if (prefix >= 0x90 && prefix <= 0x9F) {
      return _readArray(prefix & 0x0F);
    }
    // fixmap (1000xxxx)
    else if (prefix >= 0x80 && prefix <= 0x8F) {
      return _readMap(prefix & 0x0F);
    }
    // Other types
    else {
      switch (prefix) {
        case 0xC0: // nil
          return null;
        case 0xC2: // false
          return false;
        case 0xC3: // true
          return true;
        case 0xCC: // uint 8
          return _readUint8();
        case 0xCD: // uint 16
          return _readUint16();
        case 0xCE: // uint 32
          return _readUint32();
        case 0xCF: // uint 64
          return _readUint64();
        case 0xD0: // int 8
          return _readInt8();
        case 0xD1: // int 16
          return _readInt16();
        case 0xD2: // int 32
          return _readInt32();
        case 0xD3: // int 64
          return _readInt64();
        case 0xCB: // float 64
          return _readDouble();
        case 0xD9: // str 8
          return _readString(_readUint8());
        case 0xDA: // str 16
          return _readString(_readUint16());
        case 0xDB: // str 32
          return _readString(_readUint32());
        case 0xC4: // bin 8
          return _readBinary(_readUint8());
        case 0xC5: // bin 16
          return _readBinary(_readUint16());
        case 0xC6: // bin 32
          return _readBinary(_readUint32());
        case 0xDC: // array 16
          return _readArray(_readUint16());
        case 0xDD: // array 32
          return _readArray(_readUint32());
        case 0xDE: // map 16
          return _readMap(_readUint16());
        case 0xDF: // map 32
          return _readMap(_readUint32());
        case 0xC7: // ext 8
          final length = _readUint8();
          return _readExt(length);
        case 0xC8: // ext 16
          final length = _readUint16();
          return _readExt(length);
        case 0xC9: // ext 32
          final length = _readUint32();
          return _readExt(length);
        default:
          throw UnsupportedError(
              'Unknown prefix: 0x${prefix.toRadixString(16)}');
      }
    }
  }

  int _readUint8() => _bytes[_offset++];
  int _readUint16() {
    final val = _byteDataView.getUint16(_offset, Endian.big);
    _offset += 2;
    return val;
  }

  int _readUint32() {
    final val = _byteDataView.getUint32(_offset, Endian.big);
    _offset += 4;
    return val;
  }

  int _readUint64() {
    final val = _byteDataView.getUint64(_offset, Endian.big);
    _offset += 8;
    return val;
  }

  int _readInt8() {
    final val = _byteDataView.getInt8(_offset);
    _offset++;
    return val;
  }

  int _readInt16() {
    final val = _byteDataView.getInt16(_offset, Endian.big);
    _offset += 2;
    return val;
  }

  int _readInt32() {
    final val = _byteDataView.getInt32(_offset, Endian.big);
    _offset += 4;
    return val;
  }

  int _readInt64() {
    final val = _byteDataView.getInt64(_offset, Endian.big);
    _offset += 8;
    return val;
  }

  double _readDouble() {
    final val = _byteDataView.getFloat64(_offset, Endian.big);
    _offset += 8;
    return val;
  }

  /// Reads a string of a given `length` from the buffer.
  String _readString(int length) {
    if (_offset + length > _bytes.length) {
      throw UnexpectedError('Unexpected end of input for string');
    }
    final view =
        Uint8List.view(_bytes.buffer, _bytes.offsetInBytes + _offset, length);
    final str = utf8.decode(view, allowMalformed: true);
    _offset += length;
    return str;
  }

  /// Reads a binary data block of a given `length` from the buffer.
  Uint8List _readBinary(int length) {
    if (_offset + length > _bytes.length) {
      throw UnexpectedError('Unexpected end of input for binary');
    }
    final result =
        Uint8List.view(_bytes.buffer, _bytes.offsetInBytes + _offset, length);
    _offset += length;
    return result;
  }

  /// Reads an array of a given `length` by recursively decoding each element.
  List<dynamic> _readArray(int length) {
    final list = List<dynamic>.filled(length, null, growable: false);
    for (int i = 0; i < length; i++) {
      list[i] = _decode();
    }
    return list;
  }

  /// Reads a map of a given `length` by recursively decoding each key-value pair.
  Map<dynamic, dynamic> _readMap(int length) {
    final map = <dynamic, dynamic>{};
    for (int i = 0; i < length; i++) {
      final key = _decode();
      final value = _decode();
      map[key] = value;
    }
    return map;
  }

  /// Reads an extension type with a given `payloadLength`.
  /// This handles custom types like `DateTime` and `BigInt`.
  dynamic _readExt(int payloadLength) {
    if (_offset + payloadLength > _bytes.length) {
      throw UnexpectedError('Unexpected end of input for ext type');
    }
    final type = _bytes[_offset++];
    final dataLength = payloadLength - 1;

    // Custom DateTime type
    if (type == 0xFF) {
      if (dataLength != 12) {
        throw UnexpectedError(
            'Unexpected data length for DateTime: $dataLength');
      }
      final millisecondsSinceEpoch = _readInt64();
      final microsecond = _readInt32();
      return DateTime.fromMicrosecondsSinceEpoch(
        millisecondsSinceEpoch * 1000 + microsecond,
        isUtc: false, // Assumes local time, adjust if UTC is needed.
      );
    }
    // Custom BigInt type
    else if (type == 0x01) {
      if (dataLength < 1) {
        throw StateError('Invalid data length for BigInt ext: $dataLength');
      }
      final signByte = _bytes[_offset++];
      final isNegative = signByte == 0x01;
      final magnitudeLength = dataLength - 1;
      final view = Uint8List.view(
          _bytes.buffer, _bytes.offsetInBytes + _offset, magnitudeLength);
      _offset += magnitudeLength;
      final magnitude = _bytesToBigInt(view);
      return isNegative ? -magnitude : magnitude;
    }
    // Fallback for unknown extension types
    else {
      final data = Uint8List.view(
          _bytes.buffer, _bytes.offsetInBytes + _offset, dataLength);
      _offset += dataLength;
      return {'type': type, 'data': data};
    }
  }
}
