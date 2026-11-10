import 'package:flutter/material.dart';
import '../../services/prescription_service.dart';
import '../../models/prescription_model.dart';

class DoctorPrescriptionView extends StatefulWidget {
  final String prescriptionId;

  const DoctorPrescriptionView({
    super.key,
    required this.prescriptionId,
  });

  @override
  State<DoctorPrescriptionView> createState() => _DoctorPrescriptionViewState();
}

class _DoctorPrescriptionViewState extends State<DoctorPrescriptionView> {
  final PrescriptionService _prescriptionService = PrescriptionService();
  Prescription? _prescription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrescription();
  }

  Future<void> _loadPrescription() async {
    setState(() => _isLoading = true);
    try {
      final prescription = await _prescriptionService.getPrescriptionById(widget.prescriptionId);
      setState(() {
        _prescription = prescription;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_prescription == null) {
      return const Scaffold(
        body: Center(child: Text('Ordonnance non trouvée')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détails Ordonnance'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Médecin:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(_prescription!.doctorName),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Patient:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(_prescription!.patientName),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Diagnostic:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(_prescription!.diagnosis),
            const SizedBox(height: 16),

            const Text(
              'Traitement:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(_prescription!.treatment),
            const SizedBox(height: 16),

            // ✅ CORRECTION: Vérification correcte sans ! inutile
            if (_prescription!.notes != null && _prescription!.notes!.isNotEmpty) ...[
              const Text(
                'Notes:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(_prescription!.notes!),
              const SizedBox(height: 16),
            ],

            Text(
              'Date: ${_prescription!.dateLabel}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}