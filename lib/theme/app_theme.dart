import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import '../widgets/ribbon_background.dart';

/// Palette Sunu Yaakaar : une famille de roses (couleur de la cause), du rose
/// framboise profond au rose poudré, avec un vert réservé aux confirmations
/// et un ambre pour les états « en attente ».
class AppColors {
  // --- Famille de roses
  static const Color rose = Color(0xFFD81B60);       // principal (boutons, accents)
  static const Color roseDark = Color(0xFFAD1457);   // appuis, textes d'accent
  static const Color roseMid = Color(0xFFEC4899);    // rose vif
  static const Color roseLight = Color(0xFFF9A8D4);  // rose clair (décors)
  static const Color roseSoft = Color(0xFFFCE4EC);   // fonds teintés
  static const Color plum = Color(0xFF880E4F);       // framboise profond (titres)

  // Anciens noms conservés : ils désignent désormais des roses, pour que
  // tous les écrans existants passent au rose sans être réécrits.
  static const Color teal = Color(0xFFC2457F);       // rose poudré foncé
  static const Color sky = Color(0xFFEC4899);        // rose vif
  static const Color violet = Color(0xFFB83280);     // rose orchidée

  // --- États (sens conservé)
  static const Color success = Color(0xFF2E9E6B);    // confirmé / réussi
  static const Color amber = Color(0xFFF59E0B);      // en attente
  static const Color danger = Color(0xFFE5484D);     // erreur / annulé

  // Versions plus foncées pour ÉCRIRE du texte (contraste suffisant sur fond blanc).
  // Les couleurs ci-dessus restent réservées aux icônes, pastilles et fonds.
  static const Color successText = Color(0xFF237952);
  static const Color dangerText = Color(0xFFC03C40);
  static const Color amberText = Color(0xFF956006);

  // --- Neutres teintés de rose
  static const Color background = Color(0xFFFFF7FA);
  static const Color border = Color(0xFFF3D6E2);
  static const Color ink = Color(0xFF2A1A24);
  static const Color muted = Color(0xFF7D6B76);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8E0E4B), roseMid],
  );

  // Espace médecin : bleu profond (en-têtes, décor). Les accents restent roses.
  static const Color doctorDeep = Color(0xFF0D3B66);
  static const Color doctorTeal = Color(0xFF1E88A8);
  static const LinearGradient doctorGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [doctorDeep, doctorTeal],
  );
}

class AppTheme {
  static OutlineInputBorder _inputBorder(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.rose,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.rose,
      onPrimary: Colors.white,
      secondary: AppColors.teal,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      outlineVariant: AppColors.border,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    final text = base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,

      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.4),
        bodySmall: text.bodySmall?.copyWith(color: AppColors.muted),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android:
              RibbonPageTransitionsBuilder(ZoomPageTransitionsBuilder()),
          TargetPlatform.iOS:
              RibbonPageTransitionsBuilder(CupertinoPageTransitionsBuilder()),
          TargetPlatform.macOS:
              RibbonPageTransitionsBuilder(CupertinoPageTransitionsBuilder()),
          TargetPlatform.windows:
              RibbonPageTransitionsBuilder(ZoomPageTransitionsBuilder()),
          TargetPlatform.linux:
              RibbonPageTransitionsBuilder(ZoomPageTransitionsBuilder()),
          TargetPlatform.fuchsia:
              RibbonPageTransitionsBuilder(ZoomPageTransitionsBuilder()),
        },
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.plum,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.plum,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: AppColors.plum),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _inputBorder(AppColors.border),
        enabledBorder: _inputBorder(AppColors.border),
        focusedBorder: _inputBorder(AppColors.rose, 1.6),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, 1.6),
        labelStyle: const TextStyle(color: AppColors.muted),
        floatingLabelStyle: const TextStyle(color: AppColors.rose),
        hintStyle: const TextStyle(color: AppColors.muted),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.rose,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.rose,
          side: const BorderSide(color: AppColors.rose),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.rose,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.roseSoft,
        elevation: 8,
        shadowColor: AppColors.rose.withValues(alpha: 0.2),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.rose : AppColors.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.rose : AppColors.muted,
          );
        }),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.rose,
        unselectedItemColor: AppColors.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.rose,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      chipTheme: const ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.roseSoft,
        checkmarkColor: AppColors.rose,
        side: BorderSide(color: AppColors.border),
        shape: StadiumBorder(),
        labelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),

      // Sur grand écran, les feuilles du bas gardent la largeur d'un téléphone.
      bottomSheetTheme: const BottomSheetThemeData(
        constraints: BoxConstraints(maxWidth: 640),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.rose,
      ),
    );
  }
}
