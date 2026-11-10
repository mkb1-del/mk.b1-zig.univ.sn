import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../theme/app_theme.dart';

/// Création d'un code PIN à 4 chiffres, en deux étapes : saisie puis confirmation.
///
/// Se ferme avec le code (String) quand les deux saisies sont identiques.
/// C'est à l'écran qui ouvre celui-ci d'enregistrer le code : cet écran ne
/// stocke rien lui-même.
class PinSetupView extends StatefulWidget {
  const PinSetupView({super.key});

  @override
  State<PinSetupView> createState() => _PinSetupViewState();
}

class _PinSetupViewState extends State<PinSetupView> {
  final _pinController = TextEditingController();
  String _currentText = '';
  String? _firstPin;
  String? _error;

  bool get _isConfirming => _firstPin != null;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentText.length != 4) return;

    // Étape 1 : on mémorise le code et on demande de le ressaisir.
    if (!_isConfirming) {
      setState(() {
        _firstPin = _currentText;
        _currentText = '';
        _error = null;
      });
      _pinController.clear();
      return;
    }

    // Étape 2 : les deux saisies doivent être identiques.
    if (_currentText == _firstPin) {
      Navigator.pop(context, _currentText);
      return;
    }

    setState(() {
      _firstPin = null;
      _currentText = '';
      _error = 'Les deux codes ne correspondent pas. Recommencez.';
    });
    _pinController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un code PIN')),
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
                child: Icon(
                  _isConfirming ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 44,
                  color: AppColors.rose,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isConfirming ? 'Confirmez votre code' : 'Créez un code PIN à 4 chiffres',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isConfirming
                  ? 'Saisissez à nouveau le même code.'
                  : 'Choisissez un code facile à retenir, mais difficile à deviner.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 32),
            PinCodeTextField(
              appContext: context,
              length: 4,
              obscureText: true,
              autoFocus: true,
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
                  _error = null;
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 2; i++)
                  Container(
                    width: 28,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: (i == 0 || _isConfirming)
                          ? AppColors.rose
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _currentText.length == 4 ? _next : null,
                child: Text(
                  _isConfirming ? 'Valider' : 'Continuer',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}