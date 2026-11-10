import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../widgets/skeleton.dart';
import '../../services/app_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../services/doctor_directory_service.dart';
import '../../models/user_model.dart';
import '../../theme/app_role.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/avatar_picker.dart';
import '../../widgets/ribbon_background.dart';
import '../../widgets/user_avatar.dart';

/// Profil du médecin : identité et complétude du profil, chiffres clés,
/// informations professionnelles (spécialité, hôpital), raccourcis, sécurité et aide.
class DoctorProfileView extends StatefulWidget {
  /// true : utilisé comme onglet de doctor_home_view (sans barre du haut).
  /// false : page indépendante (route /doctor-profile) avec sa propre barre.
  final bool embedded;

  const DoctorProfileView({super.key, this.embedded = false});

  @override
  State<DoctorProfileView> createState() => _DoctorProfileViewState();
}

class _DoctorProfileViewState extends State<DoctorProfileView> {
  final AuthService _authService = AuthService();
  final DoctorDirectoryService _directory = DoctorDirectoryService();
  UserModel? _doctor;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;

  /// Version lue dans pubspec.yaml ; vide si indisponible (ex. test dans le navigateur).
  String _appVersion = '';
  String _buildNumber = '';

  int _patientsCount = 0;
  int _prescriptionsCount = 0;
  int _appointmentsCount = 0;

  String _hospital = '';

  /// Établissements déjà utilisés par les médecins : proposés à la saisie
  /// pour éviter les fautes et les doublons (« Hôpital Principal » / « Hopital principal »).
  List<String> _hospitalChoices = [];

  final _nameController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _hospitalController = TextEditingController();

  static const List<String> _specialtyChoices = [
    'Oncologie médicale',
    'Chirurgie oncologique',
    'Radiothérapie',
    'Chimiothérapie',
    'Gynécologie',
    'Médecine générale',
  ];

  @override
  void initState() {
    super.initState();
    _loadDoctorData();
    _loadVersion();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specialtyController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _hospitalController.dispose();
    super.dispose();
  }

