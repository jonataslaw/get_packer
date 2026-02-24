import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:get_packer/get_packer.dart' as gp;
import 'package:msgpack_dart/msgpack_dart.dart' as msgp;

// =======================================
// Entry point
// =======================================
void main(List<String> args) async {
  print('--- get_packer ---');
  print(_runtimeSummary());

  final scenarios = [
    (
      name: 'generateSimple (plain collections)',
      gen: generateSimple,
      touchPath: 'nested/a',
      iters: iterationsForSimple,
    ),
    (
      name: 'generate (typed‑data heavy)',
      gen: generate,
      touchPath: 'meta/epoch',
      iters: iterationsFor,
    ),
  ];

  for (final scenario in scenarios) {
    print('\n${"=" * 50}');
    print('  Scenario: ${scenario.name}');
    print("=" * 50);

    for (final size in ScenarioSize.values) {
      final data = scenario.gen(size);
      final approx = _approxPayloadBytes(data);
      final gpCfg = bestGetPackerConfig(size);
      final gpCap = _nextPow2(approx + 64);

      final adapters = <Adapter>[
        GetPackerAdapter(cfg: gpCfg, initialCapacity: gpCap),
        MsgPackPlainAdapter(),
        JsonAdapter(),
      ];

      print('\n  Size: ${size.name}  ~${_fmtBytes(approx)} (raw estimate)');
      final pre = _preEncodeAll(data, adapters);
      _printSizes(pre);

      final it = scenario.iters(size);
      final rounds = 5;

      // Encode-only
      print('  Encode throughput (MB/s) [median of $rounds runs, $it iters]:');
      for (final ad in adapters) {
        final (mbps, seconds, ops, sink) =
            _timeEncodeMedian(data, ad, it, rounds);
        print(
          '    ${ad.name.padRight(12)} ${mbps.toStringAsFixed(1).padLeft(8)} MB/s  '
          '| ${_fmtOps(ops)} op/s  '
          '| time ${_fmtTime(seconds)}  | chk $sink',
        );
      }

      // Decode-only
      print('  Decode throughput (MB/s) [median of $rounds runs, $it iters]:');
      for (final ad in adapters) {
        final encoded = pre[ad.name]!;
        final (mbps, seconds, ops, sink) =
            _timeDecodeMedian(encoded, ad, it, rounds, scenario.touchPath);
        print(
          '    ${ad.name.padRight(12)} ${mbps.toStringAsFixed(1).padLeft(8)} MB/s  '
          '| ${_fmtOps(ops)} op/s  '
          '| time ${_fmtTime(seconds)}  | chk $sink',
        );
      }
    }
  }
}

// =======================================
// Scenario framework
// =======================================

enum ScenarioSize { small, medium, large }

