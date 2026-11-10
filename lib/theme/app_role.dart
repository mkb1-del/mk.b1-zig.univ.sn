import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_theme.dart';

/// Rôle de l'utilisateur connecté (« patient » ou « doctor »), utilisé pour
/// donner à chaque espace sa propre identité visuelle (fond, en-têtes).
///
/// Le rôle vient d'abord de la connexion, sinon des informations enregistrées à
/// l'inscription. Avant la connexion, il est nul : l'apparence rose habituelle
/// s'affiche.
class AppRole {
  static final ValueNotifier<String?> role = ValueNotifier<String?>(null);

  static bool get isDoctor => role.value == 'doctor';

  static bool _started = false;

  /// Démarre l'écoute de la connexion (appelée une seule fois, sans effet ensuite).
  static void ensureStarted() {
    if (_started) return;
    _started = true;
    try {
      final auth = Supabase.instance.client.auth;
      _fromUser(auth.currentUser);
      auth.onAuthStateChange.listen((state) => _fromUser(state.session?.user));
    } catch (e) {
      debugPrint('ℹ️ Rôle non initialisé: $e');
    }
  }

  static void _fromUser(User? user) {
    if (user == null) {
      role.value = null;
      return;
    }
    final type = user.userMetadata?['user_type']?.toString();
    if (type == 'doctor' || type == 'patient') {
      role.value = type;
    }
    // Sinon on garde la valeur éventuellement posée par la connexion.
  }

  /// Fixe le rôle explicitement (la connexion le connaît avec certitude).
  static void set(String? value) {
    role.value = value;
  }

  /// Dégradé des grands en-têtes : rose pour la patiente, bleu pour le médecin.
  static LinearGradient get heroGradient =>
      isDoctor ? AppColors.doctorGradient : AppColors.heroGradient;

  /// Couleur de l'ombre des en-têtes.
  static Color get headerShadow =>
      isDoctor ? AppColors.doctorDeep : AppColors.rose;
}