import 'dart:async';

import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';

/// Enveloppe toute l'application : affiche un bandeau en haut quand la
/// connexion est perdue, puis « Connexion rétablie » pendant 2 secondes.
///
/// Branché une seule fois dans main.dart (paramètre builder de MaterialApp).
/// Le contenu de l'application reste intact : seul un bandeau s'insère au-dessus.
class ConnectivityBannerHost extends StatefulWidget {
  final Widget child;

  const ConnectivityBannerHost({super.key, required this.child});

  @override
  State<ConnectivityBannerHost> createState() => _ConnectivityBannerHostState();
}

class _ConnectivityBannerHostState extends State<ConnectivityBannerHost> {
  bool _wasOffline = false;
  bool _showRestored = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _wasOffline = !ConnectivityService.instance.online.value;
    ConnectivityService.instance.online.addListener(_onChanged);
  }

  @override
  void dispose() {
    ConnectivityService.instance.online.removeListener(_onChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onChanged() {
    final online = ConnectivityService.instance.online.value;
    _timer?.cancel();

    if (!online) {
      _wasOffline = true;
      setState(() => _showRestored = false);
    } else if (_wasOffline) {
      _wasOffline = false;
      setState(() => _showRestored = true);
      _timer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _showRestored = false);
      });
    } else {
      setState(() {});
    }
  }

  Widget _buildBanner(bool online) {
    final color = online ? AppColors.success : AppColors.ink;

    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                online ? Icons.wifi : Icons.wifi_off,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  online
                      ? 'Connexion rétablie'
                      : 'Pas de connexion internet. Certaines fonctions sont indisponibles.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = ConnectivityService.instance.online.value;
    final showBanner = !online || _showRestored;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: showBanner
              ? _buildBanner(online)
              : const SizedBox(width: double.infinity, height: 0),
        ),
        // Même structure dans les deux cas : l'état de la navigation est conservé.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: showBanner,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// Affichage de secours quand un élément de l'écran plante, à la place de
/// l'écran gris ou rouge standard de Flutter.
class FriendlyErrorWidget extends StatelessWidget {
  const FriendlyErrorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.muted, size: 28),
            SizedBox(height: 8),
            Text(
              'Cet élément n\'a pas pu s\'afficher.\nRevenez en arrière puis réessayez.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.muted,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
