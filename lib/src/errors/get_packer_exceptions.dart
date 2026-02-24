/// Typed, structured exceptions thrown by `get_packer`.
///
/// These are intended to be *actionable*:
/// - Stable `code` strings for programmatic handling.
/// - Context fields like `offset`, `limit`, and `extType`.
/// - A compact `toString()` that avoids dumping huge payloads.
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

sealed class GetPackerException implements Exception {
  const GetPackerException(
    this.code,
    this.message, {
    this.operation,
    this.offset,
    this.details,
    this.stackTrace,
  });

  /// Stable, machine-readable identifier (e.g. `decode.truncated_input`).
  final String code;

  /// Human-readable message.
  final String message;

  /// Optional high-level area (e.g. `encode`, `decode`).
  final String? operation;

  /// Byte offset into the input (decode only).
  final int? offset;

  /// Extra structured context.
  final Map<String, Object?>? details;

  /// Stack trace for [cause], if available.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final b = StringBuffer();
    b.write('GetPackerException($code)');
    if (operation != null) b.write(' op=$operation');
    if (offset != null) b.write(' offset=$offset');
    b.write(': $message');

    final d = details;
    if (d != null && d.isNotEmpty) {
      b.write(' [');
      var i = 0;
      d.forEach((k, v) {
        if (i++ != 0) b.write(', ');
        b.write(k);
        b.write('=');
        b.write(v);
      });
      b.write(']');
    }

    return b.toString();
  }
}

class GetPackerEncodingException extends GetPackerException {
  const GetPackerEncodingException(
    super.code,
    super.message, {
    super.details,
    super.stackTrace,
  }) : super(operation: 'encode');
}

class GetPackerDecodingException extends GetPackerException {
  const GetPackerDecodingException(
    super.code,
    super.message, {
    super.offset,
    super.details,
    super.stackTrace,
  }) : super(operation: 'decode');
}

/// Thrown when the nesting depth exceeds `GetPackerConfig.maxDepth`.
class GetPackerMaxDepthExceededException extends GetPackerException {
  GetPackerMaxDepthExceededException({
    required String operation,
    required this.maxDepth,
    required this.depth,
    int? offset,
  }) : super(
          operation == 'encode'
              ? GetPackerErrorCodes.encodeMaxDepthExceeded
              : GetPackerErrorCodes.decodeMaxDepthExceeded,
          'Max depth exceeded ($maxDepth).',
          operation: operation,
          offset: offset,
          details: {
            'maxDepth': maxDepth,
            'depth': depth,
          },
        );

  final int maxDepth;
  final int depth;
}

/// Thrown when an input buffer ends before the decoder can read a full value.
class GetPackerTruncatedInputException extends GetPackerDecodingException {
  GetPackerTruncatedInputException({
    required this.neededBytes,
    required super.offset,
    required this.inputLength,
    String? context,
  }) : super(
          GetPackerErrorCodes.decodeTruncatedInput,
          context == null
              ? 'Unexpected end of input.'
              : 'Unexpected end of input while reading $context.',
          details: {
            'neededBytes': neededBytes,
            'inputLength': inputLength,
          },
        );

  final int neededBytes;

  final int inputLength;
}

/// Thrown when decoding a prefix byte that is not part of the supported wire format.
class GetPackerUnknownPrefixException extends GetPackerDecodingException {
  GetPackerUnknownPrefixException({
    required this.prefix,
    required int offset,
  }) : super(
          GetPackerErrorCodes.decodeUnknownPrefix,
          'Unknown prefix byte 0x${prefix.toRadixString(16)}.',
          offset: offset,
          details: {
            'prefix': prefix,
          },
        );

  final int prefix;
}

/// Thrown when an ext payload is malformed (wrong length, inconsistent fields, etc).
class GetPackerInvalidExtPayloadException extends GetPackerDecodingException {
  GetPackerInvalidExtPayloadException({
    required this.extType,
    required this.payloadLength,
    required int offset,
    required String reason,
    Map<String, Object?>? details,
  }) : super(
          GetPackerErrorCodes.decodeInvalidExtPayload,
          reason,
          offset: offset,
          details: {
            'extType': extType,
            'payloadLength': payloadLength,
            if (details != null) ...details,
          },
        );

  final int extType;
  final int payloadLength;
}

/// Thrown when a well-formed value is followed by unexpected bytes in a fixed-length ext.
class GetPackerTrailingBytesException extends GetPackerDecodingException {
  GetPackerTrailingBytesException({
    required int offset,
    required String context,
    Map<String, Object?>? details,
  }) : super(
          GetPackerErrorCodes.decodeTrailingBytes,
          'Trailing bytes after $context.',
          offset: offset,
          details: details,
        );
}

/// Thrown when an API expects one decoded type but a different one was produced.
class GetPackerTypeMismatchException extends GetPackerException {
  GetPackerTypeMismatchException({
    required String operation,
    required this.expected,
    required this.actual,
    int? offset,
  }) : super(
          GetPackerErrorCodes.decodeTypeMismatch,
          'Type mismatch: expected $expected, got $actual.',
          operation: operation,
          offset: offset,
          details: {
            'expected': expected,
            'actual': actual,
          },
        );

  final String expected;
  final String actual;
}

/// Thrown when an encoded value exceeds configured size limits.
class GetPackerLimitExceededException extends GetPackerEncodingException {
  GetPackerLimitExceededException({
    required this.limitName,
    required String message,
    this.limit,
    this.actual,
    this.unit,
    String? valueType,
    Map<String, Object?>? details,
  }) : super(
          GetPackerErrorCodes.encodeLimitExceeded,
          message,
          details: {
            'limitName': limitName,
            if (limit != null) 'limit': limit,
            if (actual != null) 'actual': actual,
            if (unit != null) 'unit': unit,
            if (valueType != null) 'valueType': valueType,
            if (details != null) ...details,
          },
        );

  final String limitName;
  final int? limit;
  final int? actual;
  final String? unit;
}

/// Thrown when attempting to encode a value of an unsupported runtime type.
class GetPackerUnsupportedTypeException extends GetPackerEncodingException {
  GetPackerUnsupportedTypeException({
    required this.valueType,
  }) : super(
          GetPackerErrorCodes.encodeUnsupportedType,
          'Unsupported type: $valueType.',
          details: {
            'valueType': valueType,
          },
        );

  final String valueType;
}
