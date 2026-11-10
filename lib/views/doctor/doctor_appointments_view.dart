import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import '../../services/app_errors.dart';
import '../../services/appointment_ticket.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';

class DoctorAppointmentsView extends StatefulWidget {
  /// true : utilisé comme contenu d'un onglet (sans barre du haut, car
  /// doctor_home_view en a déjà une).
  final bool embedded;

  const DoctorAppointmentsView({super.key, this.embedded = false});

  @override
  State<DoctorAppointmentsView> createState() => _DoctorAppointmentsViewState();
}

class _DoctorAppointmentsViewState extends State<DoctorAppointmentsView> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _appointments = [];
  bool _isLoading = true;
  String _filter = 'all';

  // Recherche par numéro de ticket (RDV-XXXXXXXX) ou par nom de patiente.
  final _searchController = TextEditingController();
  String _query = '';

  static const List<String> _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  static const List<MapEntry<String, String>> _filters = [
    MapEntry('all', 'Tous'),
    MapEntry('today', 'Aujourd\'hui'),
    MapEntry('upcoming', 'À venir'),
    MapEntry('pending', 'En attente'),
    MapEntry('completed', 'Terminés'),
  ];

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- Helpers

  String _two(int n) => n.toString().padLeft(2, '0');

  DateTime? _dateTimeOf(Map<String, dynamic> a) {
    final date = a['date']?.toString() ?? '';
    final time = a['time']?.toString() ?? '';
    if (date.isEmpty) return null;
    return DateTime.tryParse(time.isEmpty ? date : '$date $time');
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  bool _isUpcoming(Map<String, dynamic> a) {
    final status = a['status']?.toString();
    if (status == 'cancelled' || status == 'completed') return false;
    final dt = _dateTimeOf(a);
    if (dt == null) return false;
    final now = DateTime.now();
    return !dt.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// Garde seulement les lettres et chiffres, en majuscules : « rdv-3f9a 1c2b »
  /// et « RDV3F9A1C2B » deviennent identiques.
  static String _normalize(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Le rendez-vous correspond-il à la recherche ? On compare avec son numéro de
  /// ticket (en entier ou en partie) et avec le nom de la patiente.
  bool _matchesQuery(Map<String, dynamic> a) {
    final q = _query.trim();
    if (q.isEmpty) return true;

    final wanted = _normalize(q);
    final code = _normalize(AppointmentTicket.codeFor(a['id'].toString()));
    if (wanted.isNotEmpty && code.contains(wanted)) return true;

    final patient = (a['patient_name']?.toString() ?? '').toLowerCase();
    return patient.contains(q.toLowerCase());
  }

  List<Map<String, dynamic>> get _filtered {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);

    // Pendant une recherche, on cherche dans TOUS les rendez-vous, quel que soit
    // le filtre choisi, du plus récent au plus ancien.
    if (_query.trim().isNotEmpty) {
      final found = _appointments.where(_matchesQuery).toList();
      found.sort((a, b) =>
          (_dateTimeOf(b) ?? epoch).compareTo(_dateTimeOf(a) ?? epoch));
      return found;
    }

    final list = _appointments.where((a) {
      final dt = _dateTimeOf(a);
      switch (_filter) {
        case 'today':
          return dt != null && _isToday(dt) && a['status'] != 'cancelled';
        case 'upcoming':
          return _isUpcoming(a);
        case 'pending':
          return a['status'] == 'pending';
        case 'completed':
          return a['status'] == 'completed';
        default:
          return true;
      }
    }).toList();

    final descending = _filter == 'completed';
    list.sort((a, b) {
      final cmp = (_dateTimeOf(a) ?? epoch).compareTo(_dateTimeOf(b) ?? epoch);
      return descending ? -cmp : cmp;
    });
    return list;
  }

  // ------------------------------------------------------------ Données

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _loadAppointments({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final response =
          await _supabase.from('appointments').select().eq('doctor_id', userId);
      if (!mounted) return;
      setState(() {
        _appointments = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement RDV médecin: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(String id, String status, String message) async {
    try {
      await _supabase.from('appointments').update({'status': status}).eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              status == 'cancelled' ? AppColors.amber : AppColors.success,
        ),
      );
      _loadAppointments(silent: true);
    } catch (e) {
      debugPrint('❌ Erreur mise à jour RDV: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Mise à jour impossible. ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _confirmCancel(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler le rendez-vous'),
        content: const Text('Voulez-vous vraiment annuler ce rendez-vous ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _updateStatus(id, 'cancelled', 'Rendez-vous annulé');
    }
  }

  Future<void> _openCreate() async {
    final result = await Navigator.pushNamed(context, '/create-appointment');
    if (result == true && mounted) _loadAppointments(silent: true);
  }

  // ------------------------------------------------------------------ UI

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          hintText: 'Numéro de ticket ou nom de la patiente',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer la recherche',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = _filters[index];
          return FilterChip(
            label: Text(f.value),
            selected: _filter == f.key,
            onSelected: (_) => setState(() => _filter = f.key),
          );
        },
      ),
    );
  }

  Widget _action(String label, IconData icon, Color color, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(foregroundColor: color),
    );
  }

  Widget _buildCard(Map<String, dynamic> a) {
    final status = a['status']?.toString() ?? 'pending';
    final dt = _dateTimeOf(a);
    final patient = (a['patient_name']?.toString() ?? '').trim();
    final reason = (a['reason']?.toString() ?? '').trim();
    final id = a['id'].toString();
    final inactive = status == 'cancelled' || status == 'completed';
    final tint = inactive ? AppColors.muted : AppColors.rose;

    final day = dt == null ? '--' : _two(dt.day);
    final month = dt == null ? '' : _months[dt.month - 1];
    final time = dt == null ? '' : '${_two(dt.hour)}:${_two(dt.minute)}';

    final actions = <Widget>[
      if (status == 'pending')
        _action('Confirmer', Icons.check_circle_outline, AppColors.success,
            () => _updateStatus(id, 'confirmed', 'Rendez-vous confirmé')),
      if (status == 'confirmed')
        _action('Terminer', Icons.task_alt, AppColors.success,
            () => _updateStatus(id, 'completed', 'Rendez-vous terminé')),
      if (!inactive)
        _action('Annuler', Icons.close, AppColors.danger, () => _confirmCancel(id)),
    ];

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      day,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: tint,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(month, style: TextStyle(fontSize: 12, color: tint)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.isEmpty ? 'Patiente' : patient,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reason.isEmpty ? time : '$time · $reason',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'N° ${AppointmentTicket.codeFor(a['id'].toString())}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatusPill(
                      label: StatusStyle.label(status),
                      color: StatusStyle.color(status),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 4, children: actions),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList() {
    final list = _filtered;
    final searching = _query.trim().isNotEmpty;

    return Column(
      children: [
        const SizedBox(height: 8),
        _buildSearchBar(),
        const SizedBox(height: 8),
        if (searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${list.length} résultat${list.length > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
          )
        else ...[
          _buildFilters(),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: RefreshIndicator(
            color: AppColors.rose,
            onRefresh: () => _loadAppointments(silent: true),
            child: list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 60),
                      EmptyState(
                        icon: searching
                            ? Icons.search_off
                            : Icons.event_available_outlined,
                        title: searching ? 'Aucun résultat' : 'Aucun rendez-vous',
                        message: searching
                            ? 'Aucun rendez-vous ne correspond à « ${_query.trim()} ». Vérifiez le numéro du ticket (exemple : RDV-3F9A1C2B).'
                            : 'Aucun rendez-vous ne correspond à ce filtre. Touchez + pour en planifier un.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _buildCard(list[index]),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Rendez-vous')),
      body: _isLoading
          ? const SkeletonList(avatar: false)
          : _buildList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau RDV'),
      ),
    );
  }
}