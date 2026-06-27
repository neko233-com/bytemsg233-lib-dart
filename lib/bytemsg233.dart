library bytemsg233;

enum WireType { varint, fixed64, bytes, fixed32 }

abstract class Resettable {
  void reset();
}

class ByteMsgPool<T extends Resettable> {
  final T Function() _factory;
  final List<T> _items = [];

  ByteMsgPool(this._factory);

  T acquire() => _items.isNotEmpty ? _items.removeLast() : _factory();

  void release(T value) {
    value.reset();
    _items.add(value);
  }
}

int zigzagEncode(int value) => (value << 1) ^ (value >> 63);
int zigzagDecode(int value) => (value >> 1) ^ -(value & 1);

class ByteMsgWriter {
  List<int> _buf;
  int _pos = 0;

  ByteMsgWriter([int initialCapacity = 256]) : _buf = List.filled(initialCapacity, 0);

  List<int> finish() => _buf.sublist(0, _pos);
  void reset() => _pos = 0;

  void _ensure(int additional) {
    if (_pos + additional > _buf.length) {
      final newBuf = List.filled(_buf.length * 2 + additional, 0);
      newBuf.setRange(0, _pos, _buf);
      _buf = newBuf;
    }
  }

  void writeVarint(int value) {
    var v = value;
    while (v >= 0x80) {
      _ensure(1);
      _buf[_pos++] = (v & 0x7F) | 0x80;
      v >>= 7;
    }
    _ensure(1);
    _buf[_pos++] = v;
  }

  void writeHeader(int tag, WireType wireType) {
    writeVarint((tag << 3) | wireType.index);
  }

  void writeFixed32(int value) {
    _ensure(4);
    _buf[_pos] = value & 0xFF;
    _buf[_pos + 1] = (value >> 8) & 0xFF;
    _buf[_pos + 2] = (value >> 16) & 0xFF;
    _buf[_pos + 3] = (value >> 24) & 0xFF;
    _pos += 4;
  }

  void writeFixed64(int value) {
    _ensure(8);
    for (var i = 0; i < 8; i++) {
      _buf[_pos + i] = (value >> (i * 8)) & 0xFF;
    }
    _pos += 8;
  }

  void writeStringValue(String value) {
    final bytes = Uint8List.fromList(utf8.encode(value));
    writeVarint(bytes.length);
    _ensure(bytes.length);
    _buf.setRange(_pos, _pos + bytes.length, bytes);
    _pos += bytes.length;
  }

  void writeString(int tag, String value) {
    writeHeader(tag, WireType.bytes);
    writeStringValue(value);
  }

  void writeUintField(int tag, int value) {
    writeHeader(tag, WireType.varint);
    writeVarint(value);
  }

  void writeIntField(int tag, int value) {
    writeHeader(tag, WireType.varint);
    writeVarint(value);
  }

  void writeInt64Field(int tag, int value) {
    writeHeader(tag, WireType.varint);
    writeVarint(zigzagEncode(value));
  }

  void writeFloatField(int tag, double value) {
    writeHeader(tag, WireType.fixed32);
    final bits = Float32List(1)..[0] = value;
    final intBits = Int32List.view(bits.buffer)[0];
    writeFixed32(intBits);
  }

  void writeDoubleField(int tag, double value) {
    writeHeader(tag, WireType.fixed64);
    final bits = Float64List(1)..[0] = value;
    final intBits = Int64List.view(bits.buffer)[0];
    writeFixed64(intBits);
  }

  void writeBoolField(int tag, bool value) {
    writeHeader(tag, WireType.varint);
    writeVarint(value ? 1 : 0);
  }

  void writeEnumField(int tag, int value) {
    writeHeader(tag, WireType.varint);
    writeVarint(value);
  }

  void writeBytesField(int tag, List<int> value) {
    writeHeader(tag, WireType.bytes);
    writeVarint(value.length);
    _ensure(value.length);
    _buf.setRange(_pos, _pos + value.length, value);
    _pos += value.length;
  }

