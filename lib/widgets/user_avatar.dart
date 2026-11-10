import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Avatar d'un utilisateur : sa photo si elle existe, sinon son initiale sur
/// fond rose. Si la photo ne peut pas se charger, l'initiale s'affiche.
class UserAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final double radius;

  const UserAvatar({
    super.key,
    required this.name,
    this.url,
    this.radius = 24,
  });

  Widget _initial() {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Center(
      child: Text(
        letter,
        style: TextStyle(
          fontSize: radius * 0.85,
          fontWeight: FontWeight.w800,
          color: AppColors.rose,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = (url ?? '').trim();
    // La photo est décodée à la taille réellement affichée, pas en pleine résolution.
    final pixels = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round();

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.roseSoft,
          child: photo.isEmpty
              ? _initial()
              : CachedNetworkImage(
                  imageUrl: photo,
                  fit: BoxFit.cover,
                  memCacheWidth: pixels,
                  fadeInDuration: const Duration(milliseconds: 150),
                  placeholder: (context, url) => _initial(),
                  errorWidget: (context, url, error) => _initial(),
                ),
        ),
      ),
    );
  }
}