  /// Lit la version de l'application dans pubspec.yaml (une seule source).
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (e) {
      debugPrint('❌ Version de l\'application indisponible : $e');
    }
  }

  /// « Version 1.0.0 (1) », ou une indication si elle n'a pas pu être lue.
  String get _versionLabel {
    if (_appVersion.isEmpty) return 'Version non disponible';
    final showBuild = _buildNumber.isNotEmpty && _buildNumber != _appVersion;
    return showBuild ? 'Version $_appVersion ($_buildNumber)' : 'Version $_appVersion';
  }

  void _fillControllers(UserModel doctor) {
    _nameController.text = doctor.name;
    _specialtyController.text = doctor.specialty ?? '';
    _phoneController.text = doctor.phone ?? '';
    _bioController.text = doctor.bio ?? '';
    _hospitalController.text = _hospital;
  }

  Future<int> _countRows(String table, String doctorId) async {
    try {
      final res = await Supabase.instance.client
          .from(table)
          .select('id')
          .eq('doctor_id', doctorId);
      return res.length;
    } catch (e) {
      debugPrint('❌ Erreur comptage $table: $e');
      return 0;
    }
  }

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _loadDoctorData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final doctor = await _authService.getCurrentUser(forceRefresh: true);

      var hospital = '';
      var patients = 0;
      var prescriptions = 0;
      var appointments = 0;
      Map<String, String> allHospitals = {};

      if (doctor != null) {
        // Cinq lectures indépendantes : elles partent ensemble.
        (hospital, patients, prescriptions, appointments, allHospitals) = await (
          _directory.hospitalOf(doctor.id),
          _authService.getAllPatients().then((list) => list.length),
          _countRows('prescriptions', doctor.id),
          _countRows('appointments', doctor.id),
          _directory.loadHospitals(),
        ).wait;
      }

      final choices = allHospitals.values
          .map((h) => h.trim())
          .where((h) => h.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (mounted) {
        setState(() {
          _doctor = doctor;
          _hospital = hospital;
          _hospitalChoices = choices;
          _patientsCount = patients;
          _prescriptionsCount = prescriptions;
          _appointmentsCount = appointments;
          // On ne touche pas aux champs si l'utilisateur est en train d'éditer.
          if (doctor != null && !_isEditing) _fillControllers(doctor);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement profil: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_doctor == null) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le nom ne peut pas être vide'),
          backgroundColor: AppColors.amber,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updatedData = {
        'name': name,
        'specialty': _specialtyController.text.trim(),
        'phone': _phoneController.text.trim(),
        'bio': _bioController.text.trim(),
        'hospital': _hospitalController.text.trim(),
      };

      var success = await _authService.updateProfile(_doctor!.id, updatedData);
      if (!success) {
        // Colonne « hôpital » pas encore créée sur le serveur : on enregistre le reste.
        final withoutHospital = Map<String, dynamic>.from(updatedData)
          ..remove('hospital');
        success = await _authService.updateProfile(_doctor!.id, withoutHospital);
      }
      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profil mis à jour avec succès'),
            backgroundColor: AppColors.teal,
          ),
        );
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
        await _loadDoctorData(silent: true);
      } else {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Erreur lors de la mise à jour (voir la console)'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _startEditing() => setState(() => _isEditing = true);

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      if (_doctor != null) _fillControllers(_doctor!);
    });
  }

  /// Vrai si au moins un champ a été modifié (le bouton Enregistrer en dépend).
  bool get _isDirty {
    final d = _doctor;
    if (d == null) return false;
    return _nameController.text.trim() != d.name ||
        _specialtyController.text.trim() != (d.specialty ?? '').trim() ||
        _hospitalController.text.trim() != _hospital.trim() ||
        _phoneController.text.trim() != (d.phone ?? '').trim() ||
        _bioController.text.trim() != (d.bio ?? '').trim();
  }

  void _openRoute(String route) {
    Navigator.pushNamed(context, route).then((_) {
      if (mounted) _loadDoctorData(silent: true);
    });
  }

  /// Changer ma photo de profil (appareil photo, galerie ou suppression).
  Future<void> _changeAvatar() async {
    final changed = await changeProfilePhoto(
      context,
      hasPhoto: (_doctor?.avatarUrl ?? '').trim().isNotEmpty,
    );
    if (changed && mounted) _loadDoctorData(silent: true);
  }

  /// Retour : écran précédent, ou accueil médecin si la page a été rechargée directement ici.
  void _goBack() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed('/doctor_home');
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copié'), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _logout() async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: AppColors.danger),
            SizedBox(width: 10),
            Text('Déconnexion'),
          ],
        ),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
      } catch (e) {
        debugPrint('❌ Erreur déconnexion: $e');
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
  }

  /// L'email vit dans le compte d'authentification, pas dans la table profiles.
  String get _email {
    final authEmail = Supabase.instance.client.auth.currentUser?.email;
    if (authEmail != null && authEmail.isNotEmpty) return authEmail;
    final fromProfile = _doctor?.email ?? '';
    return fromProfile.isNotEmpty ? fromProfile : 'Non renseigné';
  }

  // ------------------------------------------------------------ Sécurité et aide

  Future<void> _changePassword() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adresse email introuvable pour ce compte.'),
          backgroundColor: AppColors.amber,
        ),
      );
      return;
    }

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _PasswordSheet(email: email),
    );

    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Mot de passe modifié'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Widget _dialogPoint(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.rose),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacy() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confidentialité et secret médical'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dialogPoint(Icons.groups_outlined,
                  'Vous ne voyez le suivi de santé (humeur, symptômes, prises de médicaments) que des patientes qui vous ont ajouté à leur équipe médicale.'),
              _dialogPoint(Icons.event_note_outlined,
                  'Les rendez-vous et les ordonnances que vous créez sont visibles par la patiente concernée.'),
              _dialogPoint(Icons.chat_bubble_outline,
                  'Vos messages ne sont visibles que par vous et la personne avec qui vous échangez.'),
              _dialogPoint(Icons.gavel_outlined,
                  'Rappel : les informations de santé de vos patientes sont soumises au secret professionnel. Ne les partagez pas en dehors de l\'application.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            RibbonLogo(size: 22, color: AppColors.rose),
            SizedBox(width: 10),
            Text('Sunu Yaakaar'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _versionLabel,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            const Text(
              'Application de suivi pour les patientes atteintes d\'un cancer du sein : suivi, rendez-vous, ordonnances, rappels et messages entre la patiente et son équipe médicale.',
              style: TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Elle ne remplace ni votre jugement clinique ni les consignes d\'urgence en vigueur.',
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ UI : en-tête

  Widget _circle(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }

  /// Ce qui manque encore au profil.
  List<String> get _missing {
    final d = _doctor;
    return [
      if ((d?.avatarUrl ?? '').trim().isEmpty) 'photo',
      if ((d?.specialty ?? '').trim().isEmpty) 'spécialité',
      if (_hospital.trim().isEmpty) 'hôpital',
      if ((d?.phone ?? '').trim().isEmpty) 'téléphone',
      if ((d?.bio ?? '').trim().isEmpty) 'à propos',
    ];
  }

  Widget _buildHero() {
    final missing = _missing;
    final done = 5 - missing.length;
    final pct = (done / 5 * 100).round();
    final specialty = (_doctor?.specialty ?? '').trim();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppRole.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppRole.headerShadow.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(top: -40, right: -30, child: _circle(150, 0.08)),
            Positioned(bottom: -50, left: -30, child: _circle(120, 0.06)),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _changeAvatar,
                        child: Semantics(
                          button: true,
                          label: 'Changer ma photo de profil',
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: UserAvatar(
                                  name: _doctor?.name ?? '',
                                  url: _doctor?.avatarUrl,
                                  radius: 38,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.rose,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.photo_camera, size: 14, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dr ${_doctor?.name ?? 'Médecin'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.medical_services_outlined, size: 14, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      specialty.isEmpty ? 'Médecin' : specialty,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_hospital.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.local_hospital_outlined, size: 14, color: Colors.white70),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      _hospital,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pct == 100 ? 'Profil complet' : 'Profil complété à $pct %',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        pct == 100 ? Icons.verified_outlined : Icons.edit_note,
                        size: 17,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: done / 5,
                      minHeight: 7,
                      backgroundColor: Colors.white24,
                      color: Colors.white,
                    ),
                  ),
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'À compléter : ${missing.join(' · ')}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ UI : chiffres clés

  Widget _stat(IconData icon, Color color, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _stat(Icons.people_alt_outlined, AppColors.rose, '$_patientsCount', 'Patientes'),
            const VerticalDivider(width: 1),
            _stat(Icons.description_outlined, AppColors.violet, '$_prescriptionsCount', 'Ordonnances'),
            const VerticalDivider(width: 1),
            _stat(Icons.event_available_outlined, AppColors.teal, '$_appointmentsCount', 'Rendez-vous'),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ UI : informations

  Widget _infoRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool placeholder = false,
    String? note,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: placeholder ? FontWeight.w400 : FontWeight.w600,
                      fontStyle: placeholder ? FontStyle.italic : FontStyle.normal,
                      color: placeholder ? AppColors.muted : AppColors.ink,
                    ),
                  ),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(note, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      ),
    );
  }

  Widget _copyIcon() => const Icon(Icons.copy, size: 16, color: AppColors.muted);

  Widget _addLink() => const Text(
        'Ajouter',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.rose),
      );

  Widget _buildInfoCard() {
    final specialty = (_doctor?.specialty ?? '').trim();
    final hospital = _hospital.trim();
    final phone = (_doctor?.phone ?? '').trim();
    final bio = (_doctor?.bio ?? '').trim();
    final email = _email;
    final hasEmail = email != 'Non renseigné';

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          _infoRow(
            icon: Icons.mail_outline,
            color: AppColors.sky,
            label: 'Email',
            value: email,
            placeholder: !hasEmail,
            onTap: hasEmail ? () => _copy('Email', email) : null,
            trailing: hasEmail ? _copyIcon() : null,
          ),
          const Divider(),
          _infoRow(
            icon: Icons.medical_services_outlined,
            color: AppColors.rose,
            label: 'Spécialité',
            value: specialty.isEmpty ? 'Non renseignée' : specialty,
            placeholder: specialty.isEmpty,
            note: specialty.isEmpty ? null : 'Visible par les patientes qui vous choisissent',
            onTap: _startEditing,
            trailing: specialty.isEmpty ? _addLink() : null,
          ),
          const Divider(),
          _infoRow(
            icon: Icons.local_hospital_outlined,
            color: AppColors.violet,
            label: 'Hôpital ou établissement',
            value: hospital.isEmpty ? 'Non renseigné' : hospital,
            placeholder: hospital.isEmpty,
            note: 'Figure sur vos ordonnances et vos rendez-vous',
            onTap: _startEditing,
            trailing: hospital.isEmpty ? _addLink() : null,
          ),
          const Divider(),
          _infoRow(
            icon: Icons.phone_outlined,
            color: AppColors.teal,
            label: 'Téléphone',
            value: phone.isEmpty ? 'Non renseigné' : phone,
            placeholder: phone.isEmpty,
            onTap: phone.isEmpty ? _startEditing : () => _copy('Téléphone', phone),
            trailing: phone.isEmpty ? _addLink() : _copyIcon(),
          ),
          const Divider(),
          _infoRow(
            icon: Icons.notes,
            color: AppColors.plum,
            label: 'À propos',
            value: bio.isEmpty ? 'Présentez votre parcours en quelques mots' : bio,
            placeholder: bio.isEmpty,
            onTap: _startEditing,
            trailing: bio.isEmpty ? _addLink() : null,
          ),
        ],
      ),
    );
  }

  Widget _suggestions(List<String> items, TextEditingController controller) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        children: [
          for (final s in items)
            ActionChip(
              label: Text(s),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => controller.text = s),
            ),
        ],
      ),
    );
  }

  Widget _buildEditCard() {
    return AppCard(
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nom',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _specialtyController,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Spécialité',
              prefixIcon: Icon(Icons.medical_services_outlined),
            ),
          ),
          const SizedBox(height: 6),
          _suggestions(_specialtyChoices, _specialtyController),
          const SizedBox(height: 14),
          TextField(
            controller: _hospitalController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Hôpital ou établissement',
              helperText: 'Figure sur vos ordonnances et vos rendez-vous',
              prefixIcon: Icon(Icons.local_hospital_outlined),
            ),
          ),
          if (_hospitalChoices.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Établissements déjà utilisés :',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 4),
            _suggestions(_hospitalChoices.take(6).toList(), _hospitalController),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Téléphone',
              hintText: 'Ex : 221 77 123 45 67',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 200,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'À propos',
              hintText: 'Votre parcours, vos domaines d\'intérêt (facultatif)',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 15, color: AppColors.muted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'L\'adresse email est celle de votre compte : elle ne se modifie pas ici.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ UI : raccourcis, sécurité, aide

  Widget _menuTile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _menuGroup(List<Widget> tiles) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1) const Divider(height: 1, indent: 70),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActivityGroup() {
    return _menuGroup([
      _menuTile(
        icon: Icons.insights_outlined,
        color: AppColors.rose,
        title: 'Statistiques',
        subtitle: 'Patientes, ordonnances, rendez-vous',
        onTap: () => _openRoute('/doctor-statistics'),
      ),
      _menuTile(
        icon: Icons.description_outlined,
        color: AppColors.violet,
        title: 'Mes ordonnances',
        subtitle: 'Consulter l\'historique',
        onTap: () => _openRoute('/doctor-prescriptions'),
      ),
      _menuTile(
        icon: Icons.person_add_alt_1,
        color: AppColors.teal,
        title: 'Ajouter une patiente',
        subtitle: 'Créer un dossier',
        onTap: () => _openRoute('/add-patient'),
      ),
    ]);
  }

  Widget _buildSecurityGroup() {
    return _menuGroup([
      _menuTile(
        icon: Icons.lock_reset_outlined,
        color: AppColors.rose,
        title: 'Changer mon mot de passe',
        onTap: _changePassword,
      ),
      _menuTile(
        icon: Icons.privacy_tip_outlined,
        color: AppColors.violet,
        title: 'Confidentialité et secret médical',
        subtitle: 'Ce que vous pouvez voir, et pourquoi',
        onTap: _showPrivacy,
      ),
      _menuTile(
        icon: Icons.info_outline,
        color: AppColors.teal,
        title: 'À propos de Sunu Yaakaar',
        subtitle: _versionLabel,
        onTap: _showAbout,
      ),
    ]);
  }

  // ------------------------------------------------------------------ UI : actions

  Widget _buildActions() {
    if (_isEditing) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: (_isSaving || !_isDirty) ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_isSaving ? 'Enregistrement...' : 'Enregistrer'),
            ),
          ),
          if (!_isDirty && !_isSaving)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Modifiez un champ pour activer l\'enregistrement.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _isSaving ? null : _cancelEditing,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.muted,
                side: const BorderSide(color: AppColors.border),
              ),
              child: const Text('Annuler'),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout),
        label: const Text('Se déconnecter'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: AppColors.danger),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _loadDoctorData(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(),
            const SizedBox(height: 16),
            if (!_isEditing) ...[
              _buildStats(),
              const SizedBox(height: 24),
            ],
            SectionTitle(
              title: _isEditing ? 'Modifier mes informations' : 'Informations professionnelles',
              actionLabel: _isEditing ? null : 'Modifier',
              onAction: _startEditing,
            ),
            _isEditing ? _buildEditCard() : _buildInfoCard(),
            if (!_isEditing) ...[
              const SizedBox(height: 24),
              const SectionTitle(title: 'Mon activité'),
              _buildActivityGroup(),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Sécurité et aide'),
              _buildSecurityGroup(),
            ],
            const SizedBox(height: 24),
            _buildActions(),
            const SizedBox(height: 20),
            Center(
              child: Text(
                _appVersion.isEmpty ? 'Sunu Yaakaar' : 'Sunu Yaakaar · v$_appVersion',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Retour',
                onPressed: _goBack,
              ),
              title: const Text('Mon profil'),
            ),
      body: _isLoading ? const SkeletonProfile() : _buildContent(),
    );
  }
}

