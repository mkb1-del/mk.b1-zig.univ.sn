import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/photo_model.dart';

/// Fichier lu en mémoire, avec son type MIME.
class _PickedFile {
  final Uint8List bytes;
  final String mime;

  const _PickedFile(this.bytes, this.mime);
}

class PhotoService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _bucket = 'photos';

  /// false : le stockage « photos » est public (comportement actuel).
  /// true  : stockage privé, les photos sont affichées via des liens
  ///         temporaires (voir le script SQL fourni pour l'activer).
  static const bool usePrivateBucket = false;

  /// Dernier message d'erreur technique (utile pour déboguer ou informer).
  String? lastError;

  // ------------------------------------------------------------- Envoi

  Future<Photo?> uploadPhoto({
    required String filePath,
    required String type,
    String? description,
  }) async {
    lastError = null;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Utilisateur non connecté');

      // Lecture en mémoire : fonctionne sur le web (adresse blob) comme sur mobile.
      final picked = await _readBytes(filePath);
      final extension = _extensionFor(picked.mime);

      // Un dossier par utilisateur : indispensable pour sécuriser le stockage.
      final storagePath =
          '$userId/photo_${DateTime.now().millisecondsSinceEpoch}.$extension';

      await _supabase.storage.from(_bucket).uploadBinary(
            storagePath,
            picked.bytes,
            fileOptions: FileOptions(contentType: picked.mime),
          );

      final stored = usePrivateBucket
          ? storagePath
          : _supabase.storage.from(_bucket).getPublicUrl(storagePath);

      final photo = Photo(
        id: '', // Sera généré par Supabase
        userId: userId,
        url: stored,
        type: type,
        description: description,
        createdAt: DateTime.now(),
      );

      final response = await _supabase
          .from('photos')
          .insert(photo.toMap())
          .select()
          .single();

      final uploaded = await _withDisplayUrl(Photo.fromMap(response));
      debugPrint('✅ Photo uploadée: $storagePath');
      return uploaded;
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ Erreur upload photo: $e');
      return null;
    }
  }

  // ----------------------------------------------------------- Lecture

  Future<List<Photo>> getUserPhotos() async {
    lastError = null;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _supabase
          .from('photos')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final photos = response.map((map) => Photo.fromMap(map)).toList();
      if (!usePrivateBucket) return photos;

      return await Future.wait(photos.map(_withDisplayUrl));
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ Erreur récupération photos: $e');
      return [];
    }
  }

  // ------------------------------------------------------- Suppression

  /// Supprime la photo de la base, puis le fichier du stockage
  /// (avant, le fichier restait en ligne même après la suppression).
  Future<bool> deletePhoto(String photoId) async {
    lastError = null;
    try {
      final rows = await _supabase
          .from('photos')
          .select('url')
          .eq('id', photoId)
          .limit(1);

      await _supabase.from('photos').delete().eq('id', photoId);

      if (rows.isNotEmpty) {
        final path = _pathFromStored(rows.first['url']?.toString() ?? '');
        if (path != null) {
          try {
            await _supabase.storage.from(_bucket).remove([path]);
          } catch (e) {
            debugPrint('ℹ️ Fichier non supprimé du stockage: $e');
          }
        }
      }

      debugPrint('✅ Photo supprimée: $photoId');
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ Erreur suppression photo: $e');
      return false;
    }
  }

  // ----------------------------------------------------------- Outils

  Future<_PickedFile> _readBytes(String filePath) async {
    if (kIsWeb) {
      final response = await http.get(Uri.parse(filePath));
      if (response.statusCode != 200) {
        throw Exception('Lecture de la photo impossible (${response.statusCode})');
      }
      final header = (response.headers['content-type'] ?? '').split(';').first;
      final mime = header.startsWith('image/') ? header : 'image/jpeg';
      return _PickedFile(response.bodyBytes, mime);
    }

    final bytes = await File(filePath).readAsBytes();
    return _PickedFile(bytes, _mimeFromPath(filePath));
  }

  String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String _extensionFor(String mime) {
    switch (mime) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/heic':
        return 'heic';
      default:
        return 'jpg';
    }
  }

  /// Retrouve le chemin du fichier dans le stockage, que la base contienne une
  /// adresse publique (anciennes photos) ou directement un chemin.
  String? _pathFromStored(String stored) {
    if (stored.isEmpty) return null;
    const marker = '/object/public/$_bucket/';
    final index = stored.indexOf(marker);
    if (index != -1) {
      final rest = stored.substring(index + marker.length).split('?').first;
      return Uri.decodeComponent(rest);
    }
    if (stored.startsWith('http')) return null;
    return stored;
  }

  /// Avec un stockage privé, remplace le chemin par un lien temporaire (1 h).
  Future<Photo> _withDisplayUrl(Photo photo) async {
    if (!usePrivateBucket) return photo;
    final path = _pathFromStored(photo.url);
    if (path == null) return photo;

    final signed = await _supabase.storage.from(_bucket).createSignedUrl(path, 3600);
    return Photo(
      id: photo.id,
      userId: photo.userId,
      url: signed,
      type: photo.type,
      description: photo.description,
      createdAt: photo.createdAt,
    );
  }
} 