import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'services/realtime_service.dart';
import 'services/timeout_http_client.dart';
import 'services/connectivity_service.dart';
import 'widgets/offline_banner.dart';

// --- AUTH ---
import 'views/auth/login_view.dart';
import 'views/auth/user_type_selection_view.dart';

// --- PATIENTE ---
import 'views/home/home_view.dart';
import 'views/patiente/patient_profile_view.dart';
import 'views/patiente/patient_appointments_view.dart';
import 'views/patiente/patient_prescriptions_view.dart';
import 'views/reminders/reminders_view.dart';
import 'views/history/history_view.dart';
import 'views/medications/medications_view.dart';
import 'views/messages/conversations_view.dart';
import 'views/messages/select_doctor_chat_view.dart';
import 'views/symptoms/symptoms_view.dart';
import 'views/symptoms/symptoms_history_view.dart';
import 'views/photos/photo_gallery_view.dart';
import 'views/profile/doctor_selection_view.dart';
import 'views/profile/profile_view.dart';
import 'views/statistics/statistics_view.dart';

// --- MÉDECIN ---
import 'views/doctor/doctor_home_view.dart';
import 'views/doctor/doctor_appointments_view.dart';
import 'views/doctor/add_patient_view.dart';
import 'views/doctor/create_appointment_view.dart';
import 'views/doctor/doctor_prescriptions_view.dart';
import 'views/doctor/select_patient_prescription_view.dart';
import 'views/doctor/doctor_patients_view.dart';
import 'views/doctor/doctor_profile_view.dart';
import 'views/doctor/doctor_statistics_view.dart';
import 'views/doctor/select_doctor_treating_view.dart';
import 'views/messages/select_patient_chat_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      // Chaque requête est limitée dans le temps (réseau très faible)
      httpClient: TimeoutHttpClient(),
      url: 'https://imhgjqdsuijpyuqlqpdd.supabase.co',
      publishableKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImltaGdqcWRzdWlqcHl1cWxxcGRkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQwNTgyNzcsImV4cCI6MjA5OTYzNDI3N30.9MSgYKmaFDS7o5P54e-EGyp9cYtHd4T6BAi522t9yrw',
    );
    debugPrint('✅ Supabase OK');
  } catch (e) {
    debugPrint('❌ Erreur Supabase: $e');
  }

  // Notifications du téléphone (sans effet dans le navigateur) et surveillance
  // de la connexion : démarrées ensemble pour ouvrir l'application plus vite.
  await Future.wait([
    NotificationService.instance.init(),
    ConnectivityService.instance.init(),
  ]);

  // Messages, ordonnances et rendez-vous reçus en direct
  RealtimeService.instance.init();

  // En production : un élément qui plante affiche un message clair
  // au lieu de l'écran gris standard.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const FriendlyErrorWidget();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sunu Yaakaar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,

      // Bandeau « pas de connexion » au-dessus de toute l'application
      builder: (context, child) {
        // Le texte agrandi par l'utilisateur est respecté jusqu'à 130 pour cent :
        // au-delà, la mise en page ne tiendrait plus à l'écran.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.3,
            ),
          ),
          child: ConnectivityBannerHost(child: child ?? const SizedBox.shrink()),
        );
      },

      // Page de démarrage
      initialRoute: '/login',

      // Tableau central des routes
      routes: {
        // --- Authentification ---
        '/login': (context) => const LoginView(),
        '/user_type_selection': (context) => const UserTypeSelectionView(),

        // --- Espace Patiente ---
        '/home': (context) => const HomeView(),
        '/patient-appointments': (context) => const PatientAppointmentsView(),
        '/patient-prescriptions': (context) => const PatientPrescriptionsView(),
        '/reminders': (context) => const RemindersView(),
        '/patient-profile': (context) => const PatientProfileView(),
        '/patient-messages': (context) => const ConversationsView(),
        '/select-doctor-chat': (context) => const SelectDoctorChatView(),
        '/history': (context) => const HistoryView(),
        '/medications': (context) => const MedicationsView(),
        '/symptoms': (context) => const SymptomsView(),
        '/symptoms-history': (context) => const SymptomsHistoryView(),
        '/photo-gallery': (context) => const PhotoGalleryView(),
        '/doctor-selection': (context) => const DoctorSelectionView(),
        '/profile': (context) => const ProfileView(),
        '/statistics': (context) => const StatisticsView(),

        // --- Espace Médecin ---
        '/doctor_home': (context) => const DoctorHomeView(),
        '/doctor-appointments': (context) => const DoctorAppointmentsView(),
        '/add-patient': (context) => const AddPatientView(),
        '/create-appointment': (context) => const CreateAppointmentView(),
        '/doctor-messages': (context) => const SelectPatientChatView(),
        '/doctor-prescriptions': (context) => const DoctorPrescriptionsView(),
        '/doctor-prescribe': (context) => const SelectPatientPrescriptionView(),
        '/doctor-patients': (context) => const DoctorPatientsView(),
        '/doctor-profile': (context) => const DoctorProfileView(),
        '/doctor-statistics': (context) => const DoctorStatisticsView(),
        '/select-doctor-treating': (context) => const SelectDoctorTreatingView(),
      },

      // Filet de sécurité anti-crash
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Page introuvable')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'La route "${settings.name}" n\'est pas encore définie dans main.dart.\n\nAjoute-la dans le tableau routes.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
