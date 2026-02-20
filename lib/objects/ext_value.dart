import 'dart:typed_data';

class ExtValue {
  /// Raw extension payload
  ///
  /// You only get this when the decoder sees an unknown [ExtType]
  const ExtValue(this.type, this.data);
  final int type;
  final Uint8List data;

  @override
  String toString() =>
      'ExtValue(type: 0x${type.toRadixString(16)}, bytes: ${data.length})';
}
