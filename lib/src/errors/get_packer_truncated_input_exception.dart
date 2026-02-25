import 'get_packer_decoding_exception.dart';
import 'get_packer_error_codes.dart';

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
