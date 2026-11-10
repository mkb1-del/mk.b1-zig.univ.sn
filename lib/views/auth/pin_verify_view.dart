import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';

/// Saisie du code PIN à 4 chiffres.
///
/// - Si [expectedPin] est fourni, la vérification se fait ici (5 essais).
/// - Sinon, l'écran se contente de renvoyer le code saisi à l'écran appelant,
///   qui le vérifie lui-même.
///
/// Se ferme avec le code saisi (String) en cas de succès.
class PinVerifyView extends StatefulWidget {
  final String? expectedPin;

  const PinVerifyView({super.key, this.expectedPin});

  @override
  State<PinVerifyView> createState() => _PinVerifyViewState();
}

class _PinVerifyViewState extends State<PinVerifyView> {
  static const int _maxAttempts = 5;

  final _pinController = TextEditingController();
  String _currentText = '';
  String? _error;
  int _attempts = 0;

  bool get _locked => _attempts >= _maxAttempts;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _verify() {
    if (_currentText.length != 4 || _locked) return;

    final expected = widget.expectedPin;
    if (expected == null || _currentText == expected) {
      Navigator.pop(context, _currentText);
      return;
    }

    final attempts = _attempts + 1;
    final remaining = _maxAttempts - attempts;
    setState(() {
      _attempts = attempts;
      _currentText = '';
      _error = remaining > 0
          ? 'Code incorrect. Il vous reste $remaining essai${remaining > 1 ? 's' : ''}.'
          : 'Trop de tentatives. Reconnectez-vous avec votre mot de passe.';
    });
    _pinController.clear();
  }

  /// Code oublié : on se déconnecte puis on se reconnecte avec le mot de passe.
  Future<void> _forgot() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Code oublié ?'),
        content: const Text(
          'Vous allez être déconnectée, puis vous pourrez vous reconnecter avec votre email et votre mot de passe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Se reconnecter'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('❌ Erreur déconnexion: $e');
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vérifier le code PIN')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.roseSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline, size: 44, color: AppColors.rose),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Entrez votre code PIN',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saisissez votre code à 4 chiffres pour continuer.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 32),
            PinCodeTextField(
              appContext: context,
              length: 4,
              obscureText: true,
              autoFocus: true,
              enabled: !_locked,
              keyboardType: TextInputType.number,
              animationType: AnimationType.fade,
              enableActiveFill: true,
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(14),
                fieldHeight: 62,
                fieldWidth: 58,
                activeFillColor: Colors.white,
                inactiveFillColor: Colors.white,
                selectedFillColor: Colors.white,
                activeColor: AppColors.rose,
                inactiveColor: AppColors.border,
                selectedColor: AppColors.rose,
              ),
              animationDuration: const Duration(milliseconds: 300),
              backgroundColor: Colors.transparent,
              controller: _pinController,
              onChanged: (value) {
                setState(() {
                  _currentText = value;
                  if (value.isNotEmpty && !_locked) _error = null;
                });
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: (_currentText.length == 4 && !_locked) ? _verify : null,
                child: const Text(
                  'Vérifier',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _forgot,
              child: const Text('Code oublié ?'),
            ),
          ],
        ),
      ),
    );
  }
}