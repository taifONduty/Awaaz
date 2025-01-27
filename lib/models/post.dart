// models/post.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String title;
  final String content;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final int votes;
  final int commentCount;
  final List<String> tags;
  final bool isPinned;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.title,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    this.votes = 0,
    this.commentCount = 0,
    this.tags = const [],
    this.isPinned = false,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    DateTime parseDateTime(dynamic timestamp) {
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      } else if (timestamp is String) {
        return DateTime.parse(timestamp);
      } else {
        return DateTime.now(); // fallback
      }
    }
    return Post(
      id: json['id'],
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      authorId: json['authorId'] ?? '',
      authorName: json['authorName'] ?? 'Anonymous',
      authorAvatar: json['authorAvatar'],
      votes: json['votes'] ?? 0,
      commentCount: json['commentCount'] ?? 0,
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.parse(json['createdAt']),
      tags: List<String>.from(json['tags'] ?? []),
      isPinned: json['isPinned'] ?? false,
    );

  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'authorId': authorId,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'votes': votes,
      'commentCount': commentCount,
      'tags': tags,
      'isPinned': isPinned,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}