// ====================================================================
// Changement de mot de passe
// ====================================================================

/// Feuille de changement de mot de passe : on vérifie d'abord le mot de passe
/// actuel, puis on enregistre le nouveau. Renvoie true si le changement a réussi.
class _PasswordSheet extends StatefulWidget {
  final String email;

  const _PasswordSheet({required this.email});

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text;
    final next = _new.text;

    String? problem;
    if (current.isEmpty) {
      problem = 'Saisissez votre mot de passe actuel.';
    } else if (next.length < 6) {
      problem = 'Le nouveau mot de passe doit contenir au moins 6 caractères.';
    } else if (next == current) {
      problem = 'Le nouveau mot de passe doit être différent de l\'actuel.';
    } else if (next != _confirm.text) {
      problem = 'Les deux mots de passe ne correspondent pas.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      // Vérifie le mot de passe actuel, puis enregistre le nouveau.
      await client.auth.signInWithPassword(email: widget.email, password: current);
      await client.auth.updateUser(UserAttributes(password: next));
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      setState(() {
        _busy = false;
        _error = m.contains('invalid')
            ? 'Mot de passe actuel incorrect.'
            : AppErrors.message(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppErrors.message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Changer mon mot de passe',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            const Text(
              'Par sécurité, saisissez d\'abord votre mot de passe actuel.',
              style: TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _current,
              obscureText: !_showCurrent,
              decoration: InputDecoration(
                labelText: 'Mot de passe actuel',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showCurrent ? 'Masquer' : 'Afficher',
                  icon: Icon(_showCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showCurrent = !_showCurrent),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _new,
              obscureText: !_showNew,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                helperText: '6 caractères minimum',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  tooltip: _showNew ? 'Masquer' : 'Afficher',
                  icon: Icon(_showNew ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showNew = !_showNew),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _confirm,
              obscureText: !_showNew,
              decoration: const InputDecoration(
                labelText: 'Confirmer le nouveau mot de passe',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.dangerText, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Enregistrer le nouveau mot de passe',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}