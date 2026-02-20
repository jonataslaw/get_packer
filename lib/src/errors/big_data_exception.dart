/// Guardrail for payloads that would blow up memory
///
/// These usually surface as runtime data issues, not programmer mistakes
class BigDataException implements Exception {
  BigDataException(this.data, {this.reason});
  final dynamic data;
  final String? reason;

  @override
  String toString() => reason == null
      ? 'Data $data is too big to process'
      : 'Data $data is too big: $reason';
}
