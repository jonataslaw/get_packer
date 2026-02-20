class ExtType {
  // Ext types are our escape hatch for things that aren't in the core format
  // Keep these stable, once written to disk you're married to them
  static const int bigInt = 0x01;
  static const int duration = 0x02;
  static const int wideInt = 0x03;
  static const int boolList = 0x04;
  static const int uri = 0x05;
  static const int set = 0x06;
  static const int dateTime = 0x07;

  static const int int8List = 0x10;
  static const int uint16List = 0x11;
  static const int int16List = 0x12;
  static const int uint32List = 0x13;
  static const int int32List = 0x14;
  static const int uint64List = 0x15;
  static const int int64List = 0x16;
  static const int float32List = 0x17;
  static const int float64List = 0x18;
}
