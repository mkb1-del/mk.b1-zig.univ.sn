import 'package:flutter/material.dart';
import '../../services/app_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_role.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/ribbon_background.dart';

/// Création d'une fiche patiente par le médecin (dossier sans compte).
/// Se ferme avec `true` quand la fiche est enregistrée.
class AddPatientView extends StatefulWidget {
  const AddPatientView({super.key});

  @override
  State<AddPatientView> createState() => _AddPatientViewState();
}

class _AddPatientViewState extends State<AddPatientView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();
  final _medicalHistoryController = TextEditingController();
  final _allergyController = TextEditingController();

  bool _isLoading = false;
  String? _selectedBloodType;
  bool _hasAllergies = false;
  final List<String> _allergies = [];

  final List<String> _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _medicalHistoryController.dispose();
    _allergyController.dispose();
    super.dispose();
  }

  /// Ajoute l'allergie saisie à la liste (sans doublon).
  void _addAllergy() {
    final text = _allergyController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!_allergies.any((a) => a.toLowerCase() == text.toLowerCase())) {
        _allergies.add(text);
      }
      _allergyController.clear();
    });
  }

  Future<void> _addPatient() async {
    if (!_formKey.currentState!.validate()) return;

    // Une allergie saisie mais pas encore validée par « + » n'est pas perdue.
    if (_hasAllergies && _allergyController.text.trim().isNotEmpty) {
      _addAllergy();
    }

    setState(() => _isLoading = true);

    try {
      final doctorId = Supabase.instance.client.auth.currentUser?.id;
      if (doctorId == null) throw Exception('Médecin non connecté');

      await Supabase.instance.client.from('patients').insert({
        'doctor_id': doctorId,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()),
        'address': _addressController.text.trim(),
        'blood_type': _selectedBloodType,
        'has_allergies': _hasAllergies,
        'allergies': _hasAllergies ? _allergies : <String>[],
        'medical_history': _medicalHistoryController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Patiente ajoutée avec succès !'),
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ------------------------------------------------------------------ UI

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppRole.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.rose.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: const Stack(
          children: [
            Positioned(
              right: 14,
              bottom: -22,
              child: Opacity(
                opacity: 0.18,
                child: RibbonLogo(size: 120, color: Colors.white),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0x33FFFFFF),
                    child: Icon(Icons.person_add_alt_1, color: Colors.white, size: 28),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nouvelle patiente',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Créez son dossier médical',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
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

  Widget _buildInfoNote() {
    return const AppCard(
      color: AppColors.roseSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.rose, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ce dossier n\'est visible que par vous. La patiente n\'a pas de compte : pour recevoir ordonnances et messages dans l\'application, elle doit s\'inscrire elle-même.',
              style: TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    return AppCard(
      child: Column(
        children: [
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nom complet *',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Veuillez entrer le nom';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              if (value != null && value.isNotEmpty && !value.contains('@')) {
                return 'Email invalide';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Téléphone *',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Veuillez entrer le téléphone';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return AppCard(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Âge',
                    prefixIcon: Icon(Icons.cake_outlined),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final age = int.tryParse(text);
                    if (age == null || age < 0 || age > 120) return 'Âge invalide';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedBloodType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Groupe',
                    prefixIcon: Icon(Icons.bloodtype_outlined),
                  ),
                  items: _bloodTypes
                      .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedBloodType = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _addressController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Adresse',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllergiesCard() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            title: const Text(
              'A des allergies',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            subtitle: const Text(
              'La patiente a-t-elle des allergies ?',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            value: _hasAllergies,
            onChanged: (value) => setState(() => _hasAllergies = value),
          ),
          if (_hasAllergies)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _allergyController,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _addAllergy(),
                          decoration: const InputDecoration(
                            labelText: 'Ajouter une allergie',
                            hintText: 'Ex : pénicilline',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _addAllergy,
                        tooltip: 'Ajouter',
                        icon: const Icon(Icons.add_circle, color: AppColors.rose, size: 32),
                      ),
                    ],
                  ),
                  if (_allergies.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _allergies.map((allergy) {
                        return Chip(
                          label: Text(allergy),
                          backgroundColor: AppColors.roseSoft,
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => setState(() => _allergies.remove(allergy)),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return AppCard(
      child: TextFormField(
        controller: _medicalHistoryController,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Antécédents médicaux',
          alignLabelWithHint: true,
          prefixIcon: Icon(Icons.medical_information_outlined),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter une patiente')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(),
              const SizedBox(height: 12),
              _buildInfoNote(),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Identité'),
              _buildIdentityCard(),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Informations'),
              _buildInfoCard(),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Allergies'),
              _buildAllergiesCard(),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Antécédents'),
              _buildHistoryCard(),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _addPatient,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.person_add_alt_1),
                  label: Text(
                    _isLoading ? 'Ajout en cours...' : 'Ajouter la patiente',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
