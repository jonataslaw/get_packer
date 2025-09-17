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

/// A mixin that adds `pack()` functionality to custom model classes.
///
/// Classes using this mixin must implement a `toJson()` method that returns a
/// `Map<String, dynamic>`, which can then be serialized to MessagePack format.
mixin PackedModel {
  /// Packs the model object into a `Uint8List`.
  ///
  /// This is achieved by first converting the object to a map using `toJson()`
  /// and then packing the resulting map.
  Uint8List pack() => GetPacker.pack(toJson());

  /// Abstract method that must be implemented to provide a serializable
  /// map representation of the object.
  Map<String, dynamic> toJson();
}

/// Internal class responsible for the encoding (packing) process.
/// It maintains a buffer and writes data according to the MessagePack specification.
class _Packer {
  /// The underlying buffer where serialized data is written.
  /// It starts with an initial size and grows dynamically as needed.
  Uint8List _buffer = Uint8List(1024 * 8);

  /// The current write position in the `_buffer`.
  int _offset = 0;

  /// A `ByteData` view over the buffer to facilitate writing multi-byte values.
  ByteData get _byteDataView => _buffer.buffer.asByteData();

  /// Ensures that the buffer has enough space to write `length` more bytes.
  ///
  /// If the buffer is too small, it is replaced with a new buffer of double the size,
  /// and the existing data is copied over.
  void _ensureBuffer(int length) {
    if (_offset + length > _buffer.length) {
      final newBuffer = Uint8List(_buffer.length * 2);
      newBuffer.setRange(0, _offset, _buffer);
      _buffer = newBuffer;
    }
  }

  /// Encodes a Dart `value` into the buffer.
  ///
  /// This method acts as a dispatcher, calling the appropriate `_encode*` method
  /// based on the runtime type of the `value`.
  void _encode(dynamic value) {
    if (value == null) {
      // nil format
      _ensureBuffer(1);
      _buffer[_offset++] = 0xC0;
    } else if (value is bool) {
      // bool format
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
      // If the object is a PackedModel, convert it to a map and encode the map.
      _encode(value.toJson());
    } else {
      throw UnsupportedError('Unsupported type: ${value.runtimeType}');
    }
  }

  /// Encodes an integer using the most compact representation possible.
  void _encodeInt(int value) {
    if (value >= 0 && value <= 0x7F) {
      // positive fixint
      _ensureBuffer(1);
      _buffer[_offset++] = value;
    } else if (value < 0 && value >= -32) {
      // negative fixint
      _ensureBuffer(1);
      _buffer[_offset++] = 0xE0 | (value + 32);
    } else if (value >= -128 && value <= 127) {
      // int 8
      _ensureBuffer(2);
      _buffer[_offset++] = 0xD0;
      _byteDataView.setInt8(_offset, value);
      _offset++;
    } else if (value >= -32768 && value <= 32767) {
      // int 16
      _ensureBuffer(3);
      _buffer[_offset++] = 0xD1;
      _byteDataView.setInt16(_offset, value, Endian.big);
      _offset += 2;
    } else if (value >= -2147483648 && value <= 2147483647) {
      // int 32
      _ensureBuffer(5);
      _buffer[_offset++] = 0xD2;
      _byteDataView.setInt32(_offset, value, Endian.big);
      _offset += 4;
    } else {
      // int 64
      _ensureBuffer(9);
      _buffer[_offset++] = 0xD3;
      _byteDataView.setInt64(_offset, value, Endian.big);
      _offset += 8;
    }
  }

  /// Encodes a 64-bit double-precision floating-point number.
  void _encodeDouble(double value) {
    // float 64
    _ensureBuffer(9);
    _buffer[_offset++] = 0xCB;
    _byteDataView.setFloat64(_offset, value, Endian.big);
    _offset += 8;
  }

