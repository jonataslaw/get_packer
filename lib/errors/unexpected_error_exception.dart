/// Signals a malformed payload (or a bug in the encoder)
///
/// Byte offsets make corruption debugging less miserable
class UnexpectedError implements Exception {
  UnexpectedError(this.message, {this.offset});
  final String message;
  final int? offset;

  @override
  String toString() => offset == null
      ? 'Unexpected error: $message'
      : 'Unexpected error at byte $offset: $message';
}
