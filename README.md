# bytemsg233-lib-dart

Dart / Flutter runtime for `bytemsg233` generated code.

This repository provides encode/decode helpers, object pool, and enum utilities for generated Dart classes. Works on Flutter, Dart VM, and web.

## Features

- `Hero.acquire()` / `release()` pooling for zero-GC game hot paths
- Native `enum` support
- Varint, zigzag, string, bytes, list, map, nested message support
- Single-threaded by design: no locks, no isolates, no background workers
- Flutter, Dart VM, and web compatible
- Zero external dependencies

## Install

Copy-based install from the main repository:

```bash
bytemsg233 install-lib dart --to ./vendor/bytemsg233
```

Or add as a git submodule:

```bash
git submodule add https://github.com/neko233-com/bytemsg233-lib-dart.git vendor/bytemsg233
```

## Quick Start

```dart
import 'package:bytemsg233/bytemsg233.dart';

enum HeroState {
  idle,
  moving,
  dead;

  static HeroState fromValue(int v) => HeroState.values[v.clamp(0, HeroState.values.length - 1)];
}

class Hero {
  int id = 0;
  String name = '';
  HeroState state = HeroState.idle;
  List<String> tags = [];

  static final _pool = ByteMsgPool<Hero>(() => Hero());

  static Hero acquire() => _pool.acquire();
  void release() {
    reset();
    _pool.release(this);
  }

  void reset() {
    id = 0;
    name = '';
    state = HeroState.idle;
    tags.clear();
  }

  List<int> encode() {
    final writer = ByteMsgWriter();
    writer.writeUintField(1, id);
    writer.writeStringField(2, name);
    writer.writeEnumField(3, state.index);
    writer.writeListField(4, tags, (w, v) => w.writeString(v));
    return writer.finish();
  }

  static Hero decode(List<int> data) {
    final hero = Hero.acquire();
    final reader = ByteMsgReader(data);
    while (!reader.eof) {
      final (tag, wireType) = reader.readFieldHeader();
      switch (tag) {
        case 1: hero.id = reader.readVarintInt();
        case 2: hero.name = reader.readString();
        case 3: hero.state = HeroState.fromValue(reader.readVarintInt());
        case 4: hero.tags.addAll(reader.readList((r) => r.readString()));
        default: reader.skipField(wireType);
      }
    }
    return hero;
  }
}
```

## API

- `ByteMsgWriter`: field header, scalar, string, bytes, list, map, nested message writing
- `ByteMsgReader`: field header, scalar reading, field skipping with bounded length checks
- `ByteMsgPool<T>`: single-threaded object pool with `acquire()` / `release()`
- Enum helpers for `enum` value restore and validation

## Development

```bash
dart test
```