  void writeListField<T>(int tag, List<T> items, void Function(ByteMsgWriter, T) writeFn) {
    writeHeader(tag, WireType.bytes);
    final nested = ByteMsgWriter();
    nested.writeVarint(items.length);
    for (final item in items) writeFn(nested, item);
    final nb = nested.finish();
    writeVarint(nb.length);
    _ensure(nb.length);
    _buf.setRange(_pos, _pos + nb.length, nb);
    _pos += nb.length;
  }

  void writePackedVarints(int tag, List<int> values) {
    writeHeader(tag, WireType.bytes);
    final nested = ByteMsgWriter();
    nested.writeVarint(values.length);
    for (final v in values) nested.writeVarint(v);
    final nb = nested.finish();
    writeVarint(nb.length);
    _ensure(nb.length);
    _buf.setRange(_pos, _pos + nb.length, nb);
    _pos += nb.length;
  }

  void writeDeltaVarints(int tag, List<int> values) {
    writeHeader(tag, WireType.bytes);
    final nested = ByteMsgWriter();
    nested.writeVarint(values.length);
    if (values.isNotEmpty) {
      var prev = values[0];
      nested.writeVarint(prev);
      for (var i = 1; i < values.length; i++) {
        nested.writeVarint(zigzagEncode(values[i] - prev));
        prev = values[i];
      }
    }
    final nb = nested.finish();
    writeVarint(nb.length);
    _ensure(nb.length);
    _buf.setRange(_pos, _pos + nb.length, nb);
    _pos += nb.length;
  }

  void writeBoolBitset(int tag, List<bool> values) {
    writeHeader(tag, WireType.bytes);
    final nested = ByteMsgWriter();
    nested.writeVarint(values.length);
    var current = 0;
    for (var i = 0; i < values.length; i++) {
      if (values[i]) current |= 1 << (i & 7);
      if ((i & 7) == 7) { nested._ensure(1); nested._buf[nested._pos++] = current; current = 0; }
    }
    if (values.length & 7 != 0) { nested._ensure(1); nested._buf[nested._pos++] = current }
    final nb = nested.finish();
    writeVarint(nb.length);
    _ensure(nb.length);
    _buf.setRange(_pos, _pos + nb.length, nb);
    _pos += nb.length;
  }

  void writeStringList(int tag, List<String> values) {
    writeHeader(tag, WireType.bytes);
    final nested = ByteMsgWriter();
    nested.writeVarint(values.length);
    for (final v in values) nested.writeStringValue(v);
    final nb = nested.finish();
    writeVarint(nb.length);
    _ensure(nb.length);
    _buf.setRange(_pos, _pos + nb.length, nb);
    _pos += nb.length;
  }
}

class ByteMsgReader {
  final Uint8List _data;
  int _pos = 0;

  ByteMsgReader(List<int> data) : _data = data is Uint8List ? data : Uint8List.fromList(data);

  bool get eof => _pos >= _data.length;
  int get remaining => _data.length - _pos;

  FieldHeader readFieldHeader() {
    final raw = readVarint();
    return FieldHeader((raw >> 3).toInt(), WireType.values[raw & 0x7]);
  }

  int readVarint() {
    var value = 0;
    var shift = 0;
    while (shift < 64) {
      if (_pos >= _data.length) return 0;
      final b = _data[_pos++];
      value |= (b & 0x7F) << shift;
      if (b < 0x80) return value;
      shift += 7;
    }
    return value;
  }

  int readVarintInt() => readVarint();
  int readVarintLong() => readVarint();
  int readVarintInt64() => zigzagDecode(readVarint());

  int readFixed32() {
    if (_data.length - _pos < 4) return 0;
    final v = _data[_pos] | (_data[_pos + 1] << 8) | (_data[_pos + 2] << 16) | (_data[_pos + 3] << 24);
    _pos += 4;
    return v;
  }

