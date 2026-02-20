import 'dart:typed_data';

import '../objects/get_packer_config.dart';

mixin PackedModel {
  /// Packs the JSON form
  ///
  /// Keeps the binary format boring and makes model evolution easier
  Uint8List pack({GetPackerConfig config = const GetPackerConfig()}) =>
      GetPacker.pack(toJson(), config: config);

  Map<String, dynamic> toJson();
}
