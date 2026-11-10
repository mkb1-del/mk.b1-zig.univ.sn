import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

/// Une photo choisie par l'utilisateur, lue en mémoire (fonctionne sur le web
/// comme sur téléphone).
class PickedAvatar {
  final Uint8List bytes;
  final String mime;

  const PickedAvatar(this.bytes, this.mime);

  String get extension {
    switch (mime) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      default:
        return 'jpg';
    }
  }
}

/// Photo de profil : choisir, envoyer, supprimer.
///
/// Les photos sont rangées dans l'espace « avatars », un dossier par
/// utilisateur, et l'adresse est enregistrée dans profiles.avatar_url.
class AvatarService {
  static const String _bucket = 'avatars';
  static const int _maxBytes = 3 * 1024 * 1024;

  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  /// Dernier message d'erreur (à afficher à l'utilisateur ou à déboguer).
  String? lastError;

  /// Ouvre l'appareil photo ou la galerie. Renvoie null si l'utilisateur annule
  /// ou si la photo est refusée (voir [lastError]).
  Future<PickedAvatar?> pick(ImageSource source) async {
    lastError = null;
    try {
      // Sur le web, on n'applique pas de redimensionnement.
      final XFile? file = kIsWeb
          ? await _picker.pickImage(source: source)
          : await _picker.pickImage(
              source: source,
              maxWidth: 800,
              maxHeight: 800,
              imageQuality: 85,
            );
      if (file == null) return null;

      final bytes = await file.readAsBytes();
      if (bytes.length > _maxBytes) {
        lastError = 'Photo trop lourde (3 Mo maximum).';
        return null;
      }
      return PickedAvatar(bytes, _mimeOf(file));
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ Erreur choix de la photo: $e');
      return null;
    }
  }

  String _mimeOf(XFile file) {
    final fromPicker = file.mimeType ?? '';
    if (fromPicker.startsWith('image/')) {
      return fromPicker == 'image/jpg' ? 'image/jpeg' : fromPicker;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Envoie la photo et l'enregistre dans le profil de l'utilisateur connecté.
  /// Renvoie l'adresse publique de la photo, ou null en cas d'échec.
  Future<String?> upload(PickedAvatar avatar) async {
    lastError = null;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Utilisateur non connecté');

      final oldUrl = await _currentUrl(userId);

      // Nom unique : la nouvelle photo s'affiche tout de suite (pas de cache).
      final path =
          '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.${avatar.extension}';

      await _supabase.storage.from(_bucket).uploadBinary(
            path,
            avatar.bytes,
            fileOptions: FileOptions(contentType: avatar.mime),
          );

      final url = _supabase.storage.from(_bucket).getPublicUrl(path);
      await _supabase.from('profiles').update({'avatar_url': url}).eq('id', userId);

      AuthService.clearCache();
      await _deleteFile(oldUrl);
      return url;
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ Erreur envoi de la photo de profil: $e');
      return null;
    }
  }

  /// Supprime la photo de profil.
  Future<bool> remove() async {
    lastError = null;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Utilisateur non connecté');

      final oldUrl = await _currentUrl(userId);
      await _supabase.from('profiles').update({'avatar_url': null}).eq('id', userId);
      AuthService.clearCache();
      await _deleteFile(oldUrl);
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ Erreur suppression de la photo de profil: $e');
      return false;
    }
  }

  // ----------------------------------------------------------- Outils

  Future<String?> _currentUrl(String userId) async {
    try {
      final rows = await _supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', userId)
          .limit(1);
      if (rows.isEmpty) return null;
      return rows.first['avatar_url']?.toString();
    } catch (e) {
      debugPrint('ℹ️ Ancienne photo non lue: $e');
      return null;
    }
  }

  /// Supprime l'ancien fichier du stockage ; sans conséquence si cela échoue.
  Future<void> _deleteFile(String? url) async {
    if (url == null || url.isEmpty) return;
    const marker = '/object/public/$_bucket/';
    final index = url.indexOf(marker);
    if (index == -1) return;

    final path = Uri.decodeComponent(url.substring(index + marker.length).split('?').first);
    try {
      await _supabase.storage.from(_bucket).remove([path]);
    } catch (e) {
      debugPrint('ℹ️ Ancien fichier non supprimé: $e');
    }
  }
}