Map<String, Object> generateSimple(ScenarioSize size) {
  final rnd = Random(123);

  switch (size) {
    case ScenarioSize.small:
      return {
        "id": rnd.nextInt(1 << 31),
        'title': "It's a lovely day in the neighborhood",
        'description': 'A short description with some unicode: こんにちは世界',
        "negativeDouble": -273.15,
        "negativeInt": -42,
        "boolean": true,
        "StringList": [
          'foo',
          'bar',
          'baz',
        ],
        "intList": [1, 2, 3, 4],
        "doubleList": [3.14, 2.718, 1.618, 0.5772, 1.414],
        "boolList": [true, false, true, false],
        "map": {
          'key1': 'value1',
          'key2': 'value2',
          'key3': 'value3',
        },
        "nested": {
          'a': 1,
          'b': [1.0, 2.0, 3.0],
          'c': {'x': 10, 'y': 20},
        },
      };
    case ScenarioSize.medium:
      return {
        "id": rnd.nextInt(1 << 31),
        'title': "Lorem ipsum dolor sit amet, consectetur adipiscing elit",
        'description':
            'A longer description with more unicode: こんにちは世界！これはテストです。',
        "negativeDouble": -273.15,
        "negativeInt": -42,
        "boolean": true,
        "StringList": List<String>.generate(100, (i) => '$i'),
        "intList": List<int>.generate(1000, (i) => i),
        "doubleList": List<double>.generate(1000, (i) => i * 0.1),
        "boolList": List<bool>.generate(1000, (i) => i % 2 == 0),
        "map": Map<String, int>.fromIterables(
          List<String>.generate(100, (i) => '$i'),
          List<int>.generate(100, (i) => i),
        ),
        "nested": {
          'a': 1,
          'b': [1.0, 2.0, 3.0],
          'c': {'x': 10, 'y': 20},
        },
      };
    case ScenarioSize.large:
      return {
        "id": rnd.nextInt(1 << 31),
        'title':
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " * 10,
        'description':
            'A much longer description with more unicode: こんにちは世界！これはテストです。' *
                10,
        "negativeDouble": -273.15,
        "negativeInt": -42,
        "boolean": true,
        "StringList": List<String>.generate(1000, (i) => '$i'),
        "intList": List<int>.generate(10000, (i) => i),
        "doubleList": List<double>.generate(100000, (i) => i * 0.13456),
        "boolList": List<bool>.generate(100000, (i) => i % 2 == 0),
        "map": Map<String, int>.fromIterables(
          List<String>.generate(1000, (i) => '$i'),
          List<int>.generate(1000, (i) => i),
        ),
        "nested": {
          'a': 1,
          'b': [1.0, 2.0, 3.0],
          'c': {'x': 10, 'y': 20},
        },
      };
  }
}

Map<String, Object> generate(ScenarioSize size) {
  final rnd = Random(123);

  switch (size) {
    case ScenarioSize.small:
      return {
        "id": rnd.nextInt(1 << 31),
        'bigInt': BigInt.one << 32,
        'title': _ascii(rnd, 24),
        'description': _unicode(rnd, 12),
        "typed": {
          'i16': _i16(rnd, 8 * 1024),
          'u16': _u16(rnd, 8 * 1024),
          'f32': _f32(rnd, 8 * 1024),
          'blob': _u8(rnd, 64 * 1024),
        },
        'labels': List<String>.generate(10, (_) => _ascii(rnd, 10)),
        'meta': {'epoch': 42, 'scale': -0.5},
        "ts": DateTime.now(),
        "dt": Duration(milliseconds: 123456789),
        "pi": 3.141592653589793,
        "scale": 0.33333334,
        "ok": true,
      };
    case ScenarioSize.medium:
      return {
        "id": rnd.nextInt(1 << 31),
        'bigInt': BigInt.one << 32,
        'title': _ascii(rnd, 48),
        'description': _unicode(rnd, 24),
        "typed": {
          'i16': _i16(rnd, 64 * 1024),
          'u16': _u16(rnd, 64 * 1024),
          'f32': _f32(rnd, 80 * 1024),
          'blob': _u8(rnd, 1 * 1024 * 1024),
        },
        'labels': List<String>.generate(10, (_) => _ascii(rnd, 20)),
        'meta': {'epoch': 1337, 'scale': -0.33333334},
        "ts": DateTime.now(),
        "dt": Duration(milliseconds: 123456789),
        "pi": 3.141592653589793,
        "scale": 0.33333334,
        "ok": true,
      };
    case ScenarioSize.large:
      return {
        "id": rnd.nextInt(1 << 31),
        'bigInt': BigInt.one << 32,
        'text': _ascii(rnd, 128),
        'description': _unicode(rnd, 48),
        "typed": {
          'u16_series': _u16(rnd, 1_000_000),
          'i16_series': _i16(rnd, 1_000_000),
          'f32_series': _f32(rnd, 500_000),
          'blob': _u8(rnd, 8_000_000),
        },
        'labels': List<String>.generate(10, (_) => _ascii(rnd, 40)),
        'meta': {'epoch': 2025, 'scale': -1.0},
        "ts": DateTime.now(),
        "dt": Duration(milliseconds: 123456789),
        "pi": 3.141592653589793,
        "scale": 0.33333334,
        "ok": true,
      };
  }
}

