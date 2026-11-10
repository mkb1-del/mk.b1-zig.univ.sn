import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/care_reminder_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';

class RemindersView extends StatefulWidget {
  const RemindersView({super.key});

  @override
  State<RemindersView> createState() => _RemindersViewState();
}

class _RemindersViewState extends State<RemindersView> {
  final CareReminderService _service = CareReminderService();
  final NotificationService _notifications = NotificationService.instance;

  ReminderPreferences _prefs = const ReminderPreferences();
  bool _isLoading = true;
  bool _notificationsEnabled = false;

  static const List<IconData> _slotIcons = [
    Icons.wb_twilight,
    Icons.wb_sunny_outlined,
    Icons.nights_stay_outlined,
    Icons.bedtime_outlined,
  ];

  String? get _patientId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final patientId = _patientId;
    if (patientId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final prefs = await _service.getPreferences(patientId);
    final enabled = await _notifications.areEnabled();

    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _notificationsEnabled = enabled;
      _isLoading = false;
    });
  }

  Future<void> _update(ReminderPreferences newPrefs) async {
    setState(() => _prefs = newPrefs);

    final patientId = _patientId;
    if (patientId == null) return;

    final ok = await _service.savePreferences(patientId, newPrefs);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Impossible d\'enregistrer vos réglages'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // Reprogramme les notifications du téléphone avec les nouveaux réglages.
    _service.syncDeviceNotifications(patientId);
  }

  Future<void> _pickTime(int slot) async {
    final current = CareReminderService.timeOn(DateTime.now(), _prefs.times[slot]);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;

    final times = List<String>.from(_prefs.times);
    times[slot] =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    await _update(_prefs.copyWith(times: times));
  }

  Future<void> _requestPermission() async {
    final granted = await _notifications.requestPermission();
    final enabled = await _notifications.areEnabled();

    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled || granted);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (enabled || granted)
              ? '✅ Notifications activées'
              : 'Les notifications sont refusées. Activez-les dans les réglages du téléphone.',
        ),
        backgroundColor: (enabled || granted) ? AppColors.teal : AppColors.amber,
      ),
    );

    final patientId = _patientId;
    if (patientId != null) _service.syncDeviceNotifications(patientId);
  }

  Future<void> _sendTestNow() async {
    await _notifications.showNow(
      title: 'Sunu Yaakaar',
      body: 'Les notifications fonctionnent. Prenez soin de vous.',
    );
  }

  Future<void> _sendTestInOneMinute() async {
    await _notifications.scheduleAt(
      id: 999001,
      title: 'Sunu Yaakaar · Test de rappel',
      body: 'Ceci est un rappel programmé il y a une minute.',
      when: DateTime.now().add(const Duration(minutes: 1)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rappel de test programmé dans 1 minute. Vous pouvez quitter l\'application.'),
        backgroundColor: AppColors.teal,
      ),
    );
  }

  // ------------------------------------------------------------------ UI

  Widget _buildTogglesCard() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text(
              'Rappels de rendez-vous',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            subtitle: const Text(
              'La veille et 2 heures avant',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            value: _prefs.appointmentReminders,
            onChanged: (value) =>
                _update(_prefs.copyWith(appointmentReminders: value)),
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text(
              'Rappels de prise de médicaments',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            subtitle: const Text(
              'Aux horaires choisis ci-dessous',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            value: _prefs.medicationReminders,
            onChanged: (value) =>
                _update(_prefs.copyWith(medicationReminders: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildTimesCard() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < CareReminderService.slotLabels.length; i++) ...[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickTime(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.rose.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_slotIcons[i], color: AppColors.rose, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        CareReminderService.slotLabels[i],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.roseSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _prefs.times[i],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.rose,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < CareReminderService.slotLabels.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceCard() {
    if (!_notifications.isSupported) {
      return const AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: AppColors.sky),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Les notifications du téléphone sont disponibles sur Android et iOS. '
                'Dans le navigateur, vos rappels s\'affichent dans l\'application.',
                style: TextStyle(fontSize: 14, color: AppColors.ink, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _notificationsEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                color: _notificationsEnabled ? AppColors.teal : AppColors.amber,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _notificationsEnabled
                      ? 'Notifications activées'
                      : 'Notifications non autorisées',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_notificationsEnabled)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Autoriser les notifications'),
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _sendTestNow,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Envoyer une notification test'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _sendTestInOneMinute,
                icon: const Icon(Icons.schedule_send_outlined),
                label: const Text('Tester dans 1 minute'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes rappels')),
      body: _isLoading
          ? const SkeletonPage()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const SectionTitle(title: 'Types de rappels'),
                _buildTogglesCard(),
                const SizedBox(height: 28),
                const SectionTitle(title: 'Mes horaires de prise'),
                _buildTimesCard(),
                const SizedBox(height: 28),
                const SectionTitle(title: 'Notifications du téléphone'),
                _buildDeviceCard(),
              ],
            ),
    );
  }
}
