import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class ReminderService {
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    try {
      // Initialiser les timezones
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Paris'));

      // Configuration Android
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // Configuration iOS
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialisation avec gestion des clics
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('🔔 Notification cliquée: ${response.payload}');
          // Gestion des clics sur les notifications
        },
      );
      
      debugPrint('✅ ReminderService initialisé avec succès');
    } catch (e) {
      debugPrint('❌ Erreur initialisation ReminderService: $e');
      rethrow;
    }
  }

  Future<void> requestPermissions() async {
    try {
      // Permission Android
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
          
      // Permission iOS
      await _notifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          
      debugPrint('✅ Permissions de notification demandées');
    } catch (e) {
      debugPrint('❌ Erreur demande permissions notifications: $e');
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    try {
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'breastcare_channel',
            'BreastCare Notifications',
            channelDescription: 'Rappels de médicaments et rendez-vous',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload ?? 'reminder',
      );
      debugPrint('✅ Notification planifiée pour: $scheduledTime (ID: $id)');
    } catch (e) {
      debugPrint('❌ Erreur planification notification: $e');
      rethrow;
    }
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
      debugPrint('✅ Notification annulée: $id');
    } catch (e) {
      debugPrint('❌ Erreur annulation notification: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      debugPrint('✅ Toutes les notifications annulées');
    } catch (e) {
      debugPrint('❌ Erreur annulation de toutes les notifications: $e');
    }
  }
}