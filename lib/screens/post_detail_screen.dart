
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/forum_service.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Detail'),
        backgroundColor: Colors.purple,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPostHeader(),
                  _buildPostContent(),
                  _buildCommentsList(),
                ],
              ),
            ),
          ),
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildPostHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage: NetworkImage(widget.post.authorAvatar),
                radius: 20,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.post.authorName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    _formatTimeAgo(widget.post.createdAt),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.post.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.post.content),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: widget.post.tags.map((tag) => Chip(
              label: Text(tag),
              backgroundColor: Colors.purple[50],
              labelStyle: const TextStyle(color: Colors.purple),
            )).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildVoteButton(true),
              const SizedBox(width: 8),
              Text(
                widget.post.votes.toString(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              _buildVoteButton(false),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _sharePost,
              ),
              IconButton(
                icon: const Icon(Icons.bookmark_border),
                onPressed: _savePost,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoteButton(bool isUpvote) {
    return IconButton(
      icon: Icon(isUpvote ? Icons.arrow_upward : Icons.arrow_downward),
      onPressed: () => _handleVote(isUpvote ? 1 : -1),
      color: Colors.grey[600],
    );
  }

  Widget _buildCommentsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .collection('comments')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No comments yet'));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final commentDoc = snapshot.data!.docs[index];
            final commentData = commentDoc.data() as Map<String, dynamic>;

            return Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 1),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: NetworkImage(
                            commentData['authorAvatar'] ?? 'https://api.dicebear.com/7.x/avataaars/svg?seed=default'
                        ),
                        radius: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        commentData['authorName'] ?? 'Anonymous',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTimeAgo(commentData['createdAt']),
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(commentData['content'] ?? ''),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCommentTile(QueryDocumentSnapshot comment) {
    final data = comment.data() as Map<String, dynamic>;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 1),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage: NetworkImage(data['authorAvatar']),
                radius: 16,
              ),
              const SizedBox(width: 8),
              Text(
                data['authorName'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTimeAgo(DateTime.parse(data['createdAt'])),
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(data['content']),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 16),
                onPressed: () => _handleCommentVote(comment.id, 1),
                color: Colors.grey[600],
              ),
              Text(data['votes'].toString()),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 16),
                onPressed: () => _handleCommentVote(comment.id, -1),
                color: Colors.grey[600],
              ),
              TextButton(
                onPressed: () => _replyToComment(comment.id),
                child: const Text('Reply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Write a comment...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _submitComment,
            color: Colors.purple,
          ),
        ],
      ),
    );
  }

  Future<void> _handleVote(int value) async {
    try {
      await ForumService().votePost(widget.post.id, value);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _handleCommentVote(String commentId, int value) async {
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .collection('comments')
          .doc(commentId)
          .update({
        'votes': FieldValue.increment(value),
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _submitComment() async {
    if (_commentController.text.isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final defaultAvatar = "https://api.dicebear.com/7.x/avataaars/svg?seed=${user.displayName ?? 'anonymous'}";

      // Reference to the comments subcollection of this post
      final commentsRef = FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .collection('comments');

      await commentsRef.add({
        'content': _commentController.text.trim(),
        'authorId': user.uid,
        'authorName': user.displayName ?? 'Anonymous',
        'authorAvatar': user.photoURL ?? defaultAvatar,
        'votes': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update comment count in the post document
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .update({
        'commentCount': FieldValue.increment(1),
      });

      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting comment: ${e.toString()}')),
        );
      }
    }
  }

  void _replyToComment(String commentId) {
    // Implement reply functionality
  }

  void _sharePost() {
    // Implement share functionality
  }

  void _savePost() {
    // Implement save functionality
  }

  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is String) {
      dateTime = DateTime.parse(timestamp);
    } else {
      return '';
    }

    final difference = DateTime.now().difference(dateTime);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }
}