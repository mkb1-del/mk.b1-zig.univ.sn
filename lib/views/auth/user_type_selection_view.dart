import 'package:flutter/material.dart';
import '../../widgets/ribbon_background.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import 'register_view.dart';

class UserTypeSelectionView extends StatelessWidget {
  const UserTypeSelectionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: AppColors.roseSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: RibbonLogo(size: 44, color: AppColors.rose),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Bienvenue sur Sunu Yaakaar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Dites-nous qui vous êtes pour personnaliser votre espace.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 32),

              _buildRoleCard(
                context: context,
                title: 'Je suis patiente',
                subtitle:
                    'Suivez votre santé, lisez vos ordonnances et échangez avec votre médecin.',
                icon: Icons.favorite_outline,
                color: AppColors.rose,
                userType: 'patient',
              ),
              const SizedBox(height: 16),

              _buildRoleCard(
                context: context,
                title: 'Je suis médecin',
                subtitle:
                    'Gérez vos patientes, vos rendez-vous et vos prescriptions.',
                icon: Icons.medical_services_outlined,
                color: AppColors.plum,
                userType: 'doctor',
              ),
              const SizedBox(height: 32),

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
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String userType,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RegisterView(userType: userType),
          ),
        );
      },
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.muted,
                    height: 1.35,
                  ),
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
}