gp.GetPackerConfig bestGetPackerConfig(ScenarioSize size) {
  switch (size) {
    case ScenarioSize.small:
      return const gp.GetPackerConfig(
        initialCapacity: 64 * 1024,
      );
    case ScenarioSize.medium:
      return const gp.GetPackerConfig(
        initialCapacity: 2 * 1024 * 1024,
      );
    case ScenarioSize.large:
      return const gp.GetPackerConfig(
        initialCapacity: 16 * 1024 * 1024,
      );
  }
}

int iterationsFor(ScenarioSize size) {
  switch (size) {
    case ScenarioSize.small:
      return 300;
    case ScenarioSize.medium:
      return 60;
    case ScenarioSize.large:
      return 8;
  }
}

/// Simple payloads are smaller (no typed-data blobs), so we can
/// afford more iterations for stable timings.
int iterationsForSimple(ScenarioSize size) {
  switch (size) {
    case ScenarioSize.small:
      return 5000;
    case ScenarioSize.medium:
      return 300;
    case ScenarioSize.large:
      return 15;
  }
}

// =======================================
// Adapters
// =======================================

abstract class Adapter {
  String get name;
  Uint8List encode(Object value);
  Object? decode(Uint8List bytes);
}

//
class GetPackerAdapter implements Adapter {
  GetPackerAdapter({
    required this.cfg,
    required int initialCapacity,
  })  : _enc = gp.GetPackerEncoder(
          trimOnFinish: false,
          config: gp.GetPackerConfig(
            initialCapacity: initialCapacity,
            preferFloat32: cfg.preferFloat32,
            allowMalformedUtf8: cfg.allowMalformedUtf8,
            deterministicMaps: cfg.deterministicMaps,
            maxDepth: cfg.maxDepth,
            intInteropMode: cfg.intInteropMode,
            maxBigIntMagnitudeBytes: cfg.maxBigIntMagnitudeBytes,
          ),
        ),
        _dec = gp.GetPackerDecoder(config: cfg);

  final gp.GetPackerConfig cfg;
  final gp.GetPackerEncoder _enc;
  final gp.GetPackerDecoder _dec;

  @override
  String get name => 'get_packer';

  @override
  Uint8List encode(Object value) {
    return _enc.pack(value);
  }

  @override
  Object? decode(Uint8List bytes) {
    _dec.reset(bytes);
    return _dec.unpack<Object?>();
  }
}

class MsgPackPlainAdapter implements Adapter {
  final msgp.Serializer _enc = msgp.Serializer();

  @override
  String get name => 'msgpack';
  @override
  Uint8List encode(Object value) {
    _enc.encode(_project(value));
    return _enc.takeBytes();
  }

  @override
  Object? decode(Uint8List bytes) {
    return _restore(msgp.deserialize(bytes));
  }

  static Object? _project(Object? v) {
    if (v is DateTime) {
      return {'__date__': v.toIso8601String()};
    }
    if (v is Duration) {
      return {'__duration__': v.inMicroseconds};
    }
    if (v is BigInt) {
      return {'__bigint__': v.toString()};
    }
    if (v is List) {
      return v
          .map<Object?>((e) => _project(e as Object?))
          .toList(growable: false);
    }
    if (v is Map) {
      // msgpack can encode non-string keys, so we don't force everything to
      // strings here.  The previous implementation called `toString()` on
      // every key, which turned `1` into `'1'` and lost the original type.  We
      // simply recurse on the values and leave the key unchanged.
      return v.map((k, val) => MapEntry(k, _project(val as Object?)));
    }
    return v;
  }

