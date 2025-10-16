import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../repositories/auth_repository.dart';
import '../repositories/chat_repository.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
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
    final draft = prefs.getString('draft_\${widget.chat.id}');
    if (draft != null) {
      _textController.text = draft;
    }
  }

  Future<void> _saveDraft(String text) async {
    final prefs = await SharedPreferences.getInstance();
    if (text.trim().isEmpty) {
      await prefs.remove('draft_\${widget.chat.id}');
    } else {
      await prefs.setString('draft_\${widget.chat.id}', text);
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
    final userId = await AuthRepository.getCurrentUserId();
    if (userId != null) {
      setState(() {
        _currentUserId = userId;
      });
      await widget.chatRepository.connectToChat(widget.chat);
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
    if (pickedFile == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Загрузка видео..."), duration: Duration(seconds: 10)),
    );

    await widget.chatRepository.sendVideoMessage(
      filePath: pickedFile.path,
      chatId: widget.chat.id,
      senderId: _currentUserId,
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
                return ListView.builder(
                  controller: _scrollController,
                  reverse: false,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return Slidable(
                      key: _messageKeys[msg.id],
                      endActionPane: ActionPane(
                        motion: const StretchMotion(),
                        dismissible: DismissiblePane(
                          onDismissed: () {},
                          confirmDismiss: () async {
                            _enterReplyMode(msg);
                            return false;
                          },
                        ),
                        children: [
                          SlidableAction(
                            onPressed: (context) => _enterReplyMode(msg),
                            backgroundColor: Colors.transparent,
                            foregroundColor: Theme.of(context).primaryColor,
                            icon: Icons.reply,
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
          if (_replyMessage != null) _buildReplyPreview(),
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
