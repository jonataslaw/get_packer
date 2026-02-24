# get_packer

**Fast, compact binary serialization for Dart — with every type you actually use, built in.**

[![pub package](https://img.shields.io/pub/v/get_packer.svg)](https://pub.dev/packages/get_packer)
[![codecov](https://codecov.io/gh/jonataslaw/get_packer/graph/badge.svg?token=U4EJLE94VI)](https://codecov.io/gh/jonataslaw/get_packer)

---

## The problem everyone has (and patches around)

You serialize a `DateTime`. JSON turns it into a string.
You deserialize it. Now you parse the string back into a `DateTime`.
Everywhere. Every model. Forever.

You have a `Float32List` with 80,000 sensor readings.
JSON doesn't know what that is. It sees a list.
It encodes every float as a decimal string, one by one.
On decode, it reads the string back character by character and rebuilds the list element by element.

So you switch to MessagePack. Binary. Smaller. Faster.
Except MessagePack has exactly eight types: `null`, `bool`, `int`, `float`, `str`, `bin`, `array`, `map`.

No `DateTime`. No `Duration`. No `BigInt`. No `Uri`. No `Set`. No typed arrays.
You're back to writing the conversion yourself. **Except now it's in binary.**

And there's a structural problem you can't optimize away: the MessagePack spec mandates big-endian encoding. Your machine is little-endian. Every multi-byte number gets byte-swapped on encode _and_ decode — two full passes over your data, just to satisfy a portability requirement you may not need.

---

## The fix

```dart
final bytes = GetPacker.pack({
  'name': 'Alice',
  'createdAt': DateTime.now(),
  'readings': Float32List.fromList([1.1, 2.2, 3.3]),
});
// bytes is binary data. Store it, send it, whatever you like.

final map = GetPacker.unpack<Map>(bytes);
// DateTime comes back as DateTime.
// Float32List comes back as a zero-copy typed view.
// No conversion. No boilerplate.
```

`get_packer` handles this right, once:

- Every Dart type you actually use — first-class, no conversion layer
- Zero-copy typed arrays — the decoder hands you a view, not a copy
- Smaller payloads — binary, with smart numeric promotion
- Fast — 3–4× faster than MessagePack on plain collections, not even counting typed-data wins
- Safe by default — size caps, depth limits, typed exceptions

---

## Quick start

```bash
dart pub add get_packer
```

```dart
import 'package:get_packer/get_packer.dart';
```

### One-shot

```dart
final bytes = GetPacker.pack(myData);
final result = GetPacker.unpack<Map>(bytes);
```

### Reuse on hot paths

```dart
// Preallocated encoder + decoder, reused across calls.
final packer = GetPacker();

final bytes  = packer.encode(myObject);
final result = packer.decode<Map>(bytes);
```

### Encoder and decoder separately

```dart
final encoder = GetPackerEncoder();
final decoder = GetPackerDecoder();

final bytes = encoder.pack(value);
decoder.reset(bytes);
final result = decoder.unpack<MyType>();
```

---

## Supported types

| Dart type      | Wire encoding                                                |
| -------------- | ------------------------------------------------------------ |
| `null`         | 1-byte nil token                                             |
| `bool`         | 1-byte true/false token                                      |
| `int`          | 1–9 bytes, smallest signed/unsigned width that fits          |
| `double`       | 4 bytes when lossless float32, 8 bytes otherwise             |
| `String`       | length-prefixed UTF-8; ASCII fast path skips the encode step |
| `Uint8List`    | length-prefixed binary blob                                  |
| `DateTime`     | ext: 1-byte UTC flag + int64 microseconds since epoch        |
| `Duration`     | ext: int64 microseconds                                      |
| `BigInt`       | ext: sign byte + big-endian magnitude bytes                  |
| `Uri`          | ext: UTF-8 bytes                                             |
| `Set`          | ext: uint32 count + encoded elements                         |
| `Int8List`     | ext: zero-copy typed payload                                 |
| `Uint16List`   | ext: zero-copy typed payload                                 |
| `Int16List`    | ext: zero-copy typed payload                                 |
| `Uint32List`   | ext: zero-copy typed payload                                 |
| `Int32List`    | ext: zero-copy typed payload                                 |
| `Uint64List`   | ext: zero-copy typed payload                                 |
| `Int64List`    | ext: zero-copy typed payload                                 |
| `Float32List`  | ext: zero-copy typed payload                                 |
| `Float64List`  | ext: zero-copy typed payload                                 |
| `BoolList`     | ext: bit-packed (8× smaller than `List<bool>`)               |
| `List<int>`    | auto-promoted to smallest typed payload                      |
| `List<double>` | auto-promoted to float32/float64 payload                     |
| `List<bool>`   | auto-promoted to bit-packed `BoolList`                       |
| `Map`          | uint32 length + alternating key/value pairs                  |
| `Iterable`     | uint32 length + encoded elements                             |
| `PackedModel`  | see [Custom models](#custom-models) below                    |

---

## Zero-copy typed arrays

When you encode a `Float32List`, get_packer writes the raw bytes exactly as they sit in memory — host-endian, contiguous, no transformation. On decode, the decoder hands you a **typed view directly into the buffer**. The data doesn't move.

```dart
final encoded = GetPacker.pack({'readings': Float32List(1_000_000)});
final result  = GetPacker.unpack<Map>(encoded);

// result['readings'] is a Float32List view into `encoded`.
// Zero allocation. Zero copy.
```

MessagePack can't do this — the big-endian spec makes it structurally impossible on little-endian hardware.
JSON can't do it either — it has no concept of typed arrays.

**Ownership model:** the view is valid as long as the buffer lives. Copy it if you need to outlive the buffer.

```dart
// Use the view directly — valid while `encoded` is in scope:
final view = result['readings'] as Float32List;

// Or take ownership of the data:
final owned = Float32List.fromList(view);

// Or trim the encoder buffer on finish so the view owns its own memory:
final encoder = GetPackerEncoder(trimOnFinish: true);
// trimOnFinish calls buffer.sublist() after encoding,
// producing a minimal allocation the view can safely outlive.
```

---

## Numeric list promotion

`get_packer` inspects `List<int>` at encode time and picks the smallest typed payload automatically:

```dart
final ids = [1, 2, 3, 4, 5, 6, 7, 8]; // all values fit in uint8

GetPacker.pack(ids);
// → Uint8List payload: 8 bytes of data, zero-copy view on decode
//   instead of 8 individually-tagged integers
```

The same applies to `List<double>`: if every value survives a float32 roundtrip and `preferFloat32` is on (the default), the list is encoded as `Float32List` — half the bytes, zero-copy on decode.

Promotion kicks in once the list length crosses `numericListPromotionMinLength` (default: 8). Below that, the header overhead isn't worth it.

---

## Performance

These are real numbers, AOT-compiled on an Apple M1 Pro, Dart SDK 3.11, macOS 26.3. Source and reproduction instructions are in [`benchmark/`](benchmark/).

**Plain collections** — maps, strings, ints, bools, plain lists. No typed arrays. Everything all three libraries handle the same way. The fairest possible comparison.

```
Encode (large payload):         Decode (large payload):
  get_packer    801 MB/s          get_packer   9,265 MB/s
  msgpack        86 MB/s          msgpack         89 MB/s
  json           50 MB/s          json            82 MB/s
```

Up to 9× faster encoding and 100× faster decoding — even on the competition’s home turf.

**Complete data** — All of `Plain collections`, plus `DateTime`, `BigInt`, `Uint16List`, `Float32List`, `Uint8List` payloads.

```
Decode (large payload):
  get_packer   5,621,992 MB/s
  msgpack             40 MB/s
  json               106 MB/s
```

That number is real. When the buffer is already the data, there's almost nothing to do.

---

## Integer handling across runtimes

Dart's `int` is not one thing:

| Runtime              | `int` precision                                 | Bitwise op width |
| -------------------- | ----------------------------------------------- | ---------------- |
| Native VM / AOT      | 64-bit two's complement                         | 64 bits          |
| Web (dart2js / DDC)  | IEEE-754 double — exact only for `±(2^53−1)`    | 32 bits          |
| Web Wasm (dart2wasm) | WasmGC `i64` — same as native inside the module | 64 bits          |

Any integer outside `±9007199254740991` silently loses precision on JS targets. `get_packer` gives you three modes:

```dart
enum IntInteropMode {
  off,                  // default — handles wide ints automatically
  promoteWideToBigInt,  // wide values always come back as BigInt
  requireBigIntForWide, // encoding a wide int throws — catch bugs early
}
```

**`off` (default)** — On the VM: native 64-bit, full range. On the web: values within `±2^53−1` are native `int`, wider values decode as `BigInt`.

**`promoteWideToBigInt`** — Wide integers become `BigInt` everywhere, including on the VM. Use this if you need consistent types across platforms.

**`requireBigIntForWide`** — Encoding a wide `int` throws. Pass `BigInt` explicitly. Use this to catch precision bugs at the source.

```dart
// This throws at encode time:
GetPacker.pack(9007199254740993, config: GetPackerConfig(
  intInteropMode: IntInteropMode.requireBigIntForWide,
));

// This is fine:
GetPacker.pack(BigInt.parse('9007199254740993'), config: GetPackerConfig(
  intInteropMode: IntInteropMode.requireBigIntForWide,
));
```

**`DateTime` note:** stored as int64 microseconds since epoch. Safely within `±2^53−1` until approximately year 2255. `Duration` uses the same encoding — durations longer than ~285 years exceed the JS-safe range.

---

## Configuration

```dart
const config = GetPackerConfig(
  initialCapacity: 8 * 1024,         // encoder preallocates this many bytes
  preferFloat32: true,                // use float32 when lossless (default: on)
  allowMalformedUtf8: false,          // reject corrupt strings
  deterministicMaps: false,           // sort string-keyed maps for stable bytes
  maxDepth: 512,                      // guards against deeply nested inputs
  intInteropMode: IntInteropMode.off,
  maxBigIntMagnitudeBytes: 8 * 1024,
  numericListPromotionMinLength: 8,
  maxStringUtf8Bytes: 0xFFFFFFFF,
  maxBinaryBytes: 0xFFFFFFFF,
  maxArrayLength: 0xFFFFFFFF,
  maxMapLength: 0xFFFFFFFF,
  maxExtPayloadBytes: 0xFFFFFFFF,
);
```

**`deterministicMaps`** — Off by default (sorting has a cost). Turn it on for content-addressed storage, diffing, or tests that compare bytes directly. Only applies to maps with all-`String` keys.

**`preferFloat32`** — On by default. The encoder tests each `double` for lossless float32 roundtrip. Coordinates, unit normals, and ML weights usually pass. When they don't, float64 is used automatically.

---

## Safety

Lower the caps when ingesting untrusted data:

```dart
final safeConfig = GetPackerConfig(
  maxDepth: 32,
  maxArrayLength: 1024,
  maxStringUtf8Bytes: 64 * 1024,
  maxBigIntMagnitudeBytes: 64,
);
```

The built-in caps protect against stack overflows, unbounded `BigInt` allocations, and oversized collections. Two exception types cover everything:

All exceptions thrown by `get_packer` extend `GetPackerException` and include:

- `code`: stable string for programmatic handling
- `offset`: byte cursor for decode failures (when applicable)
- `details`: structured context (limits, prefix byte, ext type, etc)

Common exceptions:

| Exception                             | Meaning                                       |
| ------------------------------------- | --------------------------------------------- |
| `GetPackerLimitExceededException`     | A value exceeded a configured size cap        |
| `GetPackerTruncatedInputException`    | Input ended before a full value could be read |
| `GetPackerInvalidExtPayloadException` | Malformed ext payload                         |
| `GetPackerUnknownPrefixException`     | Unknown prefix byte in the payload            |
| `GetPackerMaxDepthExceededException`  | `maxDepth` exceeded                           |

```dart
try {
  final value = GetPacker.unpack(bytes, config: safeConfig);
} on GetPackerLimitExceededException catch (e) {
  // Oversized input — reject.
} on GetPackerDecodingException catch (e) {
  // Truncated/corrupt payload (often with an `offset`).
}

// Note: `BigDataException` and `UnexpectedError` still exist for compatibility,
// but are deprecated in v2 in favor of the structured exceptions above.
```

---

## Custom models

`PackedModel` is the hook for encoding your own classes. Implement it and get_packer delegates to your `toJson()` method at encode time, and calls your `fromJson()` constructor at decode time.

```dart
class User with PackedModel {
  final String name;
  final DateTime createdAt;

  const User({required this.name, required this.createdAt});

  // Called by the encoder. Return any get_packer-supported value.
  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'createdAt': createdAt,  // DateTime encoded natively — no string conversion
  };

  // Called by the decoder. Receives exactly what toJson() returned.
  factory User.fromJson(Map<String, dynamic> json) => User(
    name: json['name'] as String,
    createdAt: json['createdAt'] as DateTime,
  );
}

// Encode:
final bytes = GetPacker.pack(User(name: 'Alice', createdAt: DateTime.now()));

// Decode — provide the factory and the type is inferred automatically:
final user = GetPacker.unpack(bytes, fromJson: User.fromJson);
print(user.name); // Alice
print(user.createdAt); // DateTime object, not a string
```

The round-trip is fully typed. `DateTime` comes back as `DateTime`, not a string. No intermediate layer.

---

## Custom extension types

Unknown ext types come back as `ExtValue` rather than throwing:

```dart
class ExtValue {
  final int type;       // the ext type byte
  final Uint8List data; // raw payload
}
```

Use type bytes outside the reserved range to layer your own types:

| Byte   | Type          |
| ------ | ------------- |
| `0x01` | `BigInt`      |
| `0x02` | `Duration`    |
| `0x03` | `wideInt`     |
| `0x04` | `BoolList`    |
| `0x05` | `Uri`         |
| `0x06` | `Set`         |
| `0x07` | `DateTime`    |
| `0x10` | `Int8List`    |
| `0x11` | `Uint16List`  |
| `0x12` | `Int16List`   |
| `0x13` | `Uint32List`  |
| `0x14` | `Int32List`   |
| `0x15` | `Uint64List`  |
| `0x16` | `Int64List`   |
| `0x17` | `Float32List` |
| `0x18` | `Float64List` |

These are stable. Once written to disk, you're committed to them.

---

## Compatibility

get_packer is **not wire-compatible with MessagePack.** It uses a custom binary format optimized for Dart's type system and host-endian memory layout.

It's the right choice when both ends of the wire are Dart. If you're crossing language boundaries, JSON or MessagePack win on portability — and that's a perfectly valid reason to use them. Many production systems use get_packer internally and JSON at the edges. That's not a workaround. That's good system design.

---

## License

MIT — see [LICENSE](LICENSE).
