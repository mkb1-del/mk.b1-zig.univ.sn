import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// État de la connexion à internet, observable par toute l'application.
///
/// Attention : « connecté » signifie qu'un réseau est disponible, pas que
/// internet fonctionne (un wifi sans accès par exemple). Le délai d'attente des
/// requêtes (TimeoutHttpClient) couvre ce second cas.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  /// Vrai quand un réseau est disponible.
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _started = false;

  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      final connectivity = Connectivity();
      _apply(await connectivity.checkConnectivity());
      _subscription = connectivity.onConnectivityChanged.listen(_apply);
    } catch (e) {
      // En cas de problème avec la surveillance, on considère qu'on est connecté.
      debugPrint('ℹ️ Surveillance du réseau indisponible: $e');
    }
  }

  void _apply(List<ConnectivityResult> results) {
    online.value = results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() {
    _subscription?.cancel();
  }
}
