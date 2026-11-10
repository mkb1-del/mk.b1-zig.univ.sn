import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/prescription_model.dart';
import '../../services/prescription_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../patiente/patient_prescription_detail_view.dart';

/// Ordonnances rédigées par le médecin connecté.
class DoctorPrescriptionsView extends StatefulWidget {
  const DoctorPrescriptionsView({super.key});

  @override
  State<DoctorPrescriptionsView> createState() => _DoctorPrescriptionsViewState();
}

class _DoctorPrescriptionsViewState extends State<DoctorPrescriptionsView> {
  final PrescriptionService _prescriptionService = PrescriptionService();

  List<Prescription> _prescriptions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// silent = true : rafraîchit sans remplacer la page par un spinner.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final doctorId = Supabase.instance.client.auth.currentUser?.id;
      if (doctorId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final list = await _prescriptionService.getDoctorPrescriptions(doctorId);
      if (!mounted) return;
      setState(() {
        _prescriptions = list;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement ordonnances médecin: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossible de charger vos ordonnances.';
      });
    }
  }

  void _open(Prescription prescription) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PatientPrescriptionDetailView(prescription: prescription),
      ),
    );
  }

  Widget _buildItem(Prescription p) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _open(p),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.description_outlined, color: AppColors.violet),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.patientName.isEmpty ? 'Patiente' : p.patientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.diagnosis,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 13, color: AppColors.muted),
                    const SizedBox(width: 5),
                    Text(
                      p.dateLabel,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const SkeletonList(avatar: false);
    }

    if (_errorMessage != null) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: _errorMessage!,
        message: 'Vérifiez votre connexion internet puis réessayez.',
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    }

    if (_prescriptions.isEmpty) {
      return const EmptyState(
        icon: Icons.description_outlined,
        title: 'Aucune ordonnance prescrite',
        message: 'Les ordonnances que vous rédigez apparaîtront ici.',
      );
    }

    return RefreshIndicator(
      color: AppColors.rose,
      onRefresh: () => _load(silent: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _prescriptions.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_prescriptions.length} ordonnance${_prescriptions.length > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            );
          }
          return _buildItem(_prescriptions[index - 1]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes ordonnances')),
      body: _buildContent(),
    );
  }
}
