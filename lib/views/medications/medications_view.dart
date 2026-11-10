import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/care_reminder_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';

class MedicationsView extends StatefulWidget {
  const MedicationsView({super.key});

  @override
  State<MedicationsView> createState() => _MedicationsViewState();
}

class _MedicationsViewState extends State<MedicationsView> {
  final CareReminderService _service = CareReminderService();

  List<DoseEntry> _doses = [];
  List<Treatment> _activeTreatments = [];
  bool _isLoading = true;

  String? get _patientId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    final patientId = _patientId;
    if (patientId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final today = DateTime.now();
    // Traitements, horaires et prises du jour : trois lectures indépendantes.
    final (treatments, prefs, taken) = await (
      _service.loadTreatments(patientId),
      _service.getPreferences(patientId),
      _service.loadTakenKeys(patientId, today),
    ).wait;

    final active = treatments.where((t) => t.isActiveOn(today)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (!mounted) return;
    setState(() {
      _activeTreatments = active;
      _doses = _service.buildDoses(
        day: today,
        treatments: treatments,
        prefs: prefs,
        taken: taken,
      );
      _isLoading = false;
    });
  }

  Future<void> _toggle(DoseEntry dose) async {
    final patientId = _patientId;
    if (patientId == null) return;

    final index = _doses.indexWhere((d) => d.key == dose.key);
    if (index == -1) return;

    final newTaken = !dose.taken;
    setState(() => _doses[index] = dose.copyWith(taken: newTaken));

    final ok = await _service.setTaken(
      patientId: patientId,
      medicationId: dose.treatment.medicationId,
      day: DateTime.now(),
      slot: dose.slot,
      taken: newTaken,
    );

    if (!mounted) return;

    if (!ok) {
      setState(() => _doses[index] = dose);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Impossible d\'enregistrer cette prise'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // La notification d'une prise déjà faite ne doit plus s'afficher.
    _service.syncDeviceNotifications(patientId);
  }

  void _openReminders() {
    Navigator.pushNamed(context, '/reminders').then((_) {
      if (mounted) _load(silent: true);
    });
  }

  // ------------------------------------------------------------------ UI

  Widget _buildProgressCard() {
    final total = _doses.length;
    final done = _doses.where((d) => d.taken).length;
    final remaining = total - done;
    final allDone = total > 0 && remaining == 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.rose.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Mes prises du jour',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$done / $total',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            allDone
                ? 'Bravo, toutes vos prises du jour sont faites.'
                : 'Il vous reste $remaining prise${remaining > 1 ? 's' : ''} aujourd\'hui.',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDoseCard(DoseEntry dose) {
    final now = DateTime.now();
    final overdue = dose.isOverdue(now);
    final accent = dose.taken
        ? AppColors.teal
        : (overdue ? AppColors.amber : AppColors.rose);
    final t = dose.treatment;
    final instructions = (t.instructions ?? '').trim();

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _toggle(dose),
      child: Row(
        children: [
          Container(
            width: 66,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  CareReminderService.timeString(dose.time),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CareReminderService.slotLabels[dose.slot],
                  style: TextStyle(fontSize: 11, color: accent),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: dose.taken ? AppColors.muted : AppColors.ink,
                    decoration: dose.taken ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (t.dosage.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    t.dosage,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ],
                if (instructions.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    instructions,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.muted,
                    ),
                  ),
                ],
                if (overdue) ...[
                  const SizedBox(height: 6),
                  const StatusPill(label: 'En retard', color: AppColors.amber),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dose.taken ? AppColors.teal : Colors.transparent,
              border: Border.all(
                color: dose.taken ? AppColors.teal : AppColors.border,
                width: 2,
              ),
            ),
            child: dose.taken
                ? const Icon(Icons.check, color: Colors.white, size: 22)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTreatmentCard(Treatment t) {
    final daysLeft = t.daysLeftFrom(DateTime.now());
    final instructions = (t.instructions ?? '').trim();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.medication_outlined, color: AppColors.teal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.dosage.isEmpty ? '' : '${t.dosage} · '}'
                      '${t.timesPerDay} fois par jour',
                      style: const TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: daysLeft <= 1 ? 'Dernier jour' : 'Encore $daysLeft jours',
                color: daysLeft <= 1 ? AppColors.amber : AppColors.teal,
              ),
            ],
          ),
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.roseSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: AppColors.rose),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      instructions,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_activeTreatments.isEmpty) {
      return RefreshIndicator(
        color: AppColors.rose,
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            EmptyState(
              icon: Icons.medication_outlined,
              title: 'Aucun traitement en cours',
              message:
                  'Vos médicaments apparaîtront ici dès que votre médecin vous aura prescrit une ordonnance.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildProgressCard(),
          const SizedBox(height: 28),
          const SectionTitle(title: 'Prises du jour'),
          for (var i = 0; i < _doses.length; i++) ...[
            _buildDoseCard(_doses[i]),
            if (i < _doses.length - 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 28),
          SectionTitle(title: 'Traitements en cours (${_activeTreatments.length})'),
          for (var i = 0; i < _activeTreatments.length; i++) ...[
            _buildTreatmentCard(_activeTreatments[i]),
            if (i < _activeTreatments.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes traitements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Mes rappels',
            onPressed: _openReminders,
          ),
        ],
      ),
      body: _isLoading
          ? const SkeletonList(avatar: false)
          : _buildContent(),
    );
  }
}
