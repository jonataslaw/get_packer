import 'dart:typed_data';

import 'decoder/get_packer_decoder.dart';
import 'encoder/get_packer_encoder.dart';
import 'errors/get_packer_exceptions.dart';
import 'objects/get_packer_config.dart';

typedef ModelFromJson<T> = T Function(Map<String, dynamic> json);

class GetPacker {
  /// Convenience wrapper around the encoder/decoder.
  ///
  /// Use the static methods for one-offs. Use the instance APIs in hot paths to
  /// reuse buffers. For persisted blobs, consider `trimOnFinish`.
  static Uint8List pack(dynamic value,
      {GetPackerConfig config = const GetPackerConfig(),
      bool trimOnFinish = false}) {
    final encoder =
        GetPackerEncoder(config: config, trimOnFinish: trimOnFinish);
    return encoder.pack(value);
  }

  /// Decode a single value from a full buffer
  ///
  /// On the web, wide integers may come back as `BigInt` depending on config
  static T unpack<T>(Uint8List bytes,
      {GetPackerConfig config = const GetPackerConfig(),
      ModelFromJson<T>? fromJson}) {
    final decoder = GetPackerDecoder(config: config);
    decoder.reset(bytes);
    final value = decoder.unpack<dynamic>();
    return _decodeAs<T>(value, fromJson: fromJson);
  }

  /// Stateful packer
  ///
  /// Defaults to tight outputs; handy for persisted blobs.
  GetPacker({GetPackerConfig config = const GetPackerConfig()})
      : _encoder = GetPackerEncoder(config: config, trimOnFinish: true),
        _decoder = GetPackerDecoder(config: config);

  final GetPackerEncoder _encoder;

  final GetPackerDecoder _decoder;

  /// Encode using the cached encoder
  Uint8List encode(
    dynamic value,
  ) {
    return _encoder.pack(value);
  }

  /// Decode using the cached decoder
  T decode<T>(Uint8List bytes, {ModelFromJson<T>? fromJson}) {
    _decoder.reset(bytes);
    final value = _decoder.unpack<dynamic>();
    return _decodeAs<T>(value, fromJson: fromJson);
  }

  static T _decodeAs<T>(dynamic value, {ModelFromJson<T>? fromJson}) {
    if (fromJson == null) {
      return value as T;
    }
    if (value is! Map) {
      throw GetPackerTypeMismatchException(
        operation: 'decode',
        expected: 'Map',
        actual: value.runtimeType.toString(),
      );
    }
    return fromJson(Map<String, dynamic>.from(value));
  }
}
