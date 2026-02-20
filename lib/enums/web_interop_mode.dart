enum WebInteropMode {
  /// Act like a normal Dart codec
  ///
  /// On the web we may still decode to BigInt when the payload can't roundtrip
  /// through JS Numbers
  off,

  /// Prefer BigInt over lossy ints for wide values
  ///
  /// Mainly for web apps that want correctness without forcing callers
  /// to sprinkle BigInt everywhere
  promoteWideToBigInt,

  /// Refuse wide ints unless the caller uses BigInt
  ///
  /// Pick this when you want to catch accidental precision loss early
  requireBigIntForWide,
}
