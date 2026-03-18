// Stub for dart:io on Web
// This file is conditionally imported when running on Web checks

class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
}

class FileSystemEntity {
  final String path;
  FileSystemEntity(this.path);

  Future<bool> exists() async => false;
  Future<void> delete({bool recursive = false}) async {}
  Future<FileStat> stat() async => FileStat();
}

class File extends FileSystemEntity {
  File(super.path);

  Future<int> length() async => 0;

  Stream<List<int>> openRead([int? start, int? end]) async* {
    yield [];
  }
}

class Directory extends FileSystemEntity {
  Directory(super.path);

  Future<void> create({bool recursive = false}) async {}

  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {}
}

class FileStat {
  DateTime get modified => DateTime.now();
  int get size => 0;

  bool isBefore(DateTime other) => false;
}

abstract class Link extends FileSystemEntity {
  Link(super.path);
}
