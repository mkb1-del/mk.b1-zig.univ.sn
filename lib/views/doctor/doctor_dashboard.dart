import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/calendar_service.dart';
import '../../services/prescription_service.dart';

class DoctorDashboard extends StatefulWidget {
  const DoctorDashboard({super.key});

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  final AuthService _authService = AuthService();
  final CalendarService _calendarService = CalendarService();
  final PrescriptionService _prescriptionService = PrescriptionService();

  String? _doctorName;
  int _totalPatients = 0;
  int _todayAppointments = 0;
  int _totalPrescriptions = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final doctor = await _authService.getCurrentUser();
      if (doctor == null) return;

      final appointments = await _calendarService.getDoctorAppointments(doctor.id);
      final prescriptions = await _prescriptionService.getDoctorPrescriptions(doctor.id);
      
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      final uniquePatients = appointments.map((a) => a.patientId).toSet().length;
      final todayCount = appointments.where((a) => a.date == todayStr).length;

      if (mounted) {
        setState(() {
          _doctorName = doctor.name;
          _totalPatients = uniquePatients;
          _todayAppointments = todayCount;
          _totalPrescriptions = prescriptions.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint(' Erreur chargement dashboard: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 0,
        title: const Text(
          'Tableau de bord',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bonjour Dr ${_doctorName ?? 'Médecin'}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildStatCard(
                    icon: Icons.people,
                    title: 'Total Patientes',
                    value: '$_totalPatients',
                    color: Colors.pink,
                  ),
                  const SizedBox(height: 12),
                  _buildStatCard(
                    icon: Icons.calendar_today,
                    title: 'RDV Aujourd\'hui',
                    value: '$_todayAppointments',
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _buildStatCard(
                    icon: Icons.medical_services,
                    title: 'Ordonnances',
                    value: '$_totalPrescriptions',
                    color: Colors.green,
                  ),
                ],
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
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}