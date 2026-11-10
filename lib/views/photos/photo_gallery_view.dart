import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import '../../services/app_errors.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/photo_model.dart';
import '../../services/photo_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import 'photo_capture_view.dart';

/// Galerie personnelle de la patiente : grille de photos, ajout, ouverture en
/// grand et suppression.
class PhotoGalleryView extends StatefulWidget {
  const PhotoGalleryView({super.key});

  @override
  State<PhotoGalleryView> createState() => _PhotoGalleryViewState();
}

class _PhotoGalleryViewState extends State<PhotoGalleryView> {
  final PhotoService _photoService = PhotoService();
  final ImagePicker _picker = ImagePicker();

  List<Photo> _photos = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _loadPhotos({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final photos = await _photoService.getUserPhotos();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ------------------------------------------------------------- Ajout

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.rose),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.rose),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    // Appareil photo : parcours guidé (conseils, aperçu, note, envoi).
    if (source == ImageSource.camera) {
      if (!mounted) return;
      final sent = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => const PhotoCaptureView(autoStart: true),
        ),
      );
      if (sent == true && mounted) _loadPhotos(silent: true);
      return;
    }

    // Sur le web, on n'applique pas de redimensionnement.
    final XFile? file = kIsWeb
        ? await _picker.pickImage(source: source)
        : await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null || !mounted) return;

    final description = await _askDescription();
    if (description == null || !mounted) return;

    setState(() => _isUploading = true);
    final photo = await _photoService.uploadPhoto(
      filePath: file.path,
      type: 'general',
      description: description.isEmpty ? null : description,
    );
    if (!mounted) return;
    setState(() => _isUploading = false);

    if (photo == null) {
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
        content: Text('✅ Photo ajoutée'),
        backgroundColor: AppColors.success,
      ),
    );
    _loadPhotos(silent: true);
  }

  /// Renvoie le texte saisi (peut être vide), ou null si l'utilisateur annule.
  Future<String?> _askDescription() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter une note'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description (optionnelle)',
            hintText: 'Ex : cicatrice, 2 semaines après la séance',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  Future<void> _openViewer(Photo photo) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _PhotoViewer(photo: photo, service: _photoService),
      ),
    );
    if (deleted == true && mounted) _loadPhotos(silent: true);
  }

  // ------------------------------------------------------------------ UI

  String _typeLabel(String type) {
    if (type.isEmpty) return 'Autre';
    return type[0].toUpperCase() + type.substring(1);
  }

  List<Photo> get _filtered {
    if (_filter == 'all') return _photos;
    return _photos.where((p) => p.type == _filter).toList();
  }

  Widget _buildFilters() {
    final types = _photos.map((p) => p.type).toSet().toList()..sort();
    if (types.length < 2) return const SizedBox.shrink();

    final entries = <MapEntry<String, String>>[
      const MapEntry('all', 'Toutes'),
      for (final t in types) MapEntry(t, _typeLabel(t)),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: entries.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final e = entries[index];
            return FilterChip(
              label: Text(e.value),
              selected: _filter == e.key,
              onSelected: (_) => setState(() => _filter = e.key),
            );
          },
        ),
      ),
    );
  }

  Widget _buildThumbnail(Photo photo) {
    return GestureDetector(
      onTap: () => _openViewer(photo),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.roseSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: CachedNetworkImage(
            imageUrl: photo.url,
            fit: BoxFit.cover,
            // Miniature : décodée en petit (et non en pleine résolution).
            memCacheWidth: 420,
            placeholder: (context, url) => const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => const Center(
              child: Icon(Icons.broken_image_outlined, color: AppColors.rose),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonGrid();
    }

    if (_photos.isEmpty) {
      return EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'Aucune photo',
        message: 'Ajoutez des photos pour suivre l\'évolution de votre santé au fil du temps.',
        actionLabel: 'Ajouter une photo',
        onAction: _addPhoto,
      );
    }

    final list = _filtered;

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _loadPhotos(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        children: [
          _buildFilters(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '${list.length} photo${list.length > 1 ? 's' : ''}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: list.length,
              itemBuilder: (context, index) => _buildThumbnail(list[index]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ma galerie')),
      body: Column(
        children: [
          if (_isUploading) const LinearProgressIndicator(minHeight: 3),
          Expanded(child: _buildContent()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _addPhoto,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Ajouter'),
      ),
    );
  }
}

/// Visionneuse plein écran : zoom, informations et suppression.
class _PhotoViewer extends StatelessWidget {
  final Photo photo;
  final PhotoService service;

  const _PhotoViewer({required this.photo, required this.service});

  String _dateLabel(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} à ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la photo'),
        content: const Text('Cette photo sera définitivement supprimée. Continuer ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ok = await service.deletePhoto(photo.id);
    if (!context.mounted) return;

    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Suppression impossible'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = (photo.description ?? '').trim();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: CachedNetworkImage(
            imageUrl: photo.url,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (context, url, error) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          color: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _dateLabel(photo.createdAt),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
