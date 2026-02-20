import 'dart:typed_data';

import '../get_packer.dart';
import '../mixins/packed_model.dart';
import '../objects/get_packer_config.dart';

extension PackedModelCodec on PackedModel {
  /// Packs the JSON form.
  /// This keeps the binary format boring and makes model evolution easier.
  Uint8List pack({
    GetPackerConfig config = const GetPackerConfig(),
    bool trimOnFinish = false,
  }) =>
      GetPacker.pack(toJson(), config: config, trimOnFinish: trimOnFinish);
}
