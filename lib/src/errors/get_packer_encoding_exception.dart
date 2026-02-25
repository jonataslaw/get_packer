import 'get_packer_exception.dart';

class GetPackerEncodingException extends GetPackerException {
  const GetPackerEncodingException(
    super.code,
    super.message, {
    super.details,
    super.stackTrace,
  }) : super(operation: 'encode');
}
