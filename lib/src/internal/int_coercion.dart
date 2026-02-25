import '../enums/int_interop_mode.dart';
import 'numeric_runtime.dart';

@pragma('vm:prefer-inline')
dynamic uint64FromParts(
  int hi,
  int lo, {
  required bool isWeb,
  required IntInteropMode mode,
}) {
  final safe = hi <= 0x001FFFFF;
  final safeValue = hi * 4294967296 + lo;

  switch (mode) {
    case IntInteropMode.off:
      if (isWeb) {
        if (safe) return safeValue;
        return (BigInt.from(hi) << 32) | BigInt.from(lo);
      }
      if (hi <= 0x7FFFFFFF) {
        return safeValue;
      }
      return (BigInt.from(hi) << 32) | BigInt.from(lo);
    case IntInteropMode.promoteWideToBigInt:
    case IntInteropMode.requireBigIntForWide:
      if (safe) return safeValue;
      return (BigInt.from(hi) << 32) | BigInt.from(lo);
  }
}

@pragma('vm:prefer-inline')
dynamic int64FromParts(
  int hiU,
  int lo, {
  required bool isWeb,
  required IntInteropMode mode,
}) {
  final neg = (hiU & 0x80000000) != 0;
  final hiSigned = neg ? (hiU - 0x100000000) : hiU;

  final bool safe = !neg
      ? (hiU <= 0x001FFFFF)
      : ((hiU > 0xFFE00000) || (hiU == 0xFFE00000 && lo != 0));

  final safeValue = hiSigned * 4294967296 + lo;

  switch (mode) {
    case IntInteropMode.off:
      if (isWeb) {
        if (safe) return safeValue;
        return (BigInt.from(hiSigned) << 32) + BigInt.from(lo);
      }
      return safeValue;
    case IntInteropMode.promoteWideToBigInt:
    case IntInteropMode.requireBigIntForWide:
      if (safe) {
        return safeValue;
      }
      return (BigInt.from(hiSigned) << 32) + BigInt.from(lo);
  }
}

@pragma('vm:prefer-inline')
dynamic coerceWideInt(
  BigInt big, {
  required bool isWeb,
  required IntInteropMode mode,
}) {
  switch (mode) {
    case IntInteropMode.off:
      if (isWeb) {
        if (big >= kMinSafeJsBig && big <= kMaxSafeJsBig) {
          return bigIntToExactInt(big) ?? big;
        }
        return big;
      }
      if (big >= kMinInt64Big && big <= kMaxInt64Big) {
        return bigIntToExactInt(big) ?? big;
      }
      return big;
    case IntInteropMode.promoteWideToBigInt:
    case IntInteropMode.requireBigIntForWide:
      if (big >= kMinSafeJsBig && big <= kMaxSafeJsBig) {
        return bigIntToExactInt(big) ?? big;
      }
      return big;
  }
}
