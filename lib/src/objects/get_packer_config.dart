import '../enums/web_interop_mode.dart';

class GetPackerConfig {
  /// Knobs for trading size and speed vs strictness
  ///
  /// Defaults are tuned for storage payloads, small-ish objects with lots
  /// of strings and numeric lists
  const GetPackerConfig({
    this.initialCapacity = 8 * 1024,
    this.preferFloat32 = true,
    this.allowMalformedUtf8 = false,
    this.deterministicMaps = false,
    this.maxDepth = 512,
    this.webInteropMode = WebInteropMode.off,
    this.maxBigIntMagnitudeBytes = 8 * 1024,
    this.numericListPromotionMinLength = 8,
  });

  /// Prealloc for the encoder buffer
  /// Keeping this sane matters more than micro-optimizing growth
  final int initialCapacity;

  /// When true, encode doubles as float32 when it roundtrips exactly,
  /// It's a size win for many workloads
  final bool preferFloat32;

  /// Allow decoding invalid UTF-8 sequences
  /// Probably you only want this for ingesting legacy or corrupt data, don't enable casually
  final bool allowMalformedUtf8;

  /// Sort string-keyed maps so the bytes don't depend on insertion order.
  /// Only applies to maps with all-String keys.
  final bool deterministicMaps;

  /// Hard stop for nested arrays and maps
  /// This is here for attacker-controlled inputs and accidental recursion
  final int maxDepth;

  /// How to handle wide integers on the web
  final WebInteropMode webInteropMode;

  /// Caps BigInt payloads so we can't be tricked into allocating forever
  final int maxBigIntMagnitudeBytes;

  /// Don't bother promoting tiny numeric lists
  ///
  /// For small N, the header and heuristics cost more than the win
  final int numericListPromotionMinLength;
}
