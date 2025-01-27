import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class Message {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final bool isImage;
  final String? imageUrl;

  Message({
    required this.id,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.isImage = false,
    this.imageUrl,
  });
}

class ChatScreen extends StatefulWidget {
  final String receiverId;
  final String otherUserName;
  final bool isParent;

  const ChatScreen({
    Key? key,
    required this.receiverId,
    required this.otherUserName,
    required this.isParent,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _supabase = Supabase.instance.client;
  final _scrollController = ScrollController();
  final List<Message> _messages = [];
  RealtimeChannel? _channel;
  bool _isLoading = false;
  String? _currentUserId;

  // Generate a unique chat ID for two users
  String _getChatId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (_currentUserId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login first')),
        );
      });
      return;
    }
    _loadMessages();
    _setupRealtimeSubscription();

    // Add listener to scroll to bottom after initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _setupRealtimeSubscription() {
    final chatId = _getChatId(_currentUserId!, widget.receiverId);

    final channel = _supabase
        .channel('public:messages:$chatId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'chat_id',
        value: chatId,
      ),
      callback: (payload) {
        if (payload.newRecord['sender_id'] != _currentUserId) {
          final message = Message(
            id: payload.newRecord['id'],
            senderId: payload.newRecord['sender_id'],
            content: payload.newRecord['content'],
            timestamp: DateTime.parse(payload.newRecord['created_at']),
            isImage: payload.newRecord['is_image'] ?? false,
            imageUrl: payload.newRecord['image_url'],
          );

          if (mounted) {
            setState(() => _messages.add(message));
            // Add a small delay before scrolling
            Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
          }
        }
      },
    );

    channel.subscribe((status, [_]) {
      if (status == 'SUBSCRIBED') {
        _channel = channel;
      }
    });
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoading = true);

      final chatId = _getChatId(_currentUserId!, widget.receiverId);

      final response = await _supabase
          .from('messages')
          .select()
          .eq('chat_id', chatId)
          .order('created_at', ascending: false) // Change to descending order
          .limit(50); // Limit to last 50 messages for better performance

      final messages = (response as List).map((msg) => Message(
        id: msg['id'],
        senderId: msg['sender_id'],
        content: msg['content'],
        timestamp: DateTime.parse(msg['created_at']),
        isImage: msg['is_image'] ?? false,
        imageUrl: msg['image_url'],
      )).toList();

      setState(() {
        _messages.clear();
        _messages.addAll(messages.reversed); // Reverse the messages to show in correct order
        _isLoading = false;
      });

      // Scroll to bottom after messages load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading messages: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // Update the send message method
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    if (_currentUserId == null) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      final chatId = _getChatId(_currentUserId!, widget.receiverId);

      final newMessage = await _supabase.from('messages').insert({
        'chat_id': chatId,
        'sender_id': _currentUserId,
        'receiver_id': widget.receiverId,
        'content': messageText,
        'is_image': false
      }).select().single();

      final message = Message(
        id: newMessage['id'],
        senderId: newMessage['sender_id'],
        content: newMessage['content'],
        timestamp: DateTime.parse(newMessage['created_at']),
        isImage: newMessage['is_image'] ?? false,
        imageUrl: newMessage['image_url'],
      );

      if (mounted) {
        setState(() => _messages.add(message));
        // Add a small delay for UI update
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: $e')),
        );
      }
    }
  }


  Future<void> _sendImage() async {
    try {
      if (_currentUserId == null) throw Exception('User not logged in');

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isLoading = true);

      final file = File(image.path);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_currentUserId}.jpg';
      final chatId = _getChatId(_currentUserId!, widget.receiverId);

      await _supabase.storage
          .from('chat_images')
          .upload(fileName, file);

      final imageUrl = _supabase.storage
          .from('chat_images')
          .getPublicUrl(fileName);

      final newMessage = await _supabase.from('messages').insert({
        'chat_id': chatId,
        'sender_id': _currentUserId,
        'receiver_id': widget.receiverId,
        'content': 'Image sent',
        'is_image': true,
        'image_url': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      final message = Message(
        id: newMessage['id'],
        senderId: newMessage['sender_id'],
        content: newMessage['content'],
        timestamp: DateTime.parse(newMessage['created_at']),
        isImage: true,
        imageUrl: imageUrl,
      );

      if (mounted) {
        setState(() {
          _messages.add(message);
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending image: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // Add a small delay to ensure the list has been built
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4B0082),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                widget.otherUserName[0].toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF4B0082),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherUserName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.isParent ? 'Child' : 'Parent',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // Add chat options menu
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4B0082)),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMe = message.senderId == _currentUserId;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: isMe
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      if (!isMe) ...[
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.grey[300],
                          child: Text(
                            widget.otherUserName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF4B0082),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        constraints: BoxConstraints(
                          maxWidth:
                          MediaQuery.of(context).size.width * 0.65,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? const Color(0xFF4B0082)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: message.isImage
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            message.imageUrl!,
                            width: 200,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(
                                  valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                      Color(0xFF4B0082)),
                                  strokeWidth: 2,
                                ),
                              );
                            },
                          ),
                        )
                            : Text(
                          message.content,
                          style: TextStyle(
                            color:
                            isMe ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    onPressed: _sendImage,
                    color: const Color(0xFF4B0082),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 12,
                          ),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF4B0082),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded),
                      onPressed: _sendMessage,
                      color: Colors.white,
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

  @override
  void dispose() {
    _messageController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }
}