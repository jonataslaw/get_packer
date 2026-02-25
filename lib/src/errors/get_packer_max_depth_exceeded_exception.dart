import 'get_packer_error_codes.dart';
import 'get_packer_exception.dart';

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
