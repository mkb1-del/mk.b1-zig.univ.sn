import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Notifications locales du téléphone (Android / iOS).
///
/// Dans le navigateur elles ne sont pas disponibles : toutes les méthodes
/// deviennent alors sans effet, et les rappels restent visibles dans
/// l'application elle-même.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Vrai uniquement sur un téléphone Android ou iOS.
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'sunu_yaakaar_reminders',
      'Rappels Sunu Yaakaar',
      channelDescription: 'Rappels de rendez-vous et de prise de médicaments',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (!isSupported || _initialized) return;
    try {
      tz_data.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (e) {
      debugPrint('❌ Erreur initialisation notifications: $e');
    }
  }

  /// Les notifications sont-elles autorisées par l'utilisateur ?
  Future<bool> areEnabled() async {
    if (!isSupported) return false;
    await init();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.areNotificationsEnabled() ?? false;
      }
      return true;
    } catch (e) {
      debugPrint('❌ Erreur lecture autorisation notifications: $e');
      return false;
    }
  }

  /// Demande l'autorisation d'afficher des notifications (Android 13+ / iOS).
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await init();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await android?.requestNotificationsPermission();
        try {
          // Alarmes exactes : pour des rappels à l'heure précise.
          await android?.requestExactAlarmsPermission();
        } catch (e) {
          debugPrint('ℹ️ Alarmes exactes non accordées: $e');
        }
        return granted ?? true;
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    } catch (e) {
      debugPrint('❌ Erreur demande autorisation notifications: $e');
      return false;
    }
  }

  /// Affiche une notification immédiatement (utile pour tester).
  Future<void> showNow({required String title, required String body, int? id}) async {
    if (!isSupported) return;
    await init();
    try {
      await _plugin.show(id ?? 999000, title, body, _details);
    } catch (e) {
      debugPrint('❌ Erreur notification immédiate: $e');
    }
  }

  /// Programme une notification à un instant précis (heure locale).
  Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!isSupported) return;
    await init();
    if (!when.isAfter(DateTime.now())) return;

    // On programme un instant absolu : le fuseau choisi n'a donc pas
    // d'importance pour une notification unique.
    final scheduled = tz.TZDateTime.from(when, tz.UTC);

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException catch (e) {
      // Alarmes exactes refusées : repli sur une alarme approximative.
      debugPrint('ℹ️ Repli sur alarme approximative: ${e.code}');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e2) {
        debugPrint('❌ Erreur programmation notification: $e2');
      }
    } catch (e) {
      debugPrint('❌ Erreur programmation notification: $e');
    }
  }

  Future<void> cancelAll() async {
    if (!isSupported) return;
    await init();
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('❌ Erreur annulation notifications: $e');
    }
  }
}