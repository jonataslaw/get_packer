import 'get_packer_encoding_exception.dart';
import 'get_packer_error_codes.dart';

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