  // Restore any sentinel values that were produced by [_project].
  //
  // The opposite of `project` and used only by the benchmarks; we need to
  // inspect maps that were generated by the projection and convert them back
  // to the original typed values.  Each sentinel is encoded as a one‑key
  // map, so the restore logic looks for those exact shapes.  Earlier we
  // mistakenly checked for *all* possible keys at once (e.g. `&&`), which meant
  // none of the restoration branches ever triggered.  The tests in
  // `benchmark_adapters_test.dart` guard against regression.
  static Object? _restore(dynamic v) {
    if (v is Map) {
      // individual sentinels are encoded in single-key maps, so look for
      // those first.  previously the code used `&&` across all keys which
      // meant no restoration ever happened; each _project call only emits one
      // marker.
      if (v.length == 1) {
        if (v.containsKey('__date__') && v['__date__'] is String) {
          return DateTime.parse(v['__date__'] as String);
        }
        if (v.containsKey('__duration__') && v['__duration__'] is int) {
          return Duration(microseconds: v['__duration__'] as int);
        }
        if (v.containsKey('__bigint__') && v['__bigint__'] is String) {
          return BigInt.parse(v['__bigint__'] as String);
        }
      }

      // not a sentinel, recurse into any nested structures
      return v.map((k, val) => MapEntry(k, _restore(val as Object?)));
    }
    if (v is List) {
      return v.map<Object?>(_restore).toList(growable: false);
    }
    return v;
  }
}

class JsonAdapter implements Adapter {
  @override
  String get name => 'json';

  @override
  Uint8List encode(Object value) {
    final projected = _project(value);
    return utf8.encode(jsonEncode(projected));
  }

  @override
  Object? decode(Uint8List bytes) {
    final s = utf8.decode(bytes);
    final decoded = jsonDecode(s);
    return _restore(decoded);
  }

  static Object? _project(Object? v) {
    if (v is DateTime) {
      return {'__date__': v.toIso8601String()};
    }
    if (v is Duration) {
      return {'__duration__': v.inMicroseconds};
    }
    if (v is Uint8List) {
      return {'__b64__': base64Encode(v)};
    }
    if (v is BigInt) {
      return {'__bigint__': v.toString()};
    }
    if (v is Int8List) return {'__t__': 'i8', 'data': (v as List).toList()};
    if (v is Uint16List) return {'__t__': 'u16', 'data': (v as List).toList()};
    if (v is Int16List) return {'__t__': 'i16', 'data': (v as List).toList()};
    if (v is Uint32List) return {'__t__': 'u32', 'data': (v as List).toList()};
    if (v is Int32List) return {'__t__': 'i32', 'data': (v as List).toList()};
    if (v is Float32List) return {'__t__': 'f32', 'data': (v as List).toList()};
    if (v is Float64List) return {'__t__': 'f64', 'data': (v as List).toList()};
    if (v is List) {
      return v
          .map<Object?>((e) => _project(e as Object?))
          .toList(growable: false);
    }
    if (v is Map) {
      return v
          .map((k, val) => MapEntry(k.toString(), _project(val as Object?)));
    }
    return v;
  }

  // Mirror of the JSON projection logic above.  The adapters used in the
  // benchmarks intentionally emit JSON-friendly maps with explicit sentinel
  // keys; this method reverses that transformation.  The earlier version had
  // the same "all keys required" bug, which meant restoration never happened
  // and benchmark decode time was artificially low.  The tests added under
  // `benchmark_adapters_test.dart` assert correct rounding on every supported
  // type.
  static Object? _restore(dynamic v) {
    if (v is Map) {
      if (v.length == 1) {
        // simple single-key sentinels first
        if (v.containsKey('__date__') && v['__date__'] is String) {
          return DateTime.parse(v['__date__'] as String);
        }
        if (v.containsKey('__duration__') && v['__duration__'] is int) {
          return Duration(microseconds: v['__duration__'] as int);
        }
        if (v.containsKey('__bigint__') && v['__bigint__'] is String) {
          return BigInt.parse(v['__bigint__'] as String);
        }
        if (v.containsKey('__b64__') && v['__b64__'] is String) {
          return Uint8List.fromList(base64Decode(v['__b64__'] as String));
        }
      }

      // typed arrays use a two-key structure (`__t__`/`data`), no other keys
      if (v.containsKey('__t__') &&
          v.containsKey('data') &&
          v['data'] is List) {
        final tag = v['__t__'] as String;
        final list = v['data'] as List;
        switch (tag) {
          case 'i8':
            return Int8List.fromList(list.cast<int>());
          case 'u16':
            return Uint16List.fromList(list.cast<int>());
          case 'i16':
            return Int16List.fromList(list.cast<int>());
          case 'u32':
            return Uint32List.fromList(list.cast<int>());
          case 'i32':
            return Int32List.fromList(list.cast<int>());
          case 'f32':
            return Float32List.fromList(list.cast<double>());
          case 'f64':
            return Float64List.fromList(list.cast<double>());
        }
      }

      // preserve other maps by recursing
      return v.map((k, val) => MapEntry(k, _restore(val as Object?)));
    }
    if (v is List) {
      return v.map<Object?>(_restore).toList(growable: false);
    }
    return v;
  }
}

