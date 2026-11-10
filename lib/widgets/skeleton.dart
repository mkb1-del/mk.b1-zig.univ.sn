import 'package:flutter/material.dart';

/// Squelettes de chargement : la forme de l'écran apparaît tout de suite, avec
/// un léger scintillement, à la place d'un cercle qui tourne au milieu du vide.
/// Cela donne une impression de rapidité et prépare l'œil à ce qui va s'afficher.
///
/// Accessibilité : un libellé « Chargement en cours » est annoncé par les
/// lecteurs d'écran, et le scintillement s'arrête si l'utilisateur a demandé de
/// réduire les animations dans les réglages de son téléphone.

const Color _boneBase = Color(0xFFEADDE4);
const Color _boneHighlight = Color(0xFFF9F2F6);

/// Décalage horizontal du dégradé (de -1 à +1 fois la largeur de la forme).
class _SlideGradient extends GradientTransform {
  final double percent;

  const _SlideGradient(this.percent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * percent, 0, 0);
  }
}

/// Fournit une seule horloge à toutes les formes d'un squelette.
class _SkeletonTicker extends InheritedNotifier<AnimationController> {
  const _SkeletonTicker({
    required AnimationController controller,
    required super.child,
  }) : super(notifier: controller);

  static AnimationController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_SkeletonTicker>()?.notifier;
  }
}

/// Enveloppe un squelette : démarre l'animation et annonce « Chargement en cours ».
class SkeletonScope extends StatefulWidget {
  final Widget child;

  const SkeletonScope({super.key, required this.child});

  @override
  State<SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<SkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement en cours',
      container: true,
      child: ExcludeSemantics(
        child: _SkeletonTicker(controller: _controller, child: widget.child),
      ),
    );
  }
}

/// Une forme grise qui scintille (texte, avatar, image...).
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final controller = _SkeletonTicker.maybeOf(context);

    return AnimatedBuilder(
      animation: controller ?? kAlwaysCompleteAnimation,
      builder: (context, _) {
        final t = controller?.value ?? 0.5;
        return Container(
          width: circle ? height : width,
          height: height,
          decoration: BoxDecoration(
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(radius),
            gradient: LinearGradient(
              colors: const [_boneBase, _boneHighlight, _boneBase],
              stops: const [0.25, 0.5, 0.75],
              transform: _SlideGradient(-1 + 2 * t),
            ),
          ),
        );
      },
    );
  }
}

/// Carte blanche translucide, comme les vraies cartes de l'application.
class _SkeletonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SkeletonCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF3DCE5)),
      ),
      child: child,
    );
  }
}

/// Une ligne de liste : avatar (ou icône carrée) et deux lignes de texte.
class _SkeletonRow extends StatelessWidget {
  final bool avatar;
  final int index;

  const _SkeletonRow({required this.avatar, required this.index});

  @override
  Widget build(BuildContext context) {
    // Largeurs légèrement variées pour un aspect naturel.
    const factors = [0.62, 0.78, 0.5];
    final f = factors[index % factors.length];

    return _SkeletonCard(
      child: Row(
        children: [
          if (avatar)
            const SkeletonBox(height: 46, circle: true)
          else
            const SkeletonBox(width: 46, height: 46, radius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: f,
                  child: const SkeletonBox(height: 14),
                ),
                const SizedBox(height: 10),
                const FractionallySizedBox(
                  widthFactor: 0.9,
                  child: SkeletonBox(height: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Liste de lignes : conversations, patientes, rendez-vous, ordonnances...
class SkeletonList extends StatelessWidget {
  final int count;
  final bool avatar;

  const SkeletonList({super.key, this.count = 7, this.avatar = true});

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SkeletonRow(avatar: avatar, index: i),
            ),
        ],
      ),
    );
  }
}

/// En-tête dégradé : grand bloc arrondi.
class _SkeletonHero extends StatelessWidget {
  final double height;

  const _SkeletonHero({required this.height});

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(height: height, radius: 24);
  }
}

class _SkeletonTextCard extends StatelessWidget {
  final int lines;

  const _SkeletonTextCard({this.lines = 3});

  @override
  Widget build(BuildContext context) {
    return _SkeletonCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FractionallySizedBox(
            widthFactor: 0.45,
            child: SkeletonBox(height: 16),
          ),
          for (var i = 0; i < lines; i++) ...[
            const SizedBox(height: 12),
            FractionallySizedBox(
              widthFactor: i.isEven ? 1.0 : 0.72,
              child: const SkeletonBox(height: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// Page de contenu : en-tête puis cartes (statistiques, détails, rappels...).
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: const [
          _SkeletonHero(height: 112),
          SizedBox(height: 20),
          _SkeletonTextCard(lines: 3),
          SizedBox(height: 14),
          _SkeletonTextCard(lines: 4),
          SizedBox(height: 14),
          _SkeletonTextCard(lines: 2),
        ],
      ),
    );
  }
}

/// Accueil : bandeau, deux compteurs, puis cartes.
class SkeletonHome extends StatelessWidget {
  const SkeletonHome({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: const [
          _SkeletonHero(height: 150),
          SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 92, radius: 18)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 92, radius: 18)),
            ],
          ),
          SizedBox(height: 22),
          _SkeletonTextCard(lines: 2),
          SizedBox(height: 14),
          _SkeletonTextCard(lines: 3),
        ],
      ),
    );
  }
}

/// Profil : grand avatar, nom, puis cartes d'informations.
class SkeletonProfile extends StatelessWidget {
  const SkeletonProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: const [
          Center(child: SkeletonBox(height: 96, circle: true)),
          SizedBox(height: 16),
          Center(child: SkeletonBox(width: 160, height: 18)),
          SizedBox(height: 8),
          Center(child: SkeletonBox(width: 110, height: 12)),
          SizedBox(height: 22),
          _SkeletonTextCard(lines: 3),
          SizedBox(height: 14),
          _SkeletonTextCard(lines: 2),
        ],
      ),
    );
  }
}

/// Conversation : bulles alternées à gauche et à droite.
class SkeletonChat extends StatelessWidget {
  const SkeletonChat({super.key});

  @override
  Widget build(BuildContext context) {
    // (de moi ?, largeur relative, hauteur)
    const bubbles = [
      (false, 0.55, 46.0),
      (true, 0.42, 38.0),
      (false, 0.68, 62.0),
      (true, 0.6, 46.0),
      (false, 0.4, 38.0),
      (true, 0.7, 62.0),
    ];

    return SkeletonScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (final b in bubbles)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Align(
                alignment: b.$1 ? Alignment.centerRight : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: b.$2,
                  child: SkeletonBox(height: b.$3, radius: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Galerie : grille de vignettes.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < 12; i++) const SkeletonBox(height: 100, radius: 14),
        ],
      ),
    );
  }
}
