import 'dart:typed_data';

import 'decoder/get_packer_decoder.dart';
import 'encoder/get_packer_encoder.dart';
import 'objects/get_packer_config.dart';

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
      {GetPackerConfig config = const GetPackerConfig()}) {
    final decoder = GetPackerDecoder(config: config);
    decoder.reset(bytes);
    return decoder.unpack<T>();
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
  T decode<T>(
    Uint8List bytes,
  ) {
    _decoder.reset(bytes);
    return _decoder.unpack<T>();
  }
}
