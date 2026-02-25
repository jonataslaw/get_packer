import 'get_packer_decoding_exception.dart';
import 'get_packer_error_codes.dart';

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
