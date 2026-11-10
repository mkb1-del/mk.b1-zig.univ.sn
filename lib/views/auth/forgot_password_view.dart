import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';

/// Mot de passe oublié, en deux étapes :
///  1. la personne saisit son email : un code à 6 chiffres lui est envoyé ;
///  2. elle saisit ce code et choisit un nouveau mot de passe.
///
/// Aucun lien à ouvrir : tout se passe dans l'application, sur le web comme sur
/// téléphone. L'email doit contenir le code (variable {{ .Token }} dans le modèle
/// « Reset password » de Supabase).
class ForgotPasswordView extends StatefulWidget {
  /// Email déjà saisi sur l'écran de connexion (pré-rempli).
  final String initialEmail;

  const ForgotPasswordView({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  static const int _resendDelaySeconds = 60;

  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _codeSent = false;
  bool _isLoading = false;
  bool _obscure = true;

  /// Le code a été accepté : une session temporaire est ouverte. On ne redemande
  /// pas le code si seul le mot de passe est refusé (trop faible, identique...).
  bool _verified = false;
  bool _completed = false;

  int _cooldown = 0;
  Timer? _timer;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();

    // On ne laisse jamais quelqu'un connecté par la session temporaire.
    if (_verified && !_completed) {
      _auth.signOut();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ Outils

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendDelaySeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) timer.cancel();
    });
  }

  void _showMessage(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.danger : AppColors.success,
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
  }

  /// Traduit une erreur du serveur en message clair pour l'utilisateur.
  String _friendlyError(AuthException e) {
    debugPrint('❌ Réinitialisation : ${e.statusCode} ${e.message}');
    final m = e.message.toLowerCase();

    if (e.statusCode == '429' ||
        m.contains('rate limit') ||
        m.contains('security purposes') ||
        m.contains('too many')) {
      return 'Trop de demandes. Patientez une minute puis réessayez.';
    }
    if (m.contains('not authorized')) {
      return 'L\'envoi d\'emails n\'est pas encore activé pour cette adresse. '
          'Contactez l\'administrateur de l\'application.';
    }
    if (m.contains('error sending') || m.contains('sending recovery')) {
      return 'L\'email n\'a pas pu être envoyé. Réessayez dans un instant.';
    }
    if (m.contains('different from the old') || m.contains('same password')) {
      return 'Choisissez un mot de passe différent de l\'ancien.';
    }
    if (m.contains('at least') || m.contains('weak')) {
      return 'Mot de passe trop faible. Choisissez-en un plus long.';
    }
    if (m.contains('expired') || m.contains('invalid')) {
      return 'Code incorrect ou expiré. Demandez un nouveau code.';
    }
    return 'Une erreur est survenue. Réessayez.';
  }

  // ------------------------------------------------------------------ Actions

  Future<void> _sendCode({bool isResend = false}) async {
    if (!isResend && !_emailFormKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await _auth.resetPasswordForEmail(email);
      if (!mounted) return;

      setState(() {
        _codeSent = true;
        _verified = false;
      });
      _startCooldown();
      _showMessage(isResend ? 'Nouveau code envoyé' : 'Code envoyé, consultez votre messagerie');
    } on AuthException catch (e) {
      if (!mounted) return;
      _showMessage(_friendlyError(e), error: true);
    } catch (e) {
      debugPrint('❌ Envoi du code : $e');
      if (!mounted) return;
      _showMessage('Impossible d\'envoyer le code. Vérifiez votre connexion.', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitNewPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      if (!_verified) {
        await _auth.verifyOTP(
          type: OtpType.recovery,
          email: _emailController.text.trim(),
          token: _codeController.text.trim(),
        );
        _verified = true;
      }

      await _auth.updateUser(UserAttributes(password: _passwordController.text));
      _completed = true;

      // On déconnecte la session temporaire : la personne se reconnecte normalement.
      await _auth.signOut();

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ Mot de passe modifié. Connectez-vous avec le nouveau.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _showMessage(_friendlyError(e), error: true);
    } catch (e) {
      debugPrint('❌ Changement du mot de passe : $e');
      if (!mounted) return;
      _showMessage('Impossible de modifier le mot de passe. Réessayez.', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeEmail() {
    _timer?.cancel();
    if (_verified) _auth.signOut();
    setState(() {
      _codeSent = false;
      _verified = false;
      _cooldown = 0;
      _codeController.clear();
      _passwordController.clear();
      _confirmController.clear();
    });
  }

  // ---------------------------------------------------------------------- UI

  Widget _loadingOr(String label) {
    if (_isLoading) {
      return const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
      );
    }
    return Text(label);
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => _isLoading ? null : _sendCode(),
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Veuillez entrer votre email';
              if (!v.contains('@') || !v.contains('.')) return 'Email invalide';
              return null;
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendCode,
              child: _loadingOr('Envoyer le code'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetStep() {
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.roseSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.mark_email_read_outlined,
                    color: AppColors.rose, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Un code à 6 chiffres a été envoyé à ${_emailController.text.trim()}. '
                    'Pensez à regarder dans vos courriers indésirables.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.ink,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: 'Code reçu par email',
              prefixIcon: Icon(Icons.pin_outlined),
              counterText: '',
            ),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.length < 6) return 'Entrez le code à 6 chiffres';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Nouveau mot de passe',
              helperText: 'Au moins 6 caractères',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: 'Afficher ou masquer le mot de passe',
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Veuillez choisir un mot de passe';
              }
              if (value.length < 6) {
                return 'Le mot de passe doit contenir au moins 6 caractères';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmController,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _isLoading ? null : _submitNewPassword(),
            decoration: const InputDecoration(
              labelText: 'Confirmer le mot de passe',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (value) {
              if (value != _passwordController.text) {
                return 'Les mots de passe ne correspondent pas';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitNewPassword,
              child: _loadingOr('Changer mon mot de passe'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _isLoading || _cooldown > 0
                    ? null
                    : () => _sendCode(isResend: true),
                child: Text(
                  _cooldown > 0
                      ? 'Renvoyer le code (${_cooldown}s)'
                      : 'Renvoyer le code',
                ),
              ),
              TextButton(
                onPressed: _isLoading ? null : _changeEmail,
                child: const Text('Changer d\'email'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        color: AppColors.roseSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_reset,
                        size: 44,
                        color: AppColors.rose,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _codeSent ? 'Saisissez le code reçu' : 'Réinitialiser le mot de passe',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _codeSent
                        ? 'Étape 2 sur 2 : entrez le code puis choisissez votre nouveau mot de passe.'
                        : 'Étape 1 sur 2 : entrez l\'email de votre compte, nous vous enverrons un code à 6 chiffres.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    child: _codeSent ? _buildResetStep() : _buildEmailStep(),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Retour à la connexion'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
