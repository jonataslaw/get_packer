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
  print(encoded);
  // Output: [132, 164, 110, 97, 109, 101, 168, 74, 111, 104, 110, 32, 68, 111, 101, 163, 97, 103, 101, 30, 169, 105, 115, 83, 116, 117, 100, 101, 110, 116, 194, 166, 103, 114, 97, 100, 101, 115, 147, 85, 90, 92]


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

  factory User.fromJson(Map<String, dynamic> json) {
    return User(json['name'], json['age']);
  }
}

void main() {
  final user = User('Alice', 25);

  // Packing
  final packed = user.pack();

  // Unpacking
  final unpackedUser = GetPacker.unpack<User>(
    packed,
    fromJson: User.fromJson,
  );

  print('${unpackedUser.name}, ${unpackedUser.age}'); // Output: Alice, 25
}
```
