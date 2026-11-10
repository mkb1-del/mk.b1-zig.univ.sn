import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // --- Mémoire des profils -------------------------------------------------
  // Chaque écran crée son propre AuthService : la mémoire est donc partagée
  // (static). Sans elle, chaque écran redemandait le profil au serveur.
  static UserModel? _meCache;
  static DateTime? _meCachedAt;
  static const Duration _meTtl = Duration(minutes: 2);

  static final Map<String, ({UserModel user, DateTime at})> _byIdCache = {};
  static const Duration _byIdTtl = Duration(minutes: 5);

  /// Oublie les profils mémorisés. A appeler après toute modification de profil
  /// (nom, photo, médecin traitant...) et à la déconnexion.
  static void clearCache() {
    _meCache = null;
    _meCachedAt = null;
    _byIdCache.clear();
  }

  Future<UserModel?> signIn(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        final user = await _fetchUserDetails(response.user!.id);
        return user;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Erreur connexion: $e');
      return null;
    }
  }

  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
    required String userType,
    String? phone,
    String? specialty,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user != null) {
        final user = UserModel(
          id: response.user!.id,
          email: email,
          name: name,
          userType: userType,
          phone: phone,
          specialty: userType == 'doctor' ? specialty : null,
          createdAt: DateTime.now(),
        );

        await _supabase.from('profiles').insert(user.toMap());
        return user;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Erreur inscription: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    clearCache();
    await _supabase.auth.signOut();
  }

  /// Profil de l'utilisateur connecté. Mémorisé 2 minutes ; forceRefresh: true
  /// impose une lecture au serveur (écrans de profil).
  Future<UserModel?> getCurrentUser({bool forceRefresh = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      clearCache();
      return null;
    }

    final cached = _meCache;
    final at = _meCachedAt;
    if (!forceRefresh &&
        cached != null &&
        at != null &&
        cached.id == user.id &&
        DateTime.now().difference(at) < _meTtl) {
      return cached;
    }

    final fresh = await _fetchUserDetails(user.id);
    _meCache = fresh;
    _meCachedAt = DateTime.now();
    return fresh;
  }

  Future<UserModel> _fetchUserDetails(String userId) async {
    final response = await _supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();

    return UserModel.fromMap(response);
  }

  Future<List<UserModel>> getAllDoctors() async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('user_type', 'doctor');

      return response.map((map) => UserModel.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur récupération médecins: $e');
      return [];
    }
  }

  /// Récupère toutes les patientes ayant un vrai compte (profiles,
  /// user_type = 'patient'). Utilisé pour la liste des patientes du
  /// médecin (messagerie, fiche patiente, etc.).
  Future<List<UserModel>> getAllPatients() async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('user_type', 'patient');

      return response.map((map) => UserModel.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Erreur récupération patientes: $e');
      return [];
    }
  }

  Future<bool> setTreatingDoctor(String patientId, String doctorId) async {
    try {
      await _supabase
          .from('profiles')
          .update({'treating_doctor_id': doctorId})
          .eq('id', patientId);

      clearCache();
      debugPrint('✅ Médecin traitant défini');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur définition médecin traitant: $e');
      return false;
    }
  }

  Future<UserModel?> getUserById(String userId) async {
    final hit = _byIdCache[userId];
    if (hit != null && DateTime.now().difference(hit.at) < _byIdTtl) {
      return hit.user;
    }

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      final user = UserModel.fromMap(response);
      _byIdCache[userId] = (user: user, at: DateTime.now());
      return user;
    } catch (e) {
      debugPrint('❌ Erreur récupération utilisateur: $e');
      return null;
    }
  }

  Future<bool> updateProfile(String userId, Map<String, dynamic> data) async {
    try {
      await _supabase
          .from('profiles')
          .update(data)
          .eq('id', userId);

      clearCache();
      debugPrint('✅ Profil mis à jour');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur mise à jour profil: $e');
      return false;
    }
  }
}
