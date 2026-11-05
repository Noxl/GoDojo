import 'storage_io.dart'
    if (dart.library.js_interop) 'storage_web.dart'
    as impl;

/// A file of the storage.
class StoredFile {
  const StoredFile(this.path, this.modified);
  final String path;
  final DateTime modified;
}

/// Where the app keeps its files: the disk on desktop, the browser storage
/// on the web. Paths are plain strings in both cases.
abstract class Storage {
  static Storage instance = impl.createStorage();

  /// True when files live in the browser (no real folder).
  bool get inBrowser;

  /// Must be called once before the first use.
  Future<void> init();

  Future<String> defaultLibraryDir();

  /// Folder for the app's own data (training progress).
  Future<String> appDataDir();

  Future<String> read(String path);

  /// Writes [text] to [path], creating its folder if needed.
  Future<void> write(String path, String text);
  Future<bool> exists(String path);

  /// When [path] was last written, or null when there is no such file.
  Future<DateTime?> modified(String path);
  bool existsSync(String path);
  Future<bool> dirExists(String dir);
  Future<void> createDir(String dir);
  Future<void> delete(String path);
  Future<void> rename(String from, String to);

  /// The `.sgf` files under [dir], searched recursively.
  Future<List<StoredFile>> listSgf(String dir);
}

Storage get storage => Storage.instance;
