/// Ticket de rendez-vous : ce que la patiente reçoit quand elle fait sa demande.
///
/// Le numéro de référence (par exemple RDV-3F9A1C2B) est tiré de l'identifiant
/// du rendez-vous : la patiente et le médecin voient exactement le même, ce qui
/// permet de retrouver le rendez-vous à l'accueil.
class AppointmentTicket {
  final String appointmentId;
  final String code;
  final String patientName;
  final String doctorName;
  final String doctorSpecialty;
  final String hospital;
  final DateTime? when;
  final String reason;

  /// pending | confirmed | cancelled | completed
  final String status;

  const AppointmentTicket({
    required this.appointmentId,
    required this.code,
    required this.patientName,
    required this.doctorName,
    required this.doctorSpecialty,
    required this.hospital,
    required this.when,
    required this.reason,
    required this.status,
  });

  static const List<String> _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const List<String> _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Numéro de référence lisible à partir de l'identifiant du rendez-vous.
  /// Seuls des chiffres et des lettres A à F (identifiant hexadécimal) sont
  /// utilisés : pas de confusion possible entre 0 et O, ni entre 1 et I.
  static String codeFor(String id) {
    final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (clean.isEmpty) return 'RDV-00000000';
    if (RegExp(r'^[0-9]+$').hasMatch(clean) && clean.length <= 8) {
      return 'RDV-${clean.padLeft(8, '0')}';
    }
    return 'RDV-${clean.length < 8 ? clean : clean.substring(0, 8)}';
  }

  /// Construit le ticket à partir d'une ligne de la table des rendez-vous.
  /// Le lieu enregistré dans le rendez-vous fait foi ; à défaut, [hospital].
  factory AppointmentTicket.fromRow(
    Map<String, dynamic> row, {
    required String patientName,
    required String doctorName,
    String doctorSpecialty = '',
    String hospital = '',
  }) {
    final id = row['id'].toString();
    final date = row['date']?.toString() ?? '';
    final time = row['time']?.toString() ?? '';
    final saved = (row['hospital']?.toString() ?? '').trim();

    return AppointmentTicket(
      appointmentId: id,
      code: codeFor(id),
      patientName: patientName.trim(),
      doctorName: doctorName.trim(),
      doctorSpecialty: doctorSpecialty.trim(),
      hospital: saved.isNotEmpty ? saved : hospital.trim(),
      when: DateTime.tryParse(time.isEmpty ? date : '$date $time'),
      reason: (row['reason']?.toString() ?? '').trim(),
      status: row['status']?.toString() ?? 'pending',
    );
  }

  /// « mardi 12 novembre 2026 »
  String get dateLabel {
    final w = when;
    if (w == null) return '';
    return '${_weekdays[w.weekday - 1]} ${w.day} ${_months[w.month - 1]} ${w.year}';
  }

  /// « 09:00 »
  String get timeLabel {
    final w = when;
    return w == null ? '' : '${_two(w.hour)}:${_two(w.minute)}';
  }

  /// Contenu du code QR. Aucune donnée de santé : seulement le numéro, la date
  /// et l'heure.
  String get qrPayload {
    final w = when;
    final day = w == null ? '' : '${w.year}-${_two(w.month)}-${_two(w.day)}';
    return 'SUNUYAAKAAR|$code|$day|$timeLabel';
  }

  /// Message selon le statut.
  String get statusMessage {
    switch (status) {
      case 'confirmed':
        return 'Rendez-vous confirmé par votre médecin.';
      case 'cancelled':
        return 'Ce rendez-vous a été annulé.';
      case 'completed':
        return 'Ce rendez-vous est terminé.';
      default:
        return 'Votre médecin doit confirmer cette demande. Vous serez prévenue dès que ce sera fait.';
    }
  }

  String get statusTitle {
    switch (status) {
      case 'confirmed':
        return 'CONFIRMÉ';
      case 'cancelled':
        return 'ANNULÉ';
      case 'completed':
        return 'TERMINÉ';
      default:
        return 'EN ATTENTE DE CONFIRMATION';
    }
  }
}