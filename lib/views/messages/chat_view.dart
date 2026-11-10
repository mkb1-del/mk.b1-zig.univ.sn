import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/skeleton.dart';
import '../../theme/app_theme.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/message_service.dart';
import '../../services/realtime_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_errors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/user_avatar.dart';
import '../../models/message_model.dart';

class ChatView extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String? receiverAvatar;

  /// Ligne sous le nom dans la barre du haut (spécialité du médecin, par exemple).
  final String? receiverSubtitle;

  const ChatView({
    super.key,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
    this.receiverSubtitle,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final MessageService _messageService = MessageService();
  final AuthService _authService = AuthService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  String? _currentUserId;
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _hasText = false;

  // --- Chargement par pages ---
  bool _loadError = false;
  bool _hasMore = false;
  bool _loadingOlder = false;
  String? _oldestCreatedAt;
  String? _newestCreatedAt;
  bool _fetchingNew = false;
  bool _fetchAgain = false;
  StreamSubscription<LiveEvent>? _liveSub;

  // --- Enregistrement vocal (style WhatsApp, détection manuelle via Listener) ---
  bool _isRecording = false;
  bool _cancelHint = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  Timer? _longPressTimer;
  double _pointerStartX = 0;
  double _dragDx = 0;
  static const double _cancelThreshold = -80;
  static const Duration _longPressDuration = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initializeChat();
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  Future<void> _initializeChat() async {
    final user = await _authService.getCurrentUser();
    if (!mounted) return;

    if (user == null) {
      setState(() {
        _isLoading = false;
        _loadError = true;
      });
      return;
    }

    setState(() => _currentUserId = user.id);
    await _loadMessages();
    if (!mounted) return;
    await _markAllAsRead();

    // Messages de cet interlocuteur reçus en direct
    RealtimeService.instance.activeChatPartnerId = widget.receiverId;
    _liveSub = RealtimeService.instance.events.listen(_onLiveEvent);
  }

  void _showError(Object? error, {String? prefix}) {
    if (!mounted) return;
    final text = AppErrors.message(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(prefix == null ? '❌ $text' : '❌ $prefix $text'),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  void _showSendFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('❌ Message non envoyé. Vérifiez votre connexion puis réessayez.'),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  /// Charge (ou recharge) les messages les plus récents.
  /// silent = true : sans écran de chargement.
  Future<void> _loadMessages({bool silent = false}) async {
    if (_currentUserId == null) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _loadError = false;
      });
    }
    try {
      final page = await _messageService.getConversationPage(
        _currentUserId!,
        widget.receiverId,
      );
      if (!mounted) return;
      setState(() {
        _messages = page.messages;
        _hasMore = page.hasMore;
        _oldestCreatedAt = page.oldestCreatedAt;
        _newestCreatedAt = page.newestCreatedAt;
        _isLoading = false;
        _loadError = false;
      });
      _scrollToBottom();
    } catch (e) {
      AppErrors.log('chargement des messages', e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_messages.isEmpty) _loadError = true;
      });
      if (_messages.isNotEmpty) _showError(e);
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 160;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 120 &&
        _hasMore &&
        !_loadingOlder &&
        !_isLoading) {
      _loadOlder();
    }
  }

  /// Charge les messages plus anciens (en remontant dans la conversation) sans
  /// faire sauter la position de lecture.
  Future<void> _loadOlder() async {
    final oldest = _oldestCreatedAt;
    if (oldest == null || _currentUserId == null || _loadingOlder) return;

    setState(() => _loadingOlder = true);
    try {
      final page = await _messageService.getConversationPage(
        _currentUserId!,
        widget.receiverId,
        before: oldest,
      );
      if (!mounted) return;

      final hadClients = _scrollController.hasClients;
      final extentBefore = hadClients ? _scrollController.position.maxScrollExtent : 0.0;
      final pixelsBefore = hadClients ? _scrollController.position.pixels : 0.0;

      setState(() {
        _messages = [...page.messages, ..._messages];
        _hasMore = page.hasMore;
        _oldestCreatedAt = page.oldestCreatedAt ?? _oldestCreatedAt;
        _loadingOlder = false;
      });

      // La liste s'est allongée au-dessus : on garde le message qu'on lisait.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final extentAfter = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(pixelsBefore + (extentAfter - extentBefore));
      });
    } catch (e) {
      AppErrors.log('messages précédents', e);
      if (!mounted) return;
      setState(() => _loadingOlder = false);
      _showError(e, prefix: 'Messages précédents indisponibles.');
    }
  }

  /// Ajoute seulement les messages arrivés depuis le dernier affiché.
  /// Les appels simultanés sont mis en file : aucun message n'est ajouté deux fois.
  Future<void> _loadNewMessages() async {
    if (_currentUserId == null) return;

    if (_newestCreatedAt == null) {
      // Conversation encore vide : premier chargement complet.
      await _loadMessages(silent: true);
      return;
    }
    if (_fetchingNew) {
      _fetchAgain = true;
      return;
    }

    _fetchingNew = true;
    try {
      do {
        _fetchAgain = false;
        final page = await _messageService.getMessagesAfter(
          _currentUserId!,
          widget.receiverId,
          _newestCreatedAt!,
        );
        if (!mounted) return;

        if (page.messages.isNotEmpty) {
          final wasNearBottom = _isNearBottom();
          final iSentOne = page.messages.any((m) => m.senderId == _currentUserId);
          setState(() {
            _messages = [..._messages, ...page.messages];
            _newestCreatedAt = page.newestCreatedAt ?? _newestCreatedAt;
          });
          // On ne fait pas sauter l'écran de quelqu'un qui relit d'anciens messages.
          if (wasNearBottom || iSentOne) _scrollToBottom();
        }
      } while (_fetchAgain && mounted);
    } catch (e) {
      AppErrors.log('nouveaux messages', e);
    } finally {
      _fetchingNew = false;
    }
  }

  Future<void> _markAllAsRead() async {
    await _messageService.markAllMessagesAsRead(_currentUserId!, widget.receiverId);
  }

  /// Un message de l'interlocuteur arrive : la conversation se met à jour toute seule.
  Future<void> _onLiveEvent(LiveEvent event) async {
    if (!mounted || _currentUserId == null) return;
    final fromPartner =
        event.type == LiveEventType.message && event.senderId == widget.receiverId;
    if (fromPartner) {
      await _loadNewMessages();
      await _markAllAsRead();
    } else if (event.type == LiveEventType.refresh) {
      await _loadNewMessages();
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUserId == null) return;

    final message = await _messageService.sendTextMessage(
      senderId: _currentUserId!,
      receiverId: widget.receiverId,
      content: text,
    );
    if (!mounted) return;

    if (message != null) {
      _messageController.clear();
      await _loadNewMessages();
    } else {
      _showSendFailure();
    }
  }

  // --- Logique d'enregistrement façon WhatsApp (via Listener bas niveau) ---

  void _onPointerDown(PointerDownEvent event) {
    if (_hasText) return;
    _pointerStartX = event.position.dx;
    _longPressTimer = Timer(_longPressDuration, () {
      _startRecording();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isRecording) return;
    final dx = event.position.dx - _pointerStartX;
    setState(() {
      _dragDx = dx;
      _cancelHint = dx < _cancelThreshold;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_longPressTimer != null && _longPressTimer!.isActive) {
      _longPressTimer!.cancel();
      return;
    }
    if (_isRecording) {
      _endRecording();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    if (_isRecording) {
      _endRecording(forceCancel: true);
    }
  }

  Future<void> _startRecording() async {
    final success = await _messageService.startRecording();
    if (success && mounted) {
      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
        _dragDx = 0;
        _cancelHint = false;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration++;
        });
      });
    }
  }

  Future<void> _endRecording({bool forceCancel = false}) async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    final shouldCancel = forceCancel || _cancelHint;
    final duration = _recordingDuration;

    setState(() {
      _isRecording = false;
      _dragDx = 0;
      _cancelHint = false;
    });

    if (shouldCancel) {
      await _messageService.cancelRecording();
      return;
    }

    final stoppedDuration = await _messageService.stopRecording();
    final finalDuration = stoppedDuration ?? duration;

    if (finalDuration < 1) {
      await _messageService.cancelRecording();
      return;
    }

    final message = await _messageService.sendVoiceMessage(
      senderId: _currentUserId!,
      receiverId: widget.receiverId,
      duration: finalDuration,
    );

    if (!mounted) return;
    if (message != null) {
      await _loadNewMessages();
    } else {
      _showSendFailure();
    }
  }

  // --- Sélection photo : pas de redimensionnement côté web (bug canvas
  // noir connu d'image_picker), et transmission du vrai type MIME pour
  // que l'upload déclare le bon Content-Type. ---

  Future<void> _sendPickedImage(XFile image) async {
    final message = await _messageService.sendPhotoMessage(
      senderId: _currentUserId!,
      receiverId: widget.receiverId,
      filePath: image.path,
      mimeType: image.mimeType,
    );

    if (!mounted) return;
    if (message != null) {
      await _loadNewMessages();
    } else {
      _showSendFailure();
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = kIsWeb
        ? await picker.pickImage(source: ImageSource.gallery)
        : await picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1280,
            maxHeight: 1280,
            imageQuality: 80,
          );

    if (image != null && mounted) {
      await _sendPickedImage(image);
    }
  }

  Future<void> _takePhoto() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = kIsWeb
        ? await picker.pickImage(source: ImageSource.camera)
        : await picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1280,
            maxHeight: 1280,
            imageQuality: 80,
          );

    if (image != null && mounted) {
      await _sendPickedImage(image);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.rose),
              title: const Text('Galerie'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.rose),
              title: const Text('Appareil photo'),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _playAudio(String url) async {
    try {
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint('❌ Erreur lecture audio: $e');
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(name: widget.receiverName, url: widget.receiverAvatar, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.receiverName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: AppColors.ink,
                    ),
                  ),
                  if ((widget.receiverSubtitle ?? '').trim().isNotEmpty)
                    Text(
                      widget.receiverSubtitle!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const SkeletonChat()
                : _loadError
                    ? EmptyState(
                        icon: Icons.wifi_off_rounded,
                        title: 'Impossible de charger la conversation',
                        message: 'Vérifiez votre connexion internet puis réessayez.',
                        actionLabel: 'Réessayer',
                        onAction: () => _currentUserId == null ? _initializeChat() : _loadMessages(),
                      )
                    : _messages.isEmpty
                        ? _buildEmptyConversation()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              // Premier élément : chargeur des messages plus anciens.
                              if (_hasMore && index == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Center(
                                    child: _loadingOlder
                                        ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2.5),
                                          )
                                        : TextButton(
                                            onPressed: _loadOlder,
                                            child: const Text('Messages précédents'),
                                          ),
                                  ),
                                );
                              }

                              final i = _hasMore ? index - 1 : index;
                              final message = _messages[i];
                              final isMe = message.senderId == _currentUserId;
                              final previous = i > 0 ? _messages[i - 1] : null;
                              final next = i < _messages.length - 1 ? _messages[i + 1] : null;
                              final newDay = previous == null ||
                                  !_sameDay(previous.createdAt, message.createdAt);
                              // Le dernier message d'une série (même expéditeur, même jour,
                              // moins de 5 minutes d'écart) porte l'avatar et la petite queue.
                              final lastInGroup = next == null ||
                                  next.senderId != message.senderId ||
                                  !_sameDay(next.createdAt, message.createdAt) ||
                                  next.createdAt.difference(message.createdAt).inMinutes.abs() >= 5;

                              return Column(
                                children: [
                                  if (newDay) _buildDaySeparator(message.createdAt),
                                  _buildMessageBubble(message, isMe, lastInGroup: lastInGroup),
                                ],
                              );
                            },
                          ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: _isRecording ? _buildRecordingRow() : _buildNormalRow(),
    );
  }

  Widget _buildNormalRow() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Prendre une photo',
          icon: const Icon(Icons.photo_camera, color: AppColors.rose),
          onPressed: _showImageSourceDialog,
        ),
        Expanded(
          child: TextField(
            controller: _messageController,
            decoration: InputDecoration(
              hintText: 'Écrire un message...',
              hintStyle: const TextStyle(color: AppColors.muted),
              filled: true,
              fillColor: AppColors.roseSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        const SizedBox(width: 8),
        Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            onTap: _hasText ? _sendMessage : null,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppColors.rose,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _hasText ? Icons.send : Icons.mic,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingRow() {
    final offset = _dragDx.clamp(_cancelThreshold * 1.5, 0.0);

    return Listener(
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Row(
        children: [
          Expanded(
            child: Transform.translate(
              offset: Offset(offset, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _cancelHint ? AppColors.roseSoft : AppColors.roseSoft,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(_recordingDuration),
                      style: const TextStyle(
                        color: AppColors.dangerText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (!_cancelHint) ...[
                      const Icon(Icons.chevron_left, color: AppColors.muted, size: 18),
                      const Text(
                        'Glisser pour annuler',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ] else
                      const Text(
                        'Relâchez pour annuler',
                        style: TextStyle(
                          color: AppColors.dangerText,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _cancelHint ? AppColors.muted : AppColors.danger,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe, {bool lastInGroup = true}) {
    const big = Radius.circular(18);
    const small = Radius.circular(5);

    return Padding(
      padding: EdgeInsets.only(bottom: lastInGroup ? 12 : 3),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            if (lastInGroup)
              UserAvatar(name: widget.receiverName, url: widget.receiverAvatar, radius: 16)
            else
              const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.74,
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: isMe ? AppColors.rose : Colors.white,
                border: isMe ? null : Border.all(color: AppColors.border),
                borderRadius: BorderRadius.only(
                  topLeft: big,
                  topRight: big,
                  bottomLeft: (!isMe && lastInGroup) ? small : big,
                  bottomRight: (isMe && lastInGroup) ? small : big,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMessageContent(message),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.timeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.85)
                                : AppColors.muted,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            message.isRead ? Icons.done_all : Icons.done,
                            size: 15,
                            // Lu : bleu clair, bien visible sur la bulle rose.
                            color: message.isRead
                                ? const Color(0xFFB3E5FC)
                                : Colors.white.withValues(alpha: 0.85),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(Message message) {
    switch (message.type) {
      case MessageType.text:
        return Text(
          message.content,
          style: TextStyle(
            color: message.senderId == _currentUserId
                ? Colors.white
                : AppColors.ink,
          ),
        );

      case MessageType.voice:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: message.senderId == _currentUserId
                ? Colors.white.withValues(alpha: 0.2)
                : AppColors.roseSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Écouter le message vocal',
                icon: Icon(
                  Icons.play_arrow,
                  color: message.senderId == _currentUserId
                      ? Colors.white
                      : AppColors.rose,
                ),
                onPressed: () => _playAudio(message.mediaUrl!),
                iconSize: 24,
              ),
              Text(
                _formatDuration(message.duration ?? 0),
                style: TextStyle(
                  color: message.senderId == _currentUserId
                      ? Colors.white
                      : AppColors.ink,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );

      case MessageType.photo:
        return GestureDetector(
          onTap: () => _openPhoto(message.mediaUrl!),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: message.mediaUrl!,
              placeholder: (context, url) => Container(
                height: 200,
                color: AppColors.border,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                height: 200,
                color: AppColors.border,
                child: const Icon(Icons.broken_image, size: 50),
              ),
              fit: BoxFit.cover,
            ),
          ),
        );
    }
  }

  // ------------------------------------------------------------ Aides d'affichage

  static const List<String> _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const List<String> _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];

  bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  /// « Aujourd'hui », « Hier », « lundi 3 novembre » (avec l'année si elle diffère).
  String _dayLabel(DateTime date) {
    final d = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Aujourd\'hui';
    if (diff == 1) return 'Hier';
    final base = '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
    return d.year == now.year ? base : '$base ${d.year}';
  }

  Widget _buildDaySeparator(DateTime date) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.roseSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _dayLabel(date),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.roseDark,
            ),
          ),
        ),
      ),
    );
  }

  /// Conversation sans message : une invitation à écrire, avec un rappel de prudence.
  Widget _buildEmptyConversation() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.roseSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline, size: 34, color: AppColors.rose),
            ),
            const SizedBox(height: 16),
            const Text(
              'Commencez la conversation',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Envoyez un premier message à ${widget.receiverName}.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            const Text(
              'En cas d\'urgence, ne passez pas par la messagerie : contactez le service d\'urgence le plus proche.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.dangerText, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  /// Affiche une photo en plein écran : pincer pour zoomer.
  void _openPhoto(String url) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) =>
                      const Icon(Icons.broken_image, size: 60, color: Colors.white54),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    if (RealtimeService.instance.activeChatPartnerId == widget.receiverId) {
      RealtimeService.instance.activeChatPartnerId = null;
    }
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _recordingTimer?.cancel();
    _longPressTimer?.cancel();
    _messageService.dispose();
    super.dispose();
  }
}