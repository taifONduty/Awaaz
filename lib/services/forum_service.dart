//services/forum_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';

class ForumService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createPost(Post post) async {
    await _firestore.collection('posts').add(post.toJson());
  }

  Future<void> updatePost(String postId, Map<String, dynamic> data) async {
    await _firestore.collection('posts').doc(postId).update(data);
  }

  Future<void> deletePost(String postId) async {
    await _firestore.collection('posts').doc(postId).delete();
  }

  Future<void> votePost(String postId, int value) async {
    await _firestore.collection('posts').doc(postId).update({
      'votes': FieldValue.increment(value),
    });
  }
}