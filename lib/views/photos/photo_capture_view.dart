import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../services/app_errors.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/photo_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';

/// Prise de photo guidée : conseils, aperçu, note facultative, envoi.
/// Se ferme avec `true` quand la photo a été envoyée.
class PhotoCaptureView extends StatefulWidget {
  /// true : l'appareil photo s'ouvre dès l'arrivée sur l'écran.
  final bool autoStart;

  const PhotoCaptureView({super.key, this.autoStart = false});

  @override
  State<PhotoCaptureView> createState() => _PhotoCaptureViewState();
}

class _PhotoCaptureViewState extends State<PhotoCaptureView> {
  final ImagePicker _picker = ImagePicker();
  final PhotoService _photoService = PhotoService();
  final TextEditingController _descriptionController = TextEditingController();

  XFile? _capturedPhoto;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _capturePhoto();
      });
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    try {
      // Sur le web, on n'applique pas de redimensionnement.
      final XFile? photo = kIsWeb
          ? await _picker.pickImage(source: ImageSource.camera)
          : await _picker.pickImage(
              source: ImageSource.camera,
              maxWidth: 1920,
              maxHeight: 1920,
              imageQuality: 85,
            );

      if (photo != null && mounted) {
        setState(() => _capturedPhoto = photo);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${AppErrors.message(e)}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _send() async {
    final photo = _capturedPhoto;
    if (photo == null) return;

    setState(() => _isSending = true);
    final note = _descriptionController.text.trim();

    final uploaded = await _photoService.uploadPhoto(
      filePath: photo.path,
      type: 'general',
      description: note.isEmpty ? null : note,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (uploaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Envoi impossible. Vérifiez votre connexion et réessayez.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Photo enregistrée'),
        backgroundColor: AppColors.success,
      ),
    );
    Navigator.pop(context, true);
  }

  // ------------------------------------------------------------------ UI

  Widget _tip(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.rose.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.rose, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: AppColors.ink, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 120,
          height: 120,
          decoration: const BoxDecoration(
            color: AppColors.roseSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.photo_camera_outlined,
              size: 56, color: AppColors.rose),
        ),
        const SizedBox(height: 20),
        const Text(
          'Prenez une photo',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pour suivre l\'évolution au fil du temps.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        AppCard(
          child: Column(
            children: [
              _tip(Icons.wb_sunny_outlined, 'Choisissez un endroit bien éclairé.'),
              _tip(Icons.crop_free, 'Cadrez bien la zone à suivre.'),
              _tip(Icons.compare_outlined,
                  'Gardez le même angle et la même distance à chaque photo.'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final path = _capturedPhoto!.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                // Sur le web, le chemin est une adresse « blob » : pas de File.
                kIsWeb
                    ? Image.network(path, fit: BoxFit.contain)
                    : Image.file(File(path), fit: BoxFit.contain),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: 'Retirer la photo',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _isSending
                          ? null
                          : () => setState(() => _capturedPhoto = null),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: TextField(
            controller: _descriptionController,
            maxLines: 2,
            enabled: !_isSending,
            decoration: const InputDecoration(
              labelText: 'Note (optionnelle)',
              hintText: 'Ex : 2 semaines après la séance',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final hasPhoto = _capturedPhoto != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.rose.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : (hasPhoto ? _send : _capturePhoto),
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(hasPhoto ? Icons.send : Icons.photo_camera_outlined),
                  label: Text(
                    _isSending
                        ? 'Envoi en cours...'
                        : (hasPhoto ? 'Enregistrer la photo' : 'Prendre une photo'),
                  ),
                ),
              ),
              if (hasPhoto && !_isSending)
                TextButton.icon(
                  onPressed: _capturePhoto,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reprendre la photo'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prendre une photo')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: _capturedPhoto == null ? _buildEmpty() : _buildPreview(),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }
}
