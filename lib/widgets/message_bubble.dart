import 'package:flutter/material.dart';
import 'package:LangBridge/models/message.dart';
import 'package:LangBridge/repositories/chat_repository.dart';
import 'video_transcription_widget.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final String currentUserId;
  final ChatRepository chatRepository;
  final VoidCallback onReply; // Для долгого нажатия/меню
  final Function(String messageId) onQuoteTap; // Для клика по цитате


  const MessageBubble({
    Key? key,
    required this.message,
    required this.currentUserId,
    required this.chatRepository,
    required this.onReply,
    required this.onQuoteTap,
  }) : super(key: key);

  Widget _buildQuote(BuildContext context) {
    final repliedMessage = message.repliedToMessage!;
    String contentPreview;
    switch(repliedMessage.type) {
    // ... (логика как в _buildReplyPreview)
      default:
        contentPreview = repliedMessage.content;
    }

    return GestureDetector(
      onTap: () => onQuoteTap(repliedMessage.id),
      child: Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: Theme.of(context).primaryColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              repliedMessage.senderId == currentUserId ? "Вы" : "Собеседник",
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(contentPreview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.senderId == currentUserId;
    final isSystem = message.senderId == "system";

    return InkWell( // Оборачиваем в InkWell для долгого нажатия
      onLongPress: onReply, // Вызываем колбэк по долгому нажатию
      child: Align(
        alignment: isSystem ? Alignment.center : (isUser ? Alignment.centerRight : Alignment.centerLeft),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSystem
                ? Colors.amber.shade100
                : isUser
                ? Colors.blue.shade100
                : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (message.repliedToMessage != null)
                _buildQuote(context),
              if (!isUser && !isSystem)
                Text(
                  message.senderId, // В будущем можно подтягивать имя пользователя
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54),
                ),
              if (message.type == MessageType.text)
                Text(message.content)
              else if (message.type == MessageType.video)
              // ИСПОЛЬЗУЕМ НОВЫЙ ВИДЖЕТ
                VideoTranscriptionWidget(
                  message: message,
                  chatRepository: chatRepository,
                  isUser: isUser,
                )
              else
                Text("Unsupported message type"),
              SizedBox(height: 4),
              Text(
                "${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}",
                style: TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ],
          ),
        )
      ),
    );
  }
}
