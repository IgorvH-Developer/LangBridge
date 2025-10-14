import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:LangBridge/config/app_config.dart';
import 'transcription_data.dart';

enum MessageType { text, image, video, audio }

class Message {
  final String id;
  final String senderId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final Message? repliedToMessage;

  String? videoUrl;
  TranscriptionData? transcription;

  Message({
    required this.id,
    required this.senderId,
    required this.content,
    required this.type,
    required this.timestamp,
    this.repliedToMessage,
  }) {
    if (type == MessageType.video) {
      try {
        final data = jsonDecode(content);
        final rawVideoUrl = data['video_url'];
        if (rawVideoUrl != null && rawVideoUrl.isNotEmpty) {
          // --- ДОБАВЬТЕ ЭТУ ЛОГИКУ ---
          if (rawVideoUrl.startsWith('http')) {
            videoUrl = rawVideoUrl;
          } else {
            videoUrl = "${AppConfig.apiBaseUrl}$rawVideoUrl";
          }
        }
      } catch (e) {
        print('Ошибка парсинга JSON: $e');
        // Ошибка парсинга
      }
    }
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    MessageType type = MessageType.values.firstWhere(
            (e) => e.toString().split('.').last == (json['type'] ?? 'text'),
        orElse: () => MessageType.text);

    Message? repliedTo;
    if (json['replied_to_message'] != null) {
      // Создаем "ненастоящее" сообщение из кратких данных
      repliedTo = Message(
        id: json['replied_to_message']['id'],
        senderId: json['replied_to_message']['sender_id'],
        content: json['replied_to_message']['content'],
        type: MessageType.values.firstWhere(
                (e) => e.toString().split('.').last == (json['replied_to_message']['type'] ?? 'text'),
            orElse: () => MessageType.text),
        timestamp: DateTime.now(), // Timestamp здесь не важен
      );
    }

    return Message(
      id: json['id'] ?? const Uuid().v4(),
      senderId: json['sender_id'] ?? json['sender'] ?? 'unknown_sender',
      content: json['content'] is String ? json['content'] : jsonEncode(json['content']),
      type: type,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      repliedToMessage: repliedTo,
    );
  }

  factory Message.fromLastMessageJson(Map<String, dynamic> json) {
    // Этот конструктор очень упрощен, так как нам нужны только content и timestamp
    return Message(
      id: '', // ID не важен для отображения в списке
      senderId: '', // Sender не важен
      content: json['content'] ?? '',
      type: MessageType.values.firstWhere(
              (e) => e.toString().split('.').last == (json['type'] ?? 'text'),
          orElse: () => MessageType.text),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  // Метод для обновления сообщения новой транскрипцией
  Message withTranscription(TranscriptionData newTranscription) {
    final Map<String, dynamic> contentData = jsonDecode(content);
    contentData['transcription'] = newTranscription.toJson();

    return Message(
      id: id,
      senderId: senderId,
      content: jsonEncode(contentData),
      type: type,
      timestamp: timestamp,
    );
  }
}
