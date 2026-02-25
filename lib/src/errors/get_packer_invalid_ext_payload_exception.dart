import 'get_packer_decoding_exception.dart';
import 'get_packer_error_codes.dart';

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
