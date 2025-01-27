// screens/forum_screen.dart
import 'package:awaaz/screens/post_detail_screen.dart';
import 'package:awaaz/widgets/create_post_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/post.dart';

class ForumScreen extends StatefulWidget {
  const ForumScreen({super.key});

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  String _currentTab = 'All';
  final List<String> _tabs = ['All', 'Discussion', 'Emergency', 'News'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Text(
              'SafetyCommunity',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Online',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [

          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _currentTab == 'All'
                  ? FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('createdAt', descending: true)
                  .snapshots()
                  : FirebaseFirestore.instance
                  .collection('posts')
                  .where('tags', arrayContains: _currentTab)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Something went wrong'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final post = snapshot.data!.docs[index];
                    return _buildPostCard(post);
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Communities',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Create',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'Inbox',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreatePost(),
        backgroundColor: Colors.purple,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 40,
      color: Colors.black,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          final isSelected = tab == _currentTab;
          return GestureDetector(
            onTap: () => setState(() => _currentTab = tab),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white12 : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  tab,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostCard(DocumentSnapshot post) {
    final data = post.data() as Map<String, dynamic>;
    final postId = post.id;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(
              post: Post(
                id: post.id,
                title: data['title'] ?? '',
                content: data['content'] ?? '',
                authorId: data['authorId'] ?? '',
                authorName: data['authorName'] ?? 'Anonymous',
                authorAvatar: data['authorAvatar'] ?? '',
                votes: data['votes'] ?? 0,
                commentCount: data['commentCount'] ?? 0,
                createdAt: data['createdAt'] != null
                    ? (data['createdAt'] as Timestamp).toDate()
                    : DateTime.now(),
                tags: List<String>.from(data['tags'] ?? []),
              ),
            ),
          ),
        );
      },
      child: Card(
        color: Colors.grey[900],
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundImage: NetworkImage(data['authorAvatar'] ?? ''),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'u/${data['authorName']}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const Text(' • ', style: TextStyle(color: Colors.grey)),
                  Text(
                    _getTimeAgo(data['createdAt']),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                data['title'],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data['content'],
                style: const TextStyle(color: Colors.white70),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildVoteButton(true, postId, data['votes'] ?? 0),  // Use postId here
                  const SizedBox(width: 4),
                  Text(
                    '${data['votes'] ?? 0}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  _buildVoteButton(false, postId, data['votes'] ?? 0),
                  Icon(Icons.mode_comment_outlined, color: Colors.grey[400], size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${data['commentCount'] ?? 0}',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  const Spacer(),
                  Icon(Icons.share, color: Colors.grey[400], size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoteButton(bool isUpvote, String postId, int votes) {
    return FutureBuilder<int?>(
      future: getUserVote(postId),
      builder: (context, snapshot) {
        final userVote = snapshot.data;
        final bool isSelected = (userVote == 1 && isUpvote) ||
            (userVote == -1 && !isUpvote);

        return InkWell(
          onTap: () => _handleVote(postId, isUpvote ? 1 : -1),
          child: Icon(
            isUpvote ? Icons.arrow_upward : Icons.arrow_downward,
            color: isSelected ? Colors.purple : Colors.grey[400],
            size: 20,
          ),
        );
      },
    );
  }

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '';

    // Handle the case when timestamp is a String
    DateTime date;
    if (timestamp is String) {
      date = DateTime.parse(timestamp);
    } else if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else {
      return '';
    }

    final difference = DateTime.now().difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  Future<void> _handleVote(String postId, int value) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to vote')),
        );
        return;
      }

      // Reference to the post document
      final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);

      // Check if the post exists first
      final postDoc = await postRef.get();
      if (!postDoc.exists) {
        throw Exception('Post not found');
      }

      // Reference to the user's vote document
      final userVoteRef = FirebaseFirestore.instance
          .collection('user_votes')
          .doc('${user.uid}_$postId');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final userVoteDoc = await transaction.get(userVoteRef);

        if (userVoteDoc.exists) {
          final previousVote = userVoteDoc.data()?['value'] ?? 0;
          if (previousVote == value) {
            // User is un-voting
            await userVoteRef.delete();
            await postRef.update({
              'votes': FieldValue.increment(-previousVote),
            });
          } else {
            // User is changing their vote
            await userVoteRef.update({'value': value});
            await postRef.update({
              'votes': FieldValue.increment(-previousVote + value),
            });
          }
        } else {
          // New vote
          await userVoteRef.set({
            'userId': user.uid,
            'postId': postId,
            'value': value,
            'timestamp': FieldValue.serverTimestamp(),
          });
          await postRef.update({
            'votes': FieldValue.increment(value),
          });
        }
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }
  Future<int?> getUserVote(String postId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final userVoteDoc = await FirebaseFirestore.instance
        .collection('user_votes')
        .doc('${user.uid}_$postId')
        .get();

    if (userVoteDoc.exists == true) {
      return userVoteDoc.data()?['value'] as int?;
    }
    return null;
  }
  void _showCreatePost() {
    showDialog(
      context: context,
      builder: (context) => const CreatePostSheet(),
    );
  }
}