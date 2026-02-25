import 'get_packer_decoding_exception.dart';
import 'get_packer_error_codes.dart';

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
