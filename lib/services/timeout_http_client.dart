import 'package:http/http.dart' as http;

/// Client réseau qui limite la durée d'attente de chaque requête.
///
/// Branché une seule fois dans main.dart (Supabase.initialize), il s'applique à
/// TOUTES les requêtes (données, connexion, fichiers). Sans lui, une requête sur
/// un réseau très faible pouvait rester en attente indéfiniment.
///
/// Dépassement du délai : une TimeoutException est levée, que les écrans
/// traduisent en message clair (voir AppErrors).
class TimeoutHttpClient extends http.BaseClient {
  final http.Client _inner;

  /// Délai pour les requêtes de données et de connexion.
  final Duration timeout;

  /// Délai plus long pour les envois de fichiers (photos, messages vocaux).
  final Duration fileTimeout;

  TimeoutHttpClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 20),
    this.fileTimeout = const Duration(seconds: 60),
  }) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final isFile = request.url.path.contains('/storage/v1/');
    return _inner.send(request).timeout(isFile ? fileTimeout : timeout);
  }

  @override
  void close() {
    _inner.close();
  }
}
