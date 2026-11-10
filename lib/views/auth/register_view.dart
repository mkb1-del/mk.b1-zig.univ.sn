import 'package:flutter/material.dart';
import '../../widgets/ribbon_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/avatar_service.dart';
import '../../theme/app_theme.dart';

class RegisterView extends StatefulWidget {
  final String userType;

  const RegisterView({
    super.key,
    required this.userType,
  });

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _hospitalController = TextEditingController();
  final AvatarService _avatarService = AvatarService();
  PickedAvatar? _avatar;

  /// Suggestions d'établissements (à titre d'exemple : le médecin peut saisir le sien).
  static const List<String> _hospitalSuggestions = [
    'Institut Joliot-Curie (Dakar)',
    'Hôpital Aristide Le Dantec',
    'Hôpital Principal de Dakar',
    'Hôpital Général de Grand Yoff',
    'Hôpital de Fann',
    'Hôpital de la Paix de Ziguinchor',
    'Hôpital régional de Ziguinchor',
    'Clinique privée',
  ];

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _specialtyController.dispose();
    _hospitalController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {
          'name': _nameController.text.trim(),
          'user_type': widget.userType,
          'phone': _phoneController.text.trim(),
          'specialty': widget.userType == 'doctor'
              ? _specialtyController.text.trim()
              : null,
          'hospital': widget.userType == 'doctor'
              ? _hospitalController.text.trim()
              : null,
        },
      );

      if (response.user == null) {
        throw Exception('Échec de la création de l\'utilisateur');
      }

      // Hôpital et photo : possibles seulement si une session existe déjà
      // (confirmation par email désactivée).
      var photoSaved = true;
      final hasSession = response.session != null ||
          Supabase.instance.client.auth.currentSession != null;
      if (hasSession) {
        photoSaved = await _finishProfile(response.user!.id);
      } else if (_avatar != null) {
        photoSaved = false;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            photoSaved
                ? '✅ Inscription réussie ! Veuillez vous connecter.'
                : '✅ Inscription réussie ! Votre photo n\'a pas pu être enregistrée : ajoutez-la depuis votre profil.',
          ),
          backgroundColor: AppColors.teal,
          duration: const Duration(seconds: 4),
        ),
      );

      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      // Le détail technique reste visible dans la Debug Console.
      debugPrint('❌ Erreur inscription: $e');

      if (!mounted) return;

      final errorText = e.toString();
      String errorMessage = 'Une erreur est survenue. Réessayez dans un instant.';

      if (errorText.contains('already registered') ||
          errorText.contains('duplicate key') ||
          errorText.contains('User already registered') ||
          errorText.contains('unique constraint')) {
        errorMessage = 'Cet email est déjà utilisé. Essayez-en un autre.';
      } else if (errorText.contains('weak-password') ||
          errorText.contains('Password should be at least')) {
        errorMessage = 'Le mot de passe doit contenir au moins 6 caractères';
      } else if (errorText.contains('invalid-email')) {
        errorMessage = 'Format d\'email invalide';
      } else if (errorText.contains('Email not confirmed')) {
        errorMessage = 'Veuillez confirmer votre email';
      } else if (errorText.contains('Database error saving new user')) {
        errorMessage =
            'Le profil n\'a pas pu être créé. Réessayez ou contactez le support.';
      } else if (errorText.contains('Failed to fetch') ||
          errorText.contains('SocketException') ||
          errorText.contains('ClientException')) {
        errorMessage = 'Connexion impossible. Vérifiez votre connexion internet.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $errorMessage'),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Complète le profil juste après l'inscription : hôpital (au cas où le serveur
  /// ne l'aurait pas repris) et photo. Renvoie false si la photo n'a pas pu être
  /// enregistrée.
  Future<bool> _finishProfile(String userId) async {
    final client = Supabase.instance.client;

    if (widget.userType == 'doctor') {
      try {
        await client
            .from('profiles')
            .update({'hospital': _hospitalController.text.trim()}).eq('id', userId);
      } catch (e) {
        debugPrint('ℹ️ Hôpital non enregistré: $e');
      }
    }

    final avatar = _avatar;
    if (avatar == null) return true;
    final url = await _avatarService.upload(avatar);
    return url != null;
  }

  Future<void> _chooseAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.rose),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.rose),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await _avatarService.pick(source);
    if (!mounted) return;

    if (picked == null) {
      if (_avatarService.lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${_avatarService.lastError}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }
    setState(() => _avatar = picked);
  }

  Widget _buildAvatarPicker() {
    final avatar = _avatar;

    return Column(
      children: [
        GestureDetector(
          onTap: _isLoading ? null : _chooseAvatar,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 52,
                backgroundColor: AppColors.roseSoft,
                backgroundImage: avatar == null ? null : MemoryImage(avatar.bytes),
                child: avatar == null
                    ? const Icon(Icons.person_outline, size: 48, color: AppColors.rose)
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.rose,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.photo_camera, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Photo de profil (facultatif)',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        if (avatar != null)
          TextButton(
            onPressed: _isLoading ? null : () => setState(() => _avatar = null),
            child: const Text('Retirer la photo'),
          ),
      ],
    );
  }

  Widget _buildHeader(bool isDoctor) {
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
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
            ),
            child: Center(
              child: isDoctor
                  ? const Icon(
                      Icons.medical_services_outlined,
                      color: Colors.white,
                      size: 28,
                    )
                  : const RibbonLogo(size: 32, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDoctor ? 'Espace médecin' : 'Espace patiente',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isDoctor
                      ? 'Rejoignez Sunu Yaakaar pour accompagner vos patientes.'
                      : 'Rejoignez Sunu Yaakaar pour suivre votre santé sereinement.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDoctor = widget.userType == 'doctor';

    return Scaffold(
      appBar: AppBar(
        title: Text(isDoctor ? 'Inscription médecin' : 'Inscription patiente'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(isDoctor),
                const SizedBox(height: 24),
                _buildAvatarPicker(),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Veuillez entrer votre nom';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Veuillez entrer votre email';
                    }
                    if (!value.contains('@')) {
                      return 'Email invalide';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone (optionnel)',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                if (isDoctor) ...[
                  TextFormField(
                    controller: _specialtyController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Spécialité',
                      prefixIcon: Icon(Icons.medical_services_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Veuillez entrer votre spécialité';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _hospitalController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Hôpital ou établissement',
                      prefixIcon: Icon(Icons.local_hospital_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Veuillez indiquer votre hôpital ou établissement';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Suggestions (ou saisissez le vôtre) :',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final h in _hospitalSuggestions)
                        ActionChip(
                          label: Text(h, style: const TextStyle(fontSize: 12)),
                          onPressed: () =>
                              setState(() => _hospitalController.text = h),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    helperText: 'Au moins 6 caractères',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: 'Afficher ou masquer le mot de passe',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer un mot de passe';
                    }
                    if (value.length < 6) {
                      return 'Le mot de passe doit contenir au moins 6 caractères';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Confirmer le mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: 'Afficher ou masquer le mot de passe',
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() =>
                            _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'Les mots de passe ne correspondent pas';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _register(),
                ),
                const SizedBox(height: 28),

                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Créer mon compte',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Déjà un compte ?',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: const Text('Se connecter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
