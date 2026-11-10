import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../theme/app_role.dart';

/// Ruban rose de sensibilisation, dessiné en vectoriel (net à toutes les
/// tailles, recolorable, aucun fichier image à embarquer).
///
/// Les deux brins se croisent : le brin « dessus » est détouré d'un fin
/// liseré transparent pour que le croisement soit visible.
class RibbonPainter extends CustomPainter {
  final Color color;

  const RibbonPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.20;
    final gap = stroke * 0.16;

    void cubic(Path p, double x1, double y1, double x2, double y2, double x3,
        double y3) {
      p.cubicTo(x1 * w, y1 * h, x2 * w, y2 * h, x3 * w, y3 * h);
    }

    // Brin « dessous » : queue gauche -> croisement -> boucle -> retour au croisement
    final under = Path()..moveTo(0.18 * w, 0.97 * h);
    cubic(under, 0.30, 0.84, 0.44, 0.66, 0.50, 0.50);
    cubic(under, 0.56, 0.40, 0.76, 0.36, 0.74, 0.20);
    cubic(under, 0.74, 0.08, 0.62, 0.04, 0.50, 0.04);
    cubic(under, 0.38, 0.04, 0.26, 0.08, 0.26, 0.20);
    cubic(under, 0.24, 0.36, 0.44, 0.40, 0.50, 0.50);

    // Brin « dessus » : côté gauche de la boucle -> croisement -> queue droite
    final firstHalf = Path()..moveTo(0.26 * w, 0.20 * h);
    cubic(firstHalf, 0.24, 0.36, 0.44, 0.40, 0.50, 0.50);
    final lengthToCrossing = firstHalf.computeMetrics().first.length;

    final over = Path()..moveTo(0.26 * w, 0.20 * h);
    cubic(over, 0.24, 0.36, 0.44, 0.40, 0.50, 0.50);
    cubic(over, 0.56, 0.66, 0.70, 0.84, 0.82, 0.97);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPath(under, paint);

    // Liseré transparent autour du brin « dessus », uniquement près du croisement
    final metric = over.computeMetrics().first;
    final start = math.max(0.0, lengthToCrossing - stroke * 2.5);
    final end = math.min(metric.length, lengthToCrossing + stroke * 2.5);
    canvas.drawPath(
      metric.extractPath(start, end),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + gap * 2
        ..strokeCap = StrokeCap.butt
        ..blendMode = BlendMode.clear,
    );

    canvas.drawPath(over, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(RibbonPainter oldDelegate) => oldDelegate.color != color;
}

/// Petit logo : le ruban seul, pour les en-têtes et les pastilles.
/// [size] est la hauteur ; la largeur suit les proportions du ruban.
class RibbonLogo extends StatelessWidget {
  final double size;
  final Color color;

  const RibbonLogo({
    super.key,
    this.size = 24,
    this.color = const Color(0xFFD81B60),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.64,
      height: size,
      child: CustomPaint(painter: RibbonPainter(color: color)),
    );
  }
}

/// Fond d'une page : dégradé rosé très clair et un grand ruban centré en filigrane.
/// Il est placé derrière chaque écran par [RibbonPageTransitionsBuilder].
class RibbonBackground extends StatelessWidget {
  final Widget child;

  const RibbonBackground({super.key, required this.child});

  /// Photos de fond (à placer dans assets/images/). Si un fichier est absent,
  /// le décor dessiné prend le relais : ruban pour la patiente, croix pour le médecin.
  ///
  /// Espace patiente : aucune photo (null) = le ruban rose, comme à l'origine.
  /// Pour lui en donner une un jour, indiquer ici son chemin.
  static const String? patientPhoto = null;
  static const String doctorPhoto = 'assets/images/doctor_background.jpg';

  /// Visibilité de la photo : 0 = invisible, 1 = pleine. Entre 0,25 et 0,40, les
  /// textes restent parfaitement lisibles.
  static const double photoOpacity = 0.32;

  static const Color _ribbonColor = Color(0xFFD81B60);

  static final Map<String, Future<bool>> _assetChecks = {};

  static Future<bool> _hasAsset(String path) {
    return _assetChecks.putIfAbsent(path, () async {
      try {
        await rootBundle.load(path);
        return true;
      } catch (_) {
        return false;
      }
    });
  }

  Widget _ribbon(double height, double opacity, double angle) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: angle,
            child: SizedBox(
              width: height * 0.64,
              height: height,
              child: const CustomPaint(
                painter: RibbonPainter(color: _ribbonColor),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Décor dessiné : grand ruban rose (patiente) ou grande croix bleue (médecin).
  Widget _decor({required bool doctor}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 700.0;
        if (doctor) {
          final size = math.min(h * 0.55, w * 0.95);
          return Center(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.10,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: const CustomPaint(
                    painter: _CrossPainter(color: Color(0xFF1E88A8)),
                  ),
                ),
              ),
            ),
          );
        }
        final big = math.min(h * 0.70, w * 1.25);
        return Center(child: _ribbon(big, 0.20, 0));
      },
    );
  }

  Widget _photoOrDecor(String path, {required bool doctor}) {
    return FutureBuilder<bool>(
      future: _hasAsset(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snapshot.data == true) {
          return Opacity(
            opacity: photoOpacity,
            child: Image.asset(
              path,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) => _decor(doctor: doctor),
            ),
          );
        }
        return _decor(doctor: doctor);
      },
    );
  }

  Widget _backdrop(String? role) {
    final doctor = role == 'doctor';
    final colors = doctor
        ? const [Color(0xFFF3F8FB), Color(0xFFE1EEF5)]
        : const [Color(0xFFFFF7FA), Color(0xFFFDE8F1)];

    // Avant la connexion, ou sans photo prévue : le décor dessiné.
    final String? photo = role == null ? null : (doctor ? doctorPhoto : patientPhoto);
    final Widget layer = photo == null
        ? _decor(doctor: doctor)
        : _photoOrDecor(photo, doctor: doctor);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
          ),
        ),
        layer,
      ],
    );
  }

  /// Largeur maximale du contenu. Sur grand écran (ordinateur, tablette), les
  /// pages restent centrées et lisibles ; le fond occupe toujours tout l'écran.
  static const double maxContentWidth = 640;

  Widget _constrained(Widget content) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Même structure quelle que soit la largeur : l'état de la page est conservé.
        final width = constraints.maxWidth < maxContentWidth
            ? constraints.maxWidth
            : maxContentWidth;
        return Center(
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: content,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    AppRole.ensureStarted();

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: ValueListenableBuilder<String?>(
            valueListenable: AppRole.role,
            builder: (context, role, _) => _backdrop(role),
          ),
        ),
        _constrained(child),
      ],
    );
  }
}

/// Croix médicale aux bras arrondis (décor de l'espace médecin).
class _CrossPainter extends CustomPainter {
  final Color color;

  const _CrossPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final arm = size.width * 0.34;
    final radius = Radius.circular(arm * 0.28);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH((size.width - arm) / 2, 0, arm, size.height),
        radius,
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, (size.height - arm) / 2, size.width, arm),
        radius,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrossPainter oldDelegate) =>
      oldDelegate.color != color;
}

class RibbonPageTransitionsBuilder extends PageTransitionsBuilder {
  final PageTransitionsBuilder delegate;

  const RibbonPageTransitionsBuilder(this.delegate);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return delegate.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      RibbonBackground(child: child),
    );
  }
}
