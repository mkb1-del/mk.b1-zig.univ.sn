import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/follow_up_service.dart';
import '../../models/user_model.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';
import 'create_prescription_view.dart';

/// Les ordonnances déjà prescrites par ce médecin à une patiente.
class _Past {
  final int count;
  final DateTime last;

  const _Past({required this.count, required this.last});
}

/// Écran "Prescrire" : le médecin choisit une patiente, puis le formulaire
/// d'ordonnance s'ouvre directement. Chaque patiente porte son contexte :
/// alerte de suivi et ordonnances déjà prescrites.
///
/// - embedded = false : page complète avec sa propre barre (route /doctor-prescribe)
/// - embedded = true  : contenu seul, à placer dans un onglet de doctor_home_view
class SelectPatientPrescriptionView extends StatefulWidget {
  final bool embedded;

  const SelectPatientPrescriptionView({super.key, this.embedded = false});

  @override
  State<SelectPatientPrescriptionView> createState() =>
      _SelectPatientPrescriptionViewState();
}

class _SelectPatientPrescriptionViewState
    extends State<SelectPatientPrescriptionView> {
  final AuthService _authService = AuthService();
  final FollowUpService _followUp = FollowUpService();
  final TextEditingController _searchController = TextEditingController();

  List<UserModel> _patients = [];
  Map<String, int> _alerts = {};
  Map<String, _Past> _past = {};
  bool _isLoading = true;
  bool _watchOnly = false;
  String _query = '';

  static const List<String> _monthsShort = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ Données

  Future<void> _loadPatients({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    // Patientes, alertes de suivi et ordonnances déjà prescrites : trois lectures indépendantes.
    final (patients, alerts, past) = await (
      _authService.getAllPatients(),
      _followUp.loadAlerts(),
      _loadPast(),
    ).wait;

    if (!mounted) return;
    setState(() {
      _patients = patients;
      _alerts = alerts;
      _past = past;
      _isLoading = false;
    });
  }

  /// Pour chaque patiente : combien d'ordonnances ce médecin lui a prescrites,
  /// et la date de la dernière. Une seule requête pour toutes.
  Future<Map<String, _Past>> _loadPast() async {
    final out = <String, _Past>{};
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return out;
    try {
      final rows = await Supabase.instance.client
          .from('prescriptions')
          .select('patient_id, created_at')
          .eq('doctor_id', me)
          .order('created_at', ascending: false)
          .limit(500);
      final counts = <String, int>{};
      final lasts = <String, DateTime>{};
      for (final r in rows) {
        final id = r['patient_id']?.toString() ?? '';
        final at = DateTime.tryParse(r['created_at']?.toString() ?? '');
        if (id.isEmpty || at == null) continue;
        counts[id] = (counts[id] ?? 0) + 1;
        lasts.putIfAbsent(id, () => at.toLocal());
      }
      for (final id in counts.keys) {
        out[id] = _Past(count: counts[id]!, last: lasts[id]!);
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement des ordonnances passées : $e');
    }
    return out;
  }

  // ------------------------------------------------------------ Actions

  Future<void> _prescribeFor(UserModel patient) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePrescriptionView(
          patientId: patient.id,
          patientName: patient.name,
        ),
      ),
    );

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Ordonnance envoyée à ${patient.name}'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadPatients(silent: true);
    }
  }

  // ------------------------------------------------------------ Aides

  Color _darker(Color c) => Color.lerp(c, Colors.black, 0.4)!;

  String _shortDate(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

  bool _matches(UserModel p) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || p.name.toLowerCase().contains(q);
  }

  // ------------------------------------------------------------ Éléments d'interface

  Widget _buildHeader(int total, int watch) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prescrire',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            'Choisissez la patiente · $total patiente${total > 1 ? 's' : ''}'
            '${watch > 0 ? ' · $watch à surveiller' : ''}',
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Rechercher une patiente...',
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
    );
  }

  Widget _buildFilters(int watch) {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('Toutes'),
          selected: !_watchOnly,
          showCheckmark: false,
          onSelected: (_) => setState(() => _watchOnly = false),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text('À surveiller ($watch)'),
          selected: _watchOnly,
          showCheckmark: false,
          onSelected: (_) => setState(() => _watchOnly = true),
        ),
      ],
    );
  }

  Widget _buildCard(UserModel patient) {
    final alertDays = _alerts[patient.id] ?? 0;
    final past = _past[patient.id];
    final alertColor = alertDays >= 2 ? AppColors.danger : AppColors.amber;

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _prescribeFor(patient),
      child: Row(
        children: [
          UserAvatar(name: patient.name, url: patient.avatarUrl, radius: 25),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  past == null
                      ? 'Aucune ordonnance prescrite'
                      : '${past.count} ordonnance${past.count > 1 ? 's' : ''} · dernière le ${_shortDate(past.last)}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                if (alertDays > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: alertColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.monitor_heart_outlined, size: 13, color: _darker(alertColor)),
                        const SizedBox(width: 4),
                        Text(
                          'À surveiller · $alertDays jour${alertDays > 1 ? 's' : ''} difficile${alertDays > 1 ? 's' : ''}',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _darker(alertColor)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _prescribeFor(patient),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('Prescrire'),
          ),
        ],
      ),
    );
  }

  Widget _emptyBlock(IconData icon, String title, String message) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.roseSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.rose),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonList();
    }

    if (_patients.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.embedded) _buildHeader(0, 0),
          _emptyBlock(
            Icons.people_outline,
            'Aucune patiente disponible',
            'Seules les patientes ayant un compte peuvent recevoir une ordonnance. Elles apparaissent ici dès qu\'elles vous ont ajouté à leur équipe médicale.',
          ),
        ],
      );
    }

    final watch = _patients.where((p) => (_alerts[p.id] ?? 0) > 0).length;

    // Les patientes à surveiller d'abord, puis l'ordre alphabétique.
    final list = _patients
        .where(_matches)
        .where((p) => !_watchOnly || (_alerts[p.id] ?? 0) > 0)
        .toList()
      ..sort((a, b) {
        final wa = _alerts[a.id] ?? 0;
        final wb = _alerts[b.id] ?? 0;
        if (wa != wb) return wb.compareTo(wa);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _loadPatients(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.embedded) _buildHeader(_patients.length, watch),
          if (_patients.length >= 5) ...[
            _buildSearch(),
            const SizedBox(height: 12),
          ],
          if (watch > 0) ...[
            _buildFilters(watch),
            const SizedBox(height: 16),
          ],
          if (list.isEmpty)
            _emptyBlock(
              Icons.search_off,
              'Aucune patiente trouvée',
              _query.trim().isNotEmpty
                  ? 'Aucun résultat pour « ${_query.trim()} ».'
                  : 'Aucune patiente n\'est à surveiller.',
            )
          else
            for (var i = 0; i < list.length; i++) ...[
              _buildCard(list[i]),
              if (i < list.length - 1) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildContent();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Prescrire une ordonnance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: _loadPatients,
          ),
        ],
      ),
      body: _buildContent(),
    );
  }
}