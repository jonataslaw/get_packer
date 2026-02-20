import 'dart:convert';
import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:get_packer/get_packer.dart';

final Map<String, dynamic> testData = {
  'nullValue': null,
  'boolean': true,
  'integer': 42,
  'negativeInteger': -42,
  // 'bigInteger': BigInt.from(0xFFFFFFFF), //jsonEncode does not support BigInt
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

  final GetPacker packer = GetPacker();

  @override
  void run() {
    final foo = packer.encode(testData);
    packer.decode(foo);
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
