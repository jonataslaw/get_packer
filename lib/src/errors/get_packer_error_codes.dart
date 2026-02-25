abstract final class GetPackerErrorCodes {
  static const encodeUnsupportedType = 'encode.unsupported_type';
  static const encodeMaxDepthExceeded = 'encode.max_depth_exceeded';
  static const encodeLimitExceeded = 'encode.limit_exceeded';

  static const decodeTruncatedInput = 'decode.truncated_input';
  static const decodeMaxDepthExceeded = 'decode.max_depth_exceeded';
  static const decodeUnknownPrefix = 'decode.unknown_prefix';
  static const decodeInvalidExtPayload = 'decode.invalid_ext_payload';
  static const decodeTrailingBytes = 'decode.trailing_bytes';
  static const decodeTypeMismatch = 'decode.type_mismatch';
}