  /// Encodes a string after converting it to UTF-8 bytes.
  void _encodeString(String value) {
    final encoded = utf8.encode(value);
    final length = encoded.length;

    if (length <= 31) {
      // fixstr
      _ensureBuffer(1 + length);
      _buffer[_offset++] = 0xA0 | length;
    } else if (length <= 0xFF) {
      // str 8
      _ensureBuffer(2 + length);
      _buffer[_offset++] = 0xD9;
      _buffer[_offset++] = length;
    } else if (length <= 0xFFFF) {
      // str 16
      _ensureBuffer(3 + length);
      _buffer[_offset++] = 0xDA;
      _byteDataView.setUint16(_offset, length, Endian.big);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      // str 32
      _ensureBuffer(5 + length);
      _buffer[_offset++] = 0xDB;
      _byteDataView.setUint32(_offset, length, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(value);
    }
    _buffer.setRange(_offset, _offset + length, encoded);
    _offset += length;
  }

  /// Encodes a `Uint8List` as binary data.
  void _encodeBinary(Uint8List data) {
    final length = data.length;
    if (length <= 0xFF) {
      // bin 8
      _ensureBuffer(2 + length);
      _buffer[_offset++] = 0xC4;
      _buffer[_offset++] = length;
    } else if (length <= 0xFFFF) {
      // bin 16
      _ensureBuffer(3 + length);
      _buffer[_offset++] = 0xC5;
      _byteDataView.setUint16(_offset, length, Endian.big);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      // bin 32
      _ensureBuffer(5 + length);
      _buffer[_offset++] = 0xC6;
      _byteDataView.setUint32(_offset, length, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(data);
    }
    _buffer.setRange(_offset, _offset + length, data);
    _offset += length;
  }

  /// Encodes an `Iterable` (e.g., a List) by encoding its length followed by each element.
  void _encodeArray(Iterable iterable) {
    final length = iterable.length;
    if (length <= 0xF) {
      // fixarray
      _ensureBuffer(1);
      _buffer[_offset++] = 0x90 | length;
    } else if (length <= 0xFFFF) {
      // array 16
      _ensureBuffer(3);
      _buffer[_offset++] = 0xDC;
      _byteDataView.setUint16(_offset, length, Endian.big);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      // array 32
      _ensureBuffer(5);
      _buffer[_offset++] = 0xDD;
      _byteDataView.setUint32(_offset, length, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(iterable);
    }
    // Encode each item in the iterable.
    for (final item in iterable) {
      _encode(item);
    }
  }

  /// Encodes a `Map` by encoding its length followed by each key-value pair.
  void _encodeMap(Map<dynamic, dynamic> map) {
    final length = map.length;
    if (length <= 0xF) {
      // fixmap
      _ensureBuffer(1);
      _buffer[_offset++] = 0x80 | length;
    } else if (length <= 0xFFFF) {
      // map 16
      _ensureBuffer(3);
      _buffer[_offset++] = 0xDE;
      _byteDataView.setUint16(_offset, length, Endian.big);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      // map 32
      _ensureBuffer(5);
      _buffer[_offset++] = 0xDF;
      _byteDataView.setUint32(_offset, length, Endian.big);
      _offset += 4;
    } else {
      throw BigDataException(map);
    }
    // Encode each key-value pair.
    for (final entry in map.entries) {
      _encode(entry.key);
      _encode(entry.value);
    }
  }

  /// Encodes a `DateTime` object using a custom extension type.
  ///
  /// Format: `ext 8` with type `0xFF`.
  /// Payload: 12 bytes (8 for millisecondsSinceEpoch, 4 for microsecond).
  void _encodeDateTime(DateTime value) {
    const int payloadLength = 12; // 8 bytes for int64, 4 bytes for int32
    _ensureBuffer(
        1 + 1 + 1 + payloadLength); // ext8 prefix + length + type + payload
    _buffer[_offset++] = 0xC7; // ext 8
    _buffer[_offset++] = payloadLength + 1; // Payload length (type + data)
    _buffer[_offset++] = 0xFF; // Custom type for DateTime
    _byteDataView.setInt64(_offset, value.millisecondsSinceEpoch, Endian.big);
    _offset += 8;
    _byteDataView.setInt32(_offset, value.microsecond, Endian.big);
    _offset += 4;
  }

  /// Encodes a `BigInt` object using a custom extension type.
  ///
  /// Format: `ext 8/16/32` with type `0x01`.
  /// Payload: 1 byte for sign (0x00 for positive, 0x01 for negative) followed
  /// by the big-endian bytes of the number's absolute value.
  void _encodeBigInt(BigInt value) {
    final isNegative = value.isNegative;
    final magnitudeBytes = _bigIntToBytes(value.abs());

    // Payload consists of a sign byte and the magnitude bytes.
    final payloadLength = 1 + magnitudeBytes.length;
    final totalLength = 1 + payloadLength; // type + sign + magnitude

    _ensureBuffer(
        5 + totalLength); // Max possible header size (ext32) + payload

    if (totalLength <= 0xFF) {
      _buffer[_offset++] = 0xC7; // ext 8
      _buffer[_offset++] = totalLength;
    } else if (totalLength <= 0xFFFF) {
      _buffer[_offset++] = 0xC8; // ext 16
      _byteDataView.setUint16(_offset, totalLength, Endian.big);
      _offset += 2;
    } else if (totalLength <= 0xFFFFFFFF) {
      _buffer[_offset++] = 0xC9; // ext 32
      _byteDataView.setUint32(_offset, totalLength, Endian.big);
      _offset += 4;
    }
    _buffer[_offset++] = 0x01; // Custom type for BigInt
    _buffer[_offset++] = isNegative ? 0x01 : 0x00; // Sign byte
    _buffer.setRange(_offset, _offset + magnitudeBytes.length, magnitudeBytes);
    _offset += magnitudeBytes.length;
  }

  /// Converts a non-negative `BigInt` to a `Uint8List` in big-endian format.
  Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List(0);
    int bytesNeeded = (value.bitLength + 7) >> 3;
    final result = Uint8List(bytesNeeded);
    BigInt temp = value;
    for (int i = bytesNeeded - 1; i >= 0; i--) {
      result[i] = (temp & BigInt.from(0xFF)).toInt();
      temp = temp >> 8;
    }
    return result;
  }

  /// Returns a final `Uint8List` containing the serialized data.
  /// This creates a view of the buffer with the correct length.
  Uint8List _takeBytes() => Uint8List.view(_buffer.buffer, 0, _offset);
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
