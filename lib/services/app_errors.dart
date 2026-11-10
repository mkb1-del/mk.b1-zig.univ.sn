import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduit les erreurs techniques en messages clairs pour l'utilisateur.
///
/// Règle : l'écran n'affiche JAMAIS le texte brut d'une exception (il peut
/// contenir des noms de tables ou de colonnes). Le détail va au journal.
class AppErrors {
  static const String _generic = 'Une erreur est survenue. Réessayez dans un instant.';

  /// Journal technique (visible seulement en développement).
  static void log(String where, Object error) {
    debugPrint('❌ $where : $error');
  }

  /// Vrai si l'erreur vient d'un problème de réseau (pas de connexion, trop lent).
  static bool isNetworkError(Object? error) {
    if (error == null) return false;
    if (error is TimeoutException || error is http.ClientException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('xmlhttprequest error') ||
        text.contains('failed to fetch');
  }

  /// Message à montrer à l'utilisateur.
  static String message(Object? error, {String fallback = _generic}) {
    if (error == null) return fallback;

    if (error is TimeoutException) {
      return 'La connexion est trop lente. Vérifiez votre réseau puis réessayez.';
    }
    if (isNetworkError(error)) {
      return 'Pas de connexion internet. Vérifiez votre réseau puis réessayez.';
    }

    if (error is AuthException) {
      final m = error.message.toLowerCase();
      if (error.statusCode == '429' || m.contains('rate limit') || m.contains('too many')) {
        return 'Trop de tentatives. Patientez quelques minutes.';
      }
      if (m.contains('invalid login credentials')) {
        return 'Email ou mot de passe incorrect.';
      }
      if (m.contains('email not confirmed')) {
        return 'Veuillez d\'abord confirmer votre email.';
      }
      if (m.contains('already registered') || m.contains('already been registered')) {
        return 'Un compte existe déjà avec cet email.';
      }
      if (m.contains('jwt') || m.contains('session')) {
        return 'Votre session a expiré. Reconnectez-vous.';
      }
      if (m.contains('weak') || m.contains('at least')) {
        return 'Mot de passe trop faible. Choisissez-en un plus long.';
      }
      return fallback;
    }

    if (error is PostgrestException) {
      final code = error.code ?? '';
      final m = error.message.toLowerCase();
      if (m.contains('jwt')) return 'Votre session a expiré. Reconnectez-vous.';
      if (code == '42501' || m.contains('row-level security') || m.contains('permission denied')) {
        return 'Cette action n\'est pas autorisée pour votre compte.';
      }
      if (code == '23505') return 'Cet élément existe déjà.';
      if (code == '23503') return 'Cet élément est lié à d\'autres données.';
      if (code == '23502') return 'Un champ obligatoire est manquant.';
      if (code == 'PGRST116') return 'Élément introuvable.';
      if (code == '42P01' || code == '42703' || code == '42883' || code.startsWith('PGRST2')) {
        return 'Cette fonction n\'est pas encore disponible. Mise à jour du serveur requise.';
      }
      return fallback;
    }

    if (error is StorageException) {
      return 'L\'envoi du fichier a échoué. Vérifiez votre connexion puis réessayez.';
    }

    return fallback;
  }
}
