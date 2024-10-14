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