// =======================================
// Benchmark engine
// =======================================

Map<String, Uint8List> _preEncodeAll(
  Map<String, Object> data,
  List<Adapter> adapters,
) {
  final pre = <String, Uint8List>{};
  for (final ad in adapters) {
    final raw = ad.encode(data);
    pre[ad.name] = Uint8List.fromList(raw);
  }
  return pre;
}

void _printSizes(Map<String, Uint8List> pre) {
  final order = pre.keys.toList();
  order.sort((a, b) => pre[a]!.length.compareTo(pre[b]!.length));
  print('  Payload sizes:');
  for (final k in order) {
    print('    ${k.padRight(12)} ${_fmtBytes(pre[k]!.length)}');
  }
}

int _touchByPath(Object? decoded, String path) {
  final parts = path.split('/');
  var cur = decoded;
  for (final p in parts) {
    if (cur is Map && cur.containsKey(p)) {
      cur = cur[p] as Object?;
    } else {
      return 0;
    }
  }
  // return a small, deterministic integer that is always >= 0.  we previously
  // XORed values which could produce a negative two's‑complement result when
  // interpreted as a signed `int`.  though the benchmark only uses the
  // result for a checksum, positive numbers make the printed `chk` column much
  // easier to read and compare across runs.
  if (cur is int) return (cur ^ 0x9E3779B97F4A7C15).abs();
  if (cur is List) return (cur.length ^ 0x85EBCA6B) & 0xFFFFFFFF;
  if (cur is String) return (cur.length ^ 0x27D4EB2D).abs();
  if (cur is bool) return cur ? 1 : 0;
  return 0;
}

(double, double, double, int) _timeEncodeMedian(
  Map<String, Object> data,
  Adapter ad,
  int iterations,
  int rounds,
) {
  for (var i = 0; i < 3; i++) {
    ad.encode(data);
  }

  final times = <double>[];
  int sink = 0;
  Uint8List? last;
  for (var r = 0; r < rounds; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      last = ad.encode(data);
      // avoid XOR cancellation; mix the length in a simple rolling hash.
      // keep the value positive by masking the low 63 bits with
      // `0x7FFFFFFFFFFFFFFF`.
      sink = (sink * 31 + last.length) & 0x7FFFFFFFFFFFFFFF;
    }
    sw.stop();
    times.add(sw.elapsedMicroseconds / 1e6);
  }
  var medianSec = _median(times);

  if (medianSec <= 0.0) {
    medianSec = 1e-9;
  }

  final totalBytes = (last?.length ?? 1) * iterations;
  final mbps = totalBytes / (1024 * 1024) / medianSec;
  final opsPerSec = iterations / medianSec;
  return (mbps, medianSec, opsPerSec, sink);
}

(double, double, double, int) _timeDecodeMedian(
  Uint8List encoded,
  Adapter ad,
  int iterations,
  int rounds,
  String touchPath,
) {
  for (var i = 0; i < 3; i++) {
    ad.decode(encoded);
  }

  final times = <double>[];
  int sink = 0;
  for (var r = 0; r < rounds; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      final obj = ad.decode(encoded);
      // use a linear congruential-style mix instead of XOR so a constant
      // touched value won't cancel out when the iteration count is even.
      // mask low 63 bits to keep the result positive (always >= 0).
      sink = (sink * 31 + _touchByPath(obj, touchPath)) & 0x7FFFFFFFFFFFFFFF;
    }
    sw.stop();
    times.add(sw.elapsedMicroseconds / 1e6);
  }
  var medianSec = _median(times);

  if (medianSec <= 0.0) {
    medianSec = 1e-9;
  }

  final totalBytes = encoded.length * iterations;
  final mbps = totalBytes / (1024 * 1024) / medianSec;
  final opsPerSec = iterations / medianSec;
  return (mbps, medianSec, opsPerSec, sink);
}

