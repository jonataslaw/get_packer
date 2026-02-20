import 'dart:collection';
import 'dart:typed_data';

class BoolList extends ListBase<bool> {
  /// Bit-packed boolean list
  /// `List<bool>` is expensive in both size and decode time
  BoolList(this._length) : _bytes = Uint8List((_length + 7) >> 3);
  BoolList._(this._length, this._bytes);

  final int _length;

  @override
  int get length => _length;

  @override
  set length(int value) {
    throw UnsupportedError('BoolList has fixed length');
  }

  final Uint8List _bytes;

  @override
  bool operator [](int index) {
    RangeError.checkValidIndex(index, this);
    final byte = index >> 3;
    final bit = index & 7;
    return (_bytes[byte] & (1 << bit)) != 0;
  }

  @override
  void operator []=(int index, bool value) {
    RangeError.checkValidIndex(index, this);
    final byte = index >> 3;
    final bit = index & 7;
    final mask = 1 << bit;
    final b = _bytes[byte];
    _bytes[byte] = value ? (b | mask) : (b & ~mask);
  }

  Uint8List asBytesView() => _bytes;

  static BoolList fromPacked(Uint8List packed, int count) {
    final neededBytes = (count + 7) >> 3;
    if (packed.lengthInBytes < neededBytes) {
      throw ArgumentError('Packed data too small for $count bools');
    }

    return BoolList._(
      count,
      Uint8List.view(
        packed.buffer,
        packed.offsetInBytes,
        neededBytes,
      ),
    );
  }

  static BoolList fromList(List<bool> src) {
    final dst = BoolList(src.length);
    for (int i = 0; i < src.length; i++) {
      dst[i] = src[i];
    }
    return dst;
  }
}
