import 'get_packer_encoding_exception.dart';
import 'get_packer_error_codes.dart';

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
