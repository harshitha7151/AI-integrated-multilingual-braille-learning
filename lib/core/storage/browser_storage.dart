import 'browser_storage_stub.dart'
    if (dart.library.html) 'browser_storage_web.dart' as platform;

/// Browser-backed storage for web variants of Resonant's local stores.
Future<String?> readBrowserLocal(String key) => platform.readLocal(key);
Future<void> writeBrowserLocal(String key, String value) =>
    platform.writeLocal(key, value);
Future<void> removeBrowserLocal(String key) => platform.removeLocal(key);
Future<String?> readBrowserSession(String key) => platform.readSession(key);
Future<void> writeBrowserSession(String key, String value) =>
    platform.writeSession(key, value);
Future<void> removeBrowserSession(String key) => platform.removeSession(key);
