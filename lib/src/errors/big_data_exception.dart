/// Thrown when an input exceeds configured size caps.
///
/// Typically this indicates unexpected data, not a programmer mistake.
class BigDataException implements Exception {
  BigDataException(this.data, {this.reason});
  final dynamic data;
  final String? reason;

  @override
  String toString() => reason == null
      ? 'Data $data is too big to process'
      : 'Data $data is too big: $reason';
}