double _median(List<double> xs) {
  final a = xs.toList()..sort();
  final n = a.length;
  if (n.isOdd) return a[n >> 1];
  return 0.5 * (a[(n >> 1) - 1] + a[n >> 1]);
}

// =======================================
// Helpers
// =======================================

String _runtimeSummary() {
  final isWeb = identical(0, 0.0);
  final isAot = const String.fromEnvironment('dart.vm.product') == 'true';
  return 'Dart VM: ${isAot ? 'AOT/Release' : 'JIT/Debug'}  |  Web: $isWeb';
}

String _fmtBytes(int n) {
  const kb = 1024;
  const mb = 1024 * 1024;
  if (n >= mb) return '${(n / mb).toStringAsFixed(2)} MB';
  if (n >= kb) return '${(n / kb).toStringAsFixed(2)} KB';
  return '${n.toStringAsFixed(0)} B';
}

String _fmtTime(double s) {
  if (s < 0.01) return '${(s * 1000).toStringAsFixed(2)} ms';
  return '${s.toStringAsFixed(3)} s';
}

String _fmtOps(double ops) {
  return ops.toStringAsFixed(1);
}

int _nextPow2(int n) {
  var v = n <= 0 ? 1 : n - 1;
  v |= v >> 1;
  v |= v >> 2;
  v |= v >> 4;
  v |= v >> 8;
  v |= v >> 16;
  return v + 1;
}

int _approxPayloadBytes(Map<String, Object> data) {
  int sum = 0;
  void walk(Object? v) {
    if (v == null) {
      sum += 1;
      return;
    }
    if (v is Uint8List) {
      sum += v.length;
      return;
    }
    if (v is TypedData) {
      sum += v.lengthInBytes;
      return;
    }
    if (v is String) {
      sum += v.length;
      return;
    }
    if (v is num || v is bool) {
      sum += 8;
      return;
    }
    if (v is List) {
      for (final e in v) {
        walk(e as Object?);
      }
      return;
    }
    if (v is Map) {
      for (final e in v.entries) {
        sum += e.key.toString().length;
        walk(e.value as Object);
      }
      return;
    }
  }

  walk(data);
  return sum;
}

String _ascii(Random rnd, int len) {
  final codes = List<int>.generate(len, (_) => 0x20 + rnd.nextInt(95));
  return String.fromCharCodes(codes);
}

String _unicode(Random rnd, int len) {
  final buf = StringBuffer();
  for (var i = 0; i < len; i++) {
    if (rnd.nextInt(10) == 0) {
      final code = 0x1F600 + rnd.nextInt(80);
      buf.writeCharCode(0xD800 + ((code - 0x10000) >> 10));
      buf.writeCharCode(0xDC00 + ((code - 0x10000) & 0x3FF));
    } else {
      buf.writeCharCode(0x61 + rnd.nextInt(26));
    }
  }
  return buf.toString();
}

BigInt _bigIntFromBytes(Uint8List bytes, {required bool signed}) {
  BigInt result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  if (!signed) return result;
  return result;
}

BigInt randBig(Random rnd, int bits) {
  final bytes = Uint8List((bits + 7) >> 3);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  return _bigIntFromBytes(bytes, signed: false);
}

Uint8List _u8(Random rnd, int n) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = rnd.nextInt(256);
  }
  return out;
}

Int16List _i16(Random rnd, int n) {
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    out[i] = rnd.nextInt(65536) - 32768;
  }
  return out;
}

Uint16List _u16(Random rnd, int n) {
  final out = Uint16List(n);
  for (var i = 0; i < n; i++) {
    out[i] = rnd.nextInt(65536);
  }
  return out;
}

Float32List _f32(Random rnd, int n) {
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = (rnd.nextInt(2000) - 1000) / 4.0;
  }
  return out;
}
