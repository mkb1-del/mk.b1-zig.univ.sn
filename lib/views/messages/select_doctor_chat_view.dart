import 'package:flutter/material.dart';
import 'conversations_view.dart';

/// Choix d'un médecin pour discuter : même écran que la liste des
/// conversations de la patiente (route /select-doctor-chat).
class SelectDoctorChatView extends StatelessWidget {
  const SelectDoctorChatView({super.key});

  @override
  Widget build(BuildContext context) => const ConversationsView();
}