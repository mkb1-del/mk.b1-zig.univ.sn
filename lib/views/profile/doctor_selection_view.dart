import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/care_team_service.dart';
import '../../services/doctor_directory_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';

/// « Mon équipe médicale » : la patiente compose l'équipe des médecins qui la
/// suivent (oncologue, chirurgien, radiothérapeute...). Ajouter un médecin
/// l'autorise à consulter son suivi. Ce choix est définitif : l'application ne
/// permet pas de retirer un médecin.
class DoctorSelectionView extends StatefulWidget {
  const DoctorSelectionView({super.key});

  @override
  State<DoctorSelectionView> createState() => _DoctorSelectionViewState();
}

class _DoctorSelectionViewState extends State<DoctorSelectionView> {
  final AuthService _authService = AuthService();
  final CareTeamService _careTeam = CareTeamService();
  final DoctorDirectoryService _directory = DoctorDirectoryService();
  final TextEditingController _searchController = TextEditingController();

  List<TeamMember> _team = [];
  List<UserModel> _allDoctors = [];
  Map<String, String> _hospitals = {};
  String _query = '';
  bool _isLoading = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      // Équipe, médecins et hôpitaux : trois lectures indépendantes.
      final (team, doctors, hospitals) = await (
        _careTeam.getTeam(),
        _authService.getAllDoctors(),
        _directory.loadHospitals(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _team = team;
        _allDoctors = doctors;
        _hospitals = hospitals;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement équipe: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ------------------------------------------------------------- Actions

  Future<void> _run(Future<bool> Function() action, String successMessage) async {
    setState(() => _isBusy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _isBusy = false);

    final error = _careTeam.lastError ?? '';
    final notReady = error.contains('Could not find') ||
        error.contains('care_team') ||
        error.contains('PGRST');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? successMessage
              : (notReady
                  ? 'Cette fonction n\'est pas encore activée sur le serveur (script « équipe médicale » à exécuter).'
                  : '❌ Action impossible. Vérifiez votre connexion et réessayez.'),
        ),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
      ),
    );
    if (ok) _load(silent: true);
  }

  Future<void> _confirmAdd(UserModel doctor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ajouter Dr ${doctor.name} ?'),
        content: const Text(
          'Ce médecin pourra consulter votre suivi : symptômes, humeur et prises de médicaments.\n\nAttention : ce choix est définitif. Vous ne pourrez pas retirer ce médecin de votre équipe depuis l\'application.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _run(
      () => _careTeam.addDoctor(doctor.id),
      'Dr ${doctor.name} a été ajouté à votre équipe',
    );
  }

  Future<void> _makePrimary(TeamMember member) {
    return _run(
      () => _careTeam.setPrimary(member.doctor.id),
      'Dr ${member.doctor.name} est maintenant votre médecin référent',
    );
  }

  // ------------------------------------------------------------------ UI

  List<UserModel> get _candidates {
    final inTeam = _team.map((m) => m.doctor.id).toSet();
    final q = _query.trim().toLowerCase();
    return _allDoctors.where((d) {
      if (inTeam.contains(d.id)) return false;
      if (q.isEmpty) return true;
      return d.name.toLowerCase().contains(q) ||
          (d.specialty ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Widget _avatar(UserModel doctor) {
    return UserAvatar(name: doctor.name, url: doctor.avatarUrl, radius: 24);
  }

  /// Ligne « hôpital » sous la spécialité (rien si non renseigné).
  Widget _hospitalLine(String hospital) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          const Icon(Icons.local_hospital_outlined, size: 13, color: AppColors.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              hospital,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return const AppCard(
      color: AppColors.roseSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.groups_outlined, color: AppColors.rose),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Plusieurs médecins peuvent vous suivre, chacun dans sa spécialité. Les médecins de votre équipe peuvent consulter votre suivi (symptômes, humeur, prises de médicaments). Choisissez-les avec soin : une fois ajouté, un médecin ne peut plus être retiré depuis l\'application.',
              style: TextStyle(fontSize: 13, color: AppColors.ink, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMember(TeamMember member) {
    final doctor = member.doctor;
    final specialty = (doctor.specialty ?? '').trim();
    final hospital = _hospitals[doctor.id] ?? '';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          _avatar(doctor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dr ${doctor.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                if (specialty.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    specialty,
                    style: const TextStyle(fontSize: 13, color: AppColors.rose),
                  ),
                ],
                if (hospital.isNotEmpty) _hospitalLine(hospital),
                if (member.isPrimary) ...[
                  const SizedBox(height: 6),
                  const StatusPill(label: 'Médecin référent', color: AppColors.rose),
                ],
              ],
            ),
          ),
          if (!member.isPrimary)
            PopupMenuButton<String>(
              enabled: !_isBusy,
              icon: const Icon(Icons.more_vert, color: AppColors.muted),
              onSelected: (value) {
                if (value == 'primary') _makePrimary(member);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'primary',
                  child: Text('Définir comme référent'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCandidate(UserModel doctor) {
    final specialty = (doctor.specialty ?? '').trim();
    final hospital = _hospitals[doctor.id] ?? '';

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _avatar(doctor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dr ${doctor.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (specialty.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    specialty,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ],
                if (hospital.isNotEmpty) _hospitalLine(hospital),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _isBusy ? null : () => _confirmAdd(doctor),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonList();
    }

    final candidates = _candidates;

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildIntro(),
          const SizedBox(height: 24),
          SectionTitle(title: 'Mon équipe (${_team.length})'),
          if (_team.isEmpty)
            const AppCard(
              child: Text(
                'Votre équipe est vide. Ajoutez les médecins qui vous suivent ci-dessous.',
                style: TextStyle(color: AppColors.muted, height: 1.4),
              ),
            )
          else
            for (var i = 0; i < _team.length; i++) ...[
              _buildMember(_team[i]),
              if (i < _team.length - 1) const SizedBox(height: 12),
            ],
          const SizedBox(height: 28),
          const SectionTitle(title: 'Ajouter un médecin'),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Rechercher par nom ou spécialité',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _query.isEmpty
                      ? 'Aucun autre médecin disponible pour le moment.'
                      : 'Aucun médecin ne correspond à votre recherche.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else
            for (var i = 0; i < candidates.length; i++) ...[
              _buildCandidate(candidates[i]),
              if (i < candidates.length - 1) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon équipe médicale')),
      body: Column(
        children: [
          if (_isBusy) const LinearProgressIndicator(minHeight: 3),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }
}
