import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../repositories/auth_repository.dart';
import '../repositories/chat_repository.dart';
import '../widgets/message_bubble.dart';

const String currentUserFixedId = "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380c99";

class ChatScreen extends StatefulWidget {
  final Chat chat; // Передаем весь объект Chat
  final ChatRepository chatRepository;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.chatRepository,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};

  String _currentUserId = '';
  Message? _replyMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserAndConnect();
    _loadDraft();
    _textController.addListener(() {
      _saveDraft(_textController.text);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.chat.unreadCount > 0) {
        widget.chatRepository.markChatAsRead(widget.chat.id);
      }
    });
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString('draft_${widget.chat.id}');
    if (draft != null) {
      _textController.text = draft;
    }
  }

  Future<void> _saveDraft(String text) async {
    final prefs = await SharedPreferences.getInstance();
    if (text.trim().isEmpty) {
      // Если поле пустое, удаляем черновик
      await prefs.remove('draft_${widget.chat.id}');
    } else {
      await prefs.setString('draft_${widget.chat.id}', text);
    }
  }

  @override
  void dispose() {
    _saveDraft(_textController.text);
    _textController.removeListener(() { _saveDraft(_textController.text); });
    widget.chatRepository.disconnectFromChat();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserAndConnect() async {
    // Предполагается, что у вас есть AuthRepository или подобный сервис
    final userId = await AuthRepository.getCurrentUserId();
    if (userId != null) {
      setState(() {
        _currentUserId = userId;
      });
      widget.chatRepository.connectToChat(widget.chat);
    } else {
      // Обработка случая, когда ID пользователя не найден
    }
  }

  void _sendMessage() {
    if (_textController.text.trim().isEmpty) return;

    widget.chatRepository.sendChatMessage(
      sender: _currentUserId,
      content: _textController.text.trim(),
      type: MessageType.text,
      replyToMessageId: _replyMessage?.id,
    );

    _textController.clear();
    _saveDraft('');
    setState(() {
      _replyMessage = null;
    });
  }

  void _enterReplyMode(Message message) {
    setState(() {
      _replyMessage = message;
    });
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _sendVideo() async {
    final pickedFile = await _picker.pickVideo(source: ImageSource.camera);
    if (pickedFile == null || _currentUserId == null) return;

    // Показываем индикатор загрузки (опционально)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Загрузка видео..."), duration: Duration(seconds: 10)),
    );

    await widget.chatRepository.sendVideoMessage(
      filePath: pickedFile.path,
      chatId: widget.chat.id,
      senderId: _currentUserId!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chat.title ?? "Чат")),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<Message>>(
              valueListenable: widget.chatRepository.messagesStream,
              builder: (context, messages, child) {
                for (var msg in messages) {
                  _messageKeys.putIfAbsent(msg.id, () => GlobalKey());
                }
                if (messages.isEmpty) {

                }
                return ListView.builder(
                  controller: _scrollController, // Привязываем контроллер
                  reverse: false, // Для скроллинга к старым сообщениям reverse должен быть false
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return Slidable( // Оборачиваем бабл в Slidable
                      key: _messageKeys[msg.id], // Привязываем ключ к виджету
                      startActionPane: ActionPane(
                        motion: const StretchMotion(),
                        extentRatio: 0.25,
                        children: [
                          SlidableAction(
                            onPressed: (_) => _enterReplyMode(msg),
                            backgroundColor: Theme.of(context).primaryColorLight,
                            foregroundColor: Colors.black,
                            icon: Icons.reply,
                            label: 'Ответ',
                          ),
                        ],
                      ),
                      child: MessageBubble(
                        message: msg,
                        currentUserId: _currentUserId,
                        chatRepository: widget.chatRepository,
                        onReply: () => _enterReplyMode(msg),
                        onQuoteTap: (messageId) => _scrollToMessage(messageId),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageComposer(),
        ],
      ),
    );
  }

  Widget _buildMessageComposer() {
    return Container(
      color: Colors.grey[100],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyMessage != null)
            _buildReplyPreview(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                icon: const Icon(Icons.videocam),
                onPressed: _sendVideo,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: "Введите сообщение...",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    final message = _replyMessage!;
    String contentPreview;
    switch(message.type) {
      case MessageType.video:
        contentPreview = "Видеосообщение";
        break;
      case MessageType.audio:
        contentPreview = "Голосовое сообщение";
        break;
      default:
        contentPreview = message.content;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Theme.of(context).primaryColor, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // TODO: Подтягивать имя пользователя по senderId
                  message.senderId == _currentUserId ? "Вы" : "Собеседник",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                ),
                const SizedBox(height: 2),
                Text(contentPreview, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _replyMessage = null),
          )
        ],
      ),
    );
  }
}

// Модифицируем _MessageBubble для приема currentUserId
class _MessageBubble extends StatefulWidget {
  final Message message;
  final String currentUserId; // ID текущего пользователя

  const _MessageBubble({required this.message, required this.currentUserId});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == MessageType.video) {
      // Важно: если content это URL, используйте VideoPlayerController.networkUrl
      // Если это путь к файлу (как в примере _sendVideo), то это будет работать только локально.
      // Для реального приложения здесь должен быть URL видео на сервере.
      Uri? videoUri;
      if (widget.message.content.startsWith('http')) {
        videoUri = Uri.tryParse(widget.message.content);
      }

      if (videoUri != null) {
        _videoController = VideoPlayerController.networkUrl(videoUri)
          ..initialize().then((_) {
            if (mounted) setState(() {});
          }).catchError((error) {
            print("Ошибка инициализации видеоплеера: $error");
            if (mounted) setState(() {}); // Чтобы показать ошибку или заглушку
          });
      } else if (widget.message.content.contains('/')) { // Попытка как локальный файл (для тестов)
        _videoController = VideoPlayerController.file(File(widget.message.content))
          ..initialize().then((_) {
            if (mounted) setState(() {});
          }).catchError((error) {
            print("Ошибка инициализации видеоплеера (файл): $error");
            if (mounted) setState(() {});
          });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.senderId == widget.currentUserId; // Сравниваем с ID текущего пользователя

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75), // Ограничение ширины бабла
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.message.senderId == "system"
              ? Colors.amber.shade100 // Цвет для системных сообщений
              : isUser
              ? Colors.blue.shade100
              : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Опционально: показать имя отправителя, если это не текущий пользователь и не система
            if (!isUser && widget.message.senderId != "system")
              Text(
                widget.message.senderId,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54),
              ),
            if (widget.message.type == MessageType.text)
              Text(widget.message.content)
            else if (widget.message.type == MessageType.video)
              _videoController != null && _videoController!.value.isInitialized
                  ? AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_videoController!),
                    IconButton(
                      icon: Icon(
                        _videoController!.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: () {
                        setState(() {
                          _videoController!.value.isPlaying
                              ? _videoController!.pause()
                              : _videoController!.play();
                        });
                      },
                    ),
                  ],
                ),
              )
                  : widget.message.content.startsWith('http') || widget.message.content.contains('/')
                  ? Column( // Показать текст + индикатор, если видео грузится или ошибка
                children: [
                  Text("Видео: ${widget.message.content.split('/').last}", style: TextStyle(fontStyle: FontStyle.italic)),
                  SizedBox(height: 8),
                  CircularProgressIndicator(),
                ],
              )
                  : Text("Не удалось загрузить видео: ${widget.message.content}"), // Если контент не похож на путь или URL
            SizedBox(height: 4),
            Text(
              "${widget.message.timestamp.hour.toString().padLeft(2, '0')}:${widget.message.timestamp.minute.toString().padLeft(2, '0')}",
              style: TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
