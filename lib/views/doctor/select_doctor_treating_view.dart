import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';

class SelectDoctorTreatingView extends StatefulWidget {
  const SelectDoctorTreatingView({super.key});

  @override
  State<SelectDoctorTreatingView> createState() => _SelectDoctorTreatingViewState();
}

class _SelectDoctorTreatingViewState extends State<SelectDoctorTreatingView> {
  final AuthService _authService = AuthService();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<UserModel> _doctors = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('🔍 Chargement des médecins depuis Supabase...');
      
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('user_type', 'doctor')
          .order('name', ascending: true);
      
      final doctors = response.map((map) => UserModel.fromMap(map)).toList();
      
      debugPrint('✅ Médecins trouvés: ${doctors.length}');
      
      if (mounted) {
        setState(() {
          _doctors = doctors;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erreur chargement médecins: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur de chargement: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDoctor(UserModel doctor) async {
    try {
      debugPrint('🔎 Récupération de la patiente connectée...');
      
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) {
        debugPrint('❌ Aucune patiente connectée');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erreur: Utilisateur non connecté'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      debugPrint('✅ Patiente trouvée: ${currentUser.name} (ID: ${currentUser.id})');
      debugPrint('🔗 Attribution du Dr. ${doctor.name} (ID: ${doctor.id})...');

      // ✅ Mettre à jour le médecin traitant dans Supabase
      await _supabase
          .from('profiles')
          .update({
            'treating_doctor_id': doctor.id,
            // Décommentez la ligne suivante si vous avez cette colonne dans votre table profiles
            // 'treating_doctor_name': 'Dr. ${doctor.name}',
          })
          .eq('id', currentUser.id);

      debugPrint('✅ Médecin traitant mis à jour avec succès!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Médecin traitant sélectionné avec succès'),
            backgroundColor: Colors.green,
          ),
        );
        
        if (Navigator.of(context).canPop()) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e) {
      debugPrint('❌ Erreur sélection médecin: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choisir un médecin traitant'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.pink,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 80,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Erreur',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDoctors,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : _doctors.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.medical_services_outlined,
                            size: 80,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Aucun médecin disponible',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Les médecins apparaîtront ici\nune fois inscrits',
                            style: TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadDoctors,
                            child: const Text('Rafraîchir'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDoctors,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _doctors.length,
                        itemBuilder: (context, index) {
                          final doctor = _doctors[index];
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.pink.shade100,
                                child: const Icon(
                                  Icons.medical_services,
                                  color: Colors.pink,
                                ),
                              ),
                              title: Text(
                                'Dr. ${doctor.name}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(doctor.email),
                                  if (doctor.specialty != null && doctor.specialty!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text('Spécialité: ${doctor.specialty}'),
                                  ],
                                ],
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                              onTap: () => _selectDoctor(doctor),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}