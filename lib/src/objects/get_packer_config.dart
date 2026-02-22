import '../enums/int_interop_mode.dart';

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
    this.intInteropMode = IntInteropMode.off,
    this.maxBigIntMagnitudeBytes = 8 * 1024,
    this.numericListPromotionMinLength = 8,
    this.maxStringUtf8Bytes = 0xFFFFFFFF,
    this.maxUriUtf8Bytes = 0xFFFFFFFF,
    this.maxBinaryBytes = 0xFFFFFFFF,
    this.maxArrayLength = 0xFFFFFFFF,
    this.maxMapLength = 0xFFFFFFFF,
    this.maxExtPayloadBytes = 0xFFFFFFFF,
  });

  /// Prealloc for the encoder buffer
  /// Keeping this sane matters more than micro-optimizing growth
  final int initialCapacity;

  /// When true, encode doubles as float32 when it roundtrips exactly.
  /// It's a size win for many workloads.
  final bool preferFloat32;

  /// Allow decoding invalid UTF-8 sequences
  /// Useful for ingesting legacy/corrupt data; keep this off by default.
  final bool allowMalformedUtf8;

  /// Sort string-keyed maps so the bytes don't depend on insertion order.
  /// Only applies to maps with all-String keys.
  final bool deterministicMaps;

  /// Hard stop for nested arrays and maps
  /// Guards against attacker-controlled inputs and accidental recursion.
  final int maxDepth;

  /// How to handle wide integers across runtimes
  final IntInteropMode intInteropMode;

  /// Caps BigInt payloads to avoid unbounded allocations.
  final int maxBigIntMagnitudeBytes;

  /// Skip promotion for tiny numeric lists.
  ///
  /// For small N, the header and heuristics cost more than the win
  final int numericListPromotionMinLength;

  /// Optional caps (default: wire-format u32 limits).
  /// Lower these to defend against pathological inputs and to make oversize
  /// branches testable without multi-GB allocations.
  final int maxStringUtf8Bytes;

  /// Max UTF-8 byte length for encoded URIs.
  final int maxUriUtf8Bytes;

  /// Max length for binary blobs.
  final int maxBinaryBytes;

  /// Max item count for arrays/iterables.
  final int maxArrayLength;

  /// Max entry count for maps.
  final int maxMapLength;

  /// Max ext payload length (excluding the 1-byte ext type tag).
  final int maxExtPayloadBytes;
}