  int readFixed64() {
    if (_data.length - _pos < 8) return 0;
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v |= (_data[_pos + i] & 0xFF) << (i * 8);
    }
    _pos += 8;
    return v;
  }

  double readFloat() {
    final bits = Int32List(1)..[0] = readFixed32();
    return Float32List.view(bits.buffer)[0];
  }

  double readDouble() {
    final bits = Int64List(1)..[0] = readFixed64();
    return Float64List.view(bits.buffer)[0];
  }

  bool readBool() => readVarint() != 0;
  int readEnum() => readVarint();

  String readString() {
    final len = readVarint();
    if (len > _data.length - _pos) return '';
    final s = utf8.decode(_data.sublist(_pos, _pos + len));
    _pos += len;
    return s;
  }

  Uint8List readBytes() {
    final len = readVarint();
    if (len > _data.length - _pos) return Uint8List(0);
    final bytes = Uint8List.fromList(_data.sublist(_pos, _pos + len));
    _pos += len;
    return bytes;
  }

  void skipField(WireType wireType) {
    switch (wireType) {
      case WireType.varint: readVarint(); break;
      case WireType.fixed64: _pos += 8; break;
      case WireType.bytes: final n = readVarint(); _pos += n; break;
      case WireType.fixed32: _pos += 4; break;
    }
  }

  List<T> readList<T>(T Function(ByteMsgReader) readFn) {
    final count = readVarint();
    final len = readVarint();
    final end = _pos + len;
    final items = <T>[];
    for (var i = 0; i < count; i++) items.add(readFn(this));
    _pos = end;
    return items;
  }

  List<int> readPackedVarints() {
    final count = readVarint();
    final len = readVarint();
    final end = _pos + len;
    final arr = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) arr[i] = readVarint();
    _pos = end;
    return arr;
  }

  List<int> readDeltaVarints() {
    final count = readVarint();
    final len = readVarint();
    final end = _pos + len;
    final arr = List<int>.filled(count, 0);
    if (count > 0) {
      var value = readVarint();
      arr[0] = value;
      for (var i = 1; i < count; i++) {
        value = value + zigzagDecode(readVarint());
        arr[i] = value;
      }
    }
    _pos = end;
    return arr;
  }

  List<bool> readBoolBitset() {
    final count = readVarint();
    final len = readVarint();
    final end = _pos + len;
    final arr = List<bool>.filled(count, false);
    var i = 0;
    while (i < count) {
      final current = _data[_pos++];
      final limit = min(8, count - i);
      for (var b = 0; b < limit; b++) arr[i + b] = (current & (1 << b)) != 0;
      i += 8;
    }
    _pos = end;
    return arr;
  }

  List<String> readStringList() {
    final count = readVarint();
    final len = readVarint();
    final end = _pos + len;
    final items = <String>[];
    for (var i = 0; i < count; i++) items.add(readString());
    _pos = end;
    return items;
  }
}

class FieldHeader {
  final int tag;
  final WireType wireType;
  const FieldHeader(this.tag, this.wireType);
}

class ProtocolHello {
  int version;
  int minCompatible;
  ProtocolHello({this.version = 0, this.minCompatible = 0});
}

extension ByteMsgWriterProtocol on ByteMsgWriter {
  void appendProtocolHello(ProtocolHello hello) {
    writeHeader(1, WireType.varint);
    writeVarint(hello.version);
    writeHeader(2, WireType.varint);
    writeVarint(hello.minCompatible);
  }
}

extension ByteMsgReaderProtocol on ByteMsgReader {
  ProtocolHello readProtocolHello() {
    final hello = ProtocolHello();
    while (!eof) {
      final h = readFieldHeader();
      switch (h.tag) {
        case 1: hello.version = readVarint();
        case 2: hello.minCompatible = readVarint();
        default: skipField(h.wireType);
      }
    }
    return hello;
  }
}

bool checkProtocolHello(ProtocolHello local, ProtocolHello remote) {
  return remote.version >= local.minCompatible && local.version >= remote.minCompatible;
}

int min(int a, int b) => a < b ? a : b;

import 'dart:convert';
import 'dart:typed_data';
