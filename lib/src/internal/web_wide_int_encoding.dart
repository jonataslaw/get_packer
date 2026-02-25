import '../enums/int_interop_mode.dart';
import '../objects/ext_type.dart';
import 'numeric_runtime.dart';

@pragma('vm:prefer-inline')
bool tryEncodeWebWideInt({
  required bool isWeb,
  required bool outsideNative64BitRange,
  required IntInteropMode mode,
  required int value,
  required void Function(int extType, Object value) encode,
}) {
  if (!isWeb || !outsideNative64BitRange) {
    return false;
  }

  if (mode == IntInteropMode.promoteWideToBigInt) {
    encode(ExtType.bigInt, value);
  } else {
    encode(ExtType.wideInt, value);
  }
  return true;
}

@pragma('vm:prefer-inline')
bool tryEncodeWebWideIntListAsArray({
  required bool isWeb,
  required int min,
  required BigInt bigMin,
  required BigInt bigMax,
  required List<int> list,
  required void Function(List<int> list) encodeAsArray,
}) {
  if (!isWeb) {
    return false;
  }

  final bool fitsUint64 = min >= 0 && bigMax <= kMaxUint64Big;
  final bool fitsInt64 = bigMin >= kMinInt64Big && bigMax <= kMaxInt64Big;
  if (fitsUint64 || fitsInt64) {
    return false;
  }

  encodeAsArray(list);
  return true;
}
