/// Build-time default for the single Resonant backend API origin.
/// Override with `--dart-define=API_BASE_URL=https://your-api.example`.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: String.fromEnvironment(
    'RESONANT_TUTOR_API_BASE',
    defaultValue: 'http://172.17.7.164:8000',
  ),
);

/// Shared runtime backend configuration used by every default API client.
///
/// Updating it from the pre-login AIML connection screen also updates clients
/// that were constructed earlier, because they resolve [baseUri] per request.
abstract final class ApiConfiguration {
  static Uri _baseUri = _normalize(Uri.parse(apiBaseUrl));

  static Uri get baseUri => _baseUri;

  static Uri configure(Uri value) {
    _baseUri = _normalize(value);
    return _baseUri;
  }

  static void resetToBuildConfig() {
    _baseUri = _normalize(Uri.parse(apiBaseUrl));
  }

  static Uri _normalize(Uri value) {
    if (!value.hasScheme ||
        value.host.isEmpty ||
        !const {'http', 'https'}.contains(value.scheme) ||
        value.userInfo.isNotEmpty) {
      throw const FormatException(
        'Enter a valid http or https backend URL without credentials.',
      );
    }
    // A backend setting is an origin, not a route. Rebuild it so query and
    // fragment delimiters from a copied endpoint URL cannot be retained.
    return Uri(
      scheme: value.scheme,
      host: value.host,
      port: value.hasPort ? value.port : null,
    );
  }
}

