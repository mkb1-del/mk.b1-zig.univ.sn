import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import '../messages/chat_view.dart';

class DoctorMessagesView extends StatefulWidget {
  const DoctorMessagesView({super.key});

  @override
  State<DoctorMessagesView> createState() => _DoctorMessagesViewState();
}

class _DoctorMessagesViewState extends State<DoctorMessagesView> {
  final AuthService _authService = AuthService();
  List<UserModel> _patients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() => _isLoading = true);
    try {
      final allUsers = await _authService.getAllDoctors();
      setState(() {
        _patients = allUsers.where((u) => u.userType == 'patient').toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('❌ Erreur chargement patientes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 0,
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _patients.isEmpty
              ? const Center(
                  child: Text(
                    'Aucune conversation',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _patients.length,
                  itemBuilder: (context, index) {
                    final patient = _patients[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.pink.shade100,
                          child: Text(
                            patient.name.isNotEmpty 
                                ? patient.name[0].toUpperCase() 
                                : 'P',
                            style: const TextStyle(color: Colors.pink),
                          ),
                        ),
                        title: Text(
                          patient.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text('Appuyer pour discuter'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatView(
                                receiverId: patient.id,
                                receiverName: patient.name,
                                receiverAvatar: patient.avatarUrl,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}