import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/avatar_service.dart';
import '../theme/app_theme.dart';

enum PhotoChoice { camera, gallery, remove }

/// Fenêtre de choix : appareil photo, galerie, et suppression si une photo existe.
Future<PhotoChoice?> showPhotoChoiceSheet(
  BuildContext context, {
  bool canRemove = false,
}) {
  return showModalBottomSheet<PhotoChoice>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: AppColors.rose),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(context, PhotoChoice.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppColors.rose),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.pop(context, PhotoChoice.gallery),
          ),
          if (canRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Supprimer ma photo'),
              onTap: () => Navigator.pop(context, PhotoChoice.remove),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Parcours complet « changer ma photo de profil » depuis un profil :
/// choix, envoi (ou suppression), message de confirmation.
/// Renvoie vrai si la photo a changé.
Future<bool> changeProfilePhoto(
  BuildContext context, {
  required bool hasPhoto,
}) async {
  final choice = await showPhotoChoiceSheet(context, canRemove: hasPhoto);
  if (choice == null || !context.mounted) return false;

  final service = AvatarService();
  var ok = false;
  String message;

  if (choice == PhotoChoice.remove) {
    ok = await service.remove();
    message = ok ? 'Photo supprimée' : '❌ Suppression impossible';
  } else {
    final picked = await service.pick(
      choice == PhotoChoice.camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (picked == null) {
      // Annulation : silence. Photo refusée : on explique pourquoi.
      if (service.lastError != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${service.lastError}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return false;
    }
    final url = await service.upload(picked);
    ok = url != null;
    message = ok
        ? '✅ Photo mise à jour'
        : '❌ Photo non enregistrée. Vérifiez votre connexion et réessayez.';
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
      ),
    );
  }
  return ok;
}