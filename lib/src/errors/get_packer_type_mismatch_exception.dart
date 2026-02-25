import 'get_packer_error_codes.dart';
import 'get_packer_exception.dart';

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
