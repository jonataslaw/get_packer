/// Base exception type thrown by `get_packer`.
abstract class GetPackerException implements Exception {
  const GetPackerException(
    this.code,
    this.message, {
    this.operation,
    this.offset,
    this.details,
    this.stackTrace,
  });

  /// Stable, machine-readable identifier (e.g. `decode.truncated_input`).
  final String code;

  /// Human-readable message.
  final String message;

  /// Optional high-level area (e.g. `encode`, `decode`).
  final String? operation;

  /// Byte offset into the input (decode only).
  final int? offset;

  /// Extra structured context.
  final Map<String, Object?>? details;

  /// Stack trace for [cause], if available.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final b = StringBuffer();
    b.write('GetPackerException($code)');
    if (operation != null) b.write(' op=$operation');
    if (offset != null) b.write(' offset=$offset');
    b.write(': $message');

    final d = details;
    if (d != null && d.isNotEmpty) {
      b.write(' [');
      var i = 0;
      d.forEach((k, v) {
        if (i++ != 0) b.write(', ');
        b.write(k);
        b.write('=');
        b.write(v);
      });
      b.write(']');
    }

    return b.toString();
  }
}
