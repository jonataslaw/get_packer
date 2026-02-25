// JavaScript Numbers are IEEE-754 doubles, so ints outside ±(2^53-1)
// silently lose precision
// intInteropMode decides how strict we are about that
import 'dart:typed_data';

const int kMaxSafeJsInt = 9007199254740991;
const int kMinSafeJsInt = -9007199254740991;
final BigInt kMinInt64Big = -(BigInt.one << 63);
final BigInt kMaxInt64Big = (BigInt.one << 63) - BigInt.one;
final BigInt kMaxUint64Big = (BigInt.one << 64) - BigInt.one;
final BigInt kMask32 = (BigInt.one << 32) - BigInt.one;
final BigInt kMask8 = BigInt.from(0xFF);
final BigInt kMinSafeJsBig = BigInt.from(kMinSafeJsInt);
final BigInt kMaxSafeJsBig = BigInt.from(kMaxSafeJsInt);

/// Convert [big] to an [int] only if the conversion is exact.
///
/// Some runtimes can represent arbitrarily large integers as `int`, while others
/// effectively clamp/wrap or lose precision. This helper keeps decoding
/// lossless across runtimes.
int? bigIntToExactInt(BigInt big) {
  try {
    final i = big.toInt();
    return BigInt.from(i) == big ? i : null;
  } catch (_) {
    return null;
  }
}

// Fast runtime check, avoids pulling in dart:io just to branch
const bool kIsWeb = identical(0, 0.0);

// TypedData views are native-endian
// Stash this once so the hot path doesn't keep branching
final host = (() {
  final u16 = Uint16List(1);
  u16[0] = 0x0102;
  final b = u16.buffer.asUint8List();
  return (b[0] == 0x02) ? Endian.little : Endian.big;
})();
