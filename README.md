# GetPacker

GetPacker is a high-performance serialization library for Dart, designed to efficiently pack and unpack data structures. It provides a fast and compact alternative to JSON encoding/decoding and MessagePack with no limitations (like DateTime objects).

[![Pub Version](https://img.shields.io/pub/v/get_packer)](https://pub.dev/packages/get_packer)
[![codecov](https://codecov.io/gh/jonataslaw/get_packer/graph/badge.svg?token=U4EJLE94VI)](https://codecov.io/gh/jonataslaw/get_packer)

## Features

- Fast encoding and decoding of variables
- Compact binary format, resulting in smaller payload sizes compared to JSON
- Support for various data types including:
  - null
  - booleans
  - integers (including large integers)
  - floating-point numbers
  - strings
  - binary data (Uint8List)
  - lists
  - maps
  - DateTime
  - BigInt
- Easy-to-use API
- Mixin support for custom objects

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  get_packer: ^2.0.0
```

Then run `dart pub get` or `flutter pub get` if you're using Flutter.

## Usage

### Basic Usage

```dart
import 'package:get_packer/get_packer.dart';

void main() {
  // Encoding
  final data = {
    'name': 'John Doe',
    'age': 30,
    'isStudent': false,
    'grades': [85, 90, 92],
  };

  final encoded = GetPacker.pack(data);

  // Decoding
  final decoded = GetPacker.unpack(encoded);

  print(decoded); // Output: {name: John Doe, age: 30, isStudent: false, grades: [85, 90, 92]}
}
```

### Using with Custom Objects

You can use the `PackedModel` mixin to easily serialize and deserialize custom objects:

```dart
class User with PackedModel {
  String name;
  int age;

  User(this.name, this.age);

  @override
  Map<String, dynamic> toJson() => {'name': name, 'age': age};

  @override
  static User fromJson<User extends PackedModel>(Map<String, dynamic> json) {
    return User(json['name'], json['age']);
  }
}

void main() {
  final user = User('Alice', 25);

  // Packing
  final packed = user.pack();

  // Unpacking
  final unpackedUser = User.fromJson(unpack(packed));

  print('${unpackedUser.name}, ${unpackedUser.age}'); // Output: Alice, 25
}
```

## Performance

GetPacker is designed to be fast and efficient. In benchmarks, it typically outperforms standard JSON encoding/decoding in both speed and size:

```dart
// Example benchmark results:
JSON Encode(RunTime): 191.99949000407997 us.
GetPacker Encode(RunTime): 140.41056438954482 us.

Size comparison:
JSON size: 1268 bytes
GetPacker size: 986 bytes
GetPacker is 22.24% smaller
```

In case you want to test it yourself, here is the benchmark code used:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:get_packer/get_packer.dart';

final Map<String, dynamic> testData = {
  'nullValue': null,
  'boolean': true,
  'integer': 42,
  'negativeInteger': -42,
  'double': 3.14159,
  'string': 'Hello, World!',
  'binary': Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
  'array': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  'map': {'key1': 'value1', 'key2': 'value2', 'key3': 'value3'},
  'nestedArray': [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
  ],
  'nestedMap': {
    'outer1': {'inner1': 'value1', 'inner2': 'value2'},
    'outer2': {'inner3': 'value3', 'inner4': 'value4'}
  },
  'mixedArray': [
    1,
    'two',
    3.0,
    true,
    null,
    {'key': 'value'}
  ],
  'complexObject': {
    'id': 1001,
    'name': 'Complex Object',
    'attributes': ['attr1', 'attr2', 'attr3'],
    'metadata': {
      'created': '2023-09-30T12:00:00Z',
      'updated': '2023-09-30T14:30:00Z',
      'tags': ['tag1', 'tag2', 'tag3']
    }
  },
  'longString':
      'This is a much longer string that contains multiple sentences. '
          'It can be used to test how the system handles larger text inputs. '
          'The string can contain various characters and punctuation marks!',
  // 'dateTime': DateTime.now(), //jsonEncode does not support DateTime
  'largeInteger': 1234567890123456789,
  'negativeDouble': -273.15,
  'emptyStructures': {'emptyArray': [], 'emptyMap': {}, 'emptyString': ''},
  'deeplyNestedStructure': {
    'level1': {
      'level2': {
        'level3': {
          'level4': {'level5': 'Deep value'}
        }
      }
    }
  },
  'repeatingData': List.generate(
      5,
      (index) =>
          {'id': index, 'name': 'Item ${index + 1}', 'isEven': index % 2 == 0}),
};

class JsonEncodeBenchmark extends BenchmarkBase {
  JsonEncodeBenchmark() : super('JSON Encode');

  @override
  void run() {
    final foo = jsonEncode(testData);
    jsonDecode(foo);
  }
}

class GetPackerEncodeBenchmark extends BenchmarkBase {
  GetPackerEncodeBenchmark() : super('GetPacker Encode');

  @override
  void run() {
    final foo = GetPacker.pack(testData);
    GetPacker.unpack(foo);
  }
}

void main() {
  JsonEncodeBenchmark().report();
  GetPackerEncodeBenchmark().report();

  // Run multiple times for more accurate results
  print('\nRunning multiple iterations:');
  for (int i = 0; i < 5; i++) {
    print('\nIteration ${i + 1}:');
    JsonEncodeBenchmark().report();
    GetPackerEncodeBenchmark().report();
  }

  // Compare sizes
  final jsonSize = utf8.encode(jsonEncode(testData)).length;
  final getPackerSize = GetPacker.pack(testData).length;

  print('\nSize comparison:');
  print('JSON size: $jsonSize bytes');
  print('GetPacker size: $getPackerSize bytes');
  print('Size difference: ${(jsonSize - getPackerSize)} bytes');
  print(
      'GetPacker is ${((jsonSize - getPackerSize) / jsonSize * 100).toStringAsFixed(2)}% smaller');
}
```

## Note

  - GetPacker uses a custom binary format and IS NOT COMPATIBLE with MessagePack.
  - GetPacker always preserves integer values on the wire. When decoding, it returns an `int` only if the value is exactly representable as an `int` on the current runtime; otherwise it returns a `BigInt`.
  - Upgrade note for production databases using it: values previously encoded as unsigned 64-bit integers above `2^63-1` may have decoded as `int` on older runtimes, but will decode as `BigInt` on Dart 3.11+ (it is not our fault, the Dart numeric system changed in this release). The numeric value is preserved; only the Dart type can change.
  - On the web, `intInteropMode` controls whether values outside JavaScript’s safe integer range are returned as `BigInt`.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
