import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/prescription_service.dart';

class DoctorStatisticsView extends StatefulWidget {
  const DoctorStatisticsView({super.key});

  @override
  State<DoctorStatisticsView> createState() => _DoctorStatisticsViewState();
}

class _DoctorStatisticsViewState extends State<DoctorStatisticsView> {
  final AuthService _authService = AuthService();
  final PrescriptionService _prescriptionService = PrescriptionService();
  
  int _totalPatients = 0;
  int _totalAppointments = 0;
  int _totalPrescriptions = 0;
  int _appointmentsThisMonth = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() => _isLoading = true);

    try {
      final doctor = await _authService.getCurrentUser();
      if (doctor == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Charger les ordonnances
      final prescriptions = await _prescriptionService.getDoctorPrescriptions(doctor.id);
      _totalPrescriptions = prescriptions.length;

      // Compter le nombre de patientes uniques
      final uniquePatients = prescriptions.map((p) => p.patientId).toSet();
      _totalPatients = uniquePatients.length;

      // Charger les rendez-vous (à implémenter dans appointment_service.dart)
      // Pour l'instant, on met 0
      _totalAppointments = 0;
      _appointmentsThisMonth = 0;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement statistiques: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiques'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatistics,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.blue, Colors.blueAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Statistiques générales',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Vue d\'ensemble de votre activité',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildStatCard(
                      icon: Icons.people,
                      title: 'Total Patientes',
                      value: _totalPatients.toString(),
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      icon: Icons.calendar_today,
                      title: 'Rendez-vous ce mois',
                      value: _appointmentsThisMonth.toString(),
                      color: Colors.green,
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      icon: Icons.receipt_long,
                      title: 'Ordonnances créées',
                      value: _totalPrescriptions.toString(),
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      icon: Icons.message,
                      title: 'Total Rendez-vous',
                      value: _totalAppointments.toString(),
                      color: Colors.purple,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}