import 'get_packer_exception.dart';

class GetPackerDecodingException extends GetPackerException {
  const GetPackerDecodingException(
    super.code,
    super.message, {
    super.offset,
    super.details,
    super.stackTrace,
  }) : super(operation: 'decode');
}
