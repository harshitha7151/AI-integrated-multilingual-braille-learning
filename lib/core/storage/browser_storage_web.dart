import 'package:web/web.dart' as web;

Future<String?> readLocal(String key) async =>
    web.window.localStorage.getItem(key);
Future<void> writeLocal(String key, String value) async {
  web.window.localStorage.setItem(key, value);
}

Future<void> removeLocal(String key) async {
  web.window.localStorage.removeItem(key);
}

Future<String?> readSession(String key) async =>
    web.window.sessionStorage.getItem(key);
Future<void> writeSession(String key, String value) async {
  web.window.sessionStorage.setItem(key, value);
}

Future<void> removeSession(String key) async {
  web.window.sessionStorage.removeItem(key);
}
