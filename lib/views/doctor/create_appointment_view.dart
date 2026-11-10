import 'package:flutter/material.dart';
import '../../services/app_errors.dart';
import '../../services/doctor_directory_service.dart';
import '../../theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateAppointmentView extends StatefulWidget {
  const CreateAppointmentView({super.key});

  @override
  State<CreateAppointmentView> createState() => _CreateAppointmentViewState();
}

class _CreateAppointmentViewState extends State<CreateAppointmentView> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // --- Gestion de la liste des patientes ---
  List<Map<String, dynamic>> _patients = [];
  String? _selectedPatientId;
  String? _selectedPatientName;
  bool _isLoadingPatients = true;

  bool _isLoading = false;

  // Lieu du rendez-vous : l'hôpital du médecin, repris de son profil.
  String _hospital = '';
  bool _hospitalLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPatients();
    _loadHospital();
  }

  Future<void> _loadHospital() async {
    final doctorId = Supabase.instance.client.auth.currentUser?.id;
    final hospital =
        doctorId == null ? '' : await DoctorDirectoryService().hospitalOf(doctorId);
    if (!mounted) return;
    setState(() {
      _hospital = hospital;
      _hospitalLoaded = true;
    });
  }

  /// Encadré « Lieu » : où aura lieu le rendez-vous, vu par la patiente.
  Widget _buildPlaceCard() {
    final missing = _hospitalLoaded && _hospital.trim().isEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: missing ? AppColors.amber.withValues(alpha: 0.12) : AppColors.roseSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.local_hospital_outlined,
            size: 20,
            color: missing ? AppColors.amberText : AppColors.rose,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lieu du rendez-vous',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  !_hospitalLoaded
                      ? 'Chargement…'
                      : (missing
                          ? 'Aucun hôpital renseigné. Indiquez-le dans votre profil '
                              '(Modifier le profil) pour que la patiente sache où se rendre.'
                          : _hospital),
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    try {
      final doctorId = Supabase.instance.client.auth.currentUser?.id;
      if (doctorId == null) throw Exception('Médecin non connecté');

      // Patientes ayant un vrai compte (profiles) : c'est ce qui permet à la
      // patiente de voir ses rendez-vous dans son propre espace.
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, name')
          .eq('user_type', 'patient')
          .order('name', ascending: true);

      if (!mounted) return;

      setState(() {
        _patients = List<Map<String, dynamic>>.from(response);
        _isLoadingPatients = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingPatients = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erreur chargement des patientes. ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _createAppointment() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPatientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Veuillez sélectionner une patiente'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Veuillez sélectionner une date'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Veuillez sélectionner une heure'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final doctorId = Supabase.instance.client.auth.currentUser?.id;
      if (doctorId == null) {
        throw Exception('Médecin non connecté');
      }

      final dateStr =
          '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';

      await Supabase.instance.client.from('appointments').insert({
        'doctor_id': doctorId,
        'patient_id': _selectedPatientId,
        'patient_name': _selectedPatientName,
        'date': dateStr,
        'time': timeStr,
        'reason': _reasonController.text.trim(),
        'notes': _notesController.text.trim(),
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Rendez-vous créé avec succès !'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${AppErrors.message(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nouveau rendez-vous',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // En-tête
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.roseMid, AppColors.rose],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.calendar_month, color: Colors.white, size: 40),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nouveau RDV',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Planifier un rendez-vous',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildPlaceCard(),
              const SizedBox(height: 24),

              // --- Sélection de la patiente (menu déroulant) ---
              _isLoadingPatients
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _patients.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.roseSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.amber),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: AppColors.amber),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Aucune patiente inscrite pour le moment.',
                                  style: TextStyle(color: AppColors.amberText),
                                ),
                              ),
                            ],
                          ),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: _selectedPatientId,
                          decoration: InputDecoration(
                            labelText: 'Patiente *',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: _patients.map((patient) {
                            return DropdownMenuItem<String>(
                              value: patient['id'] as String,
                              child: Text(patient['name'] as String? ?? 'Sans nom'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            final patient = _patients.firstWhere(
                              (p) => p['id'] == value,
                            );
                            setState(() {
                              _selectedPatientId = value;
                              _selectedPatientName = patient['name'] as String?;
                            });
                          },
                          validator: (value) {
                            if (value == null) {
                              return 'Veuillez sélectionner une patiente';
                            }
                            return null;
                          },
                        ),
              const SizedBox(height: 16),

              // Date
              InkWell(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: AppColors.rose),
                      const SizedBox(width: 12),
                      Text(
                        _selectedDate != null
                            ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                            : 'Sélectionner une date *',
                        style: TextStyle(
                          color: _selectedDate != null ? Colors.black : AppColors.muted,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Heure
              InkWell(
                onTap: _selectTime,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: AppColors.rose),
                      const SizedBox(width: 12),
                      Text(
                        _selectedTime != null
                            ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
                            : 'Sélectionner une heure *',
                        style: TextStyle(
                          color: _selectedTime != null ? Colors.black : AppColors.muted,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Motif
              TextFormField(
                controller: _reasonController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Motif de la consultation *',
                  prefixIcon: const Icon(Icons.medical_services),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Veuillez entrer le motif';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Notes
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notes (optionnel)',
                  prefixIcon: const Icon(Icons.note),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 32),

              // Bouton Créer
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _createAppointment,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.calendar_month),
                  label: Text(
                    _isLoading ? 'Création...' : 'Créer le rendez-vous',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.rose,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
