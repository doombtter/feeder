import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';
import '../models/comment_model.dart';
import 'notification_service.dart';

class PostService {
  // 싱글톤 패턴
  static final PostService _instance = PostService._internal();
  factory PostService() => _instance;
  PostService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // 단일 게시글 조회
  Future<PostModel?> getPost(String postId) async {
    final doc = await _firestore.collection('posts').doc(postId).get();
    if (!doc.exists) return null;
    final post = PostModel.fromFirestore(doc);
    if (post.isDeleted) return null;
    return post;
  }

  // 게시글 목록 스트림 (최신순)
  Stream<List<PostModel>> getPostsStream({int limit = 20}) {
    return _firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .where((post) => !post.isDeleted)
          .toList();
    });
  }

  // 게시글 페이징 조회
  Future<List<PostModel>> getPosts({
    int limit = 20,
    DocumentSnapshot? lastDoc,
  }) async {
    Query query = _firestore
        .collection('posts')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList();
  }

  // 게시글 문서 가져오기 (페이지네이션용)
  Future<QuerySnapshot> getPostsSnapshot({
    int limit = 20,
    DocumentSnapshot? lastDoc,
  }) async {
    Query query = _firestore
        .collection('posts')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    return await query.get();
  }

  // 내가 쓴 글
  Stream<List<PostModel>> getMyPostsStream(String userId) {
    return _firestore
        .collection('posts')
        .where('authorId', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList();
    });
  }

  // 와드한 글
  Future<List<PostModel>> getWardedPosts(String userId) async {
    // userId 필드로 필터링
    final wardsSnapshot = await _firestore
        .collectionGroup('wards')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();

    final postIds = <String>[];
    for (final doc in wardsSnapshot.docs) {
      // posts/{postId}/wards/{visitorId} 경로에서 postId 추출
      final pathSegments = doc.reference.path.split('/');
      if (pathSegments.length >= 2) {
        postIds.add(pathSegments[1]);
      }
    }

    if (postIds.isEmpty) return [];

    // 배치로 게시글 가져오기 (whereIn은 최대 30개 제한)
    final posts = <PostModel>[];
    final chunks = <List<String>>[];
    
    for (var i = 0; i < postIds.length; i += 30) {
      chunks.add(postIds.sublist(i, i + 30 > postIds.length ? postIds.length : i + 30));
    }

    for (final chunk in chunks) {
      final snapshot = await _firestore
          .collection('posts')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      
      for (final doc in snapshot.docs) {
        final post = PostModel.fromFirestore(doc);
        if (!post.isDeleted) {
          posts.add(post);
        }
      }
    }

    // postIds 순서대로 정렬 (와드한 순서 = 최신순)
    final postIdOrder = {for (var i = 0; i < postIds.length; i++) postIds[i]: i};
    posts.sort((a, b) => (postIdOrder[a.id] ?? 0).compareTo(postIdOrder[b.id] ?? 0));
    
    return posts;
  }

  // 게시글 작성
  Future<String> createPost({
    required String authorId,
    required String authorGender,
    required String content,
    String? imageUrl,
    String? voiceUrl,
    int? voiceDuration,
  }) async {
    final docRef = await _firestore.collection('posts').add({
      'authorId': authorId,
      'authorGender': authorGender,
      'content': content,
      'imageUrl': imageUrl,
      'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration,
      'createdAt': FieldValue.serverTimestamp(),
      'wardCount': 0,
      'commentCount': 0,
      'isDeleted': false,
    });
    return docRef.id;
  }

  // 게시글 삭제 (소프트 삭제)
  Future<void> deletePost(String postId) async {
    await _firestore.collection('posts').doc(postId).update({
      'isDeleted': true,
    });
  }

  // 와드 토글
  Future<bool> toggleWard(String postId, String userId) async {
    final wardRef = _firestore
        .collection('posts')
        .doc(postId)
        .collection('wards')
        .doc(userId);

    final wardDoc = await wardRef.get();

    if (wardDoc.exists) {
      // 와드 취소
      await wardRef.delete();
      await _firestore.collection('posts').doc(postId).update({
        'wardCount': FieldValue.increment(-1),
      });
      return false;
    } else {
      // 와드
      await wardRef.set({
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection('posts').doc(postId).update({
        'wardCount': FieldValue.increment(1),
      });
      return true;
    }
  }

  // 와드 여부 확인
  Future<bool> isWarded(String postId, String userId) async {
    final wardDoc = await _firestore
        .collection('posts')
        .doc(postId)
        .collection('wards')
        .doc(userId)
        .get();
    return wardDoc.exists;
  }

  // 와드 여부 스트림
  Stream<bool> isWardedStream(String postId, String userId) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('wards')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  // 댓글 목록 스트림 (댓글 + 대댓글 정렬)
  Stream<List<CommentModel>> getCommentsStream(String postId) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      final allComments = snapshot.docs
          .map((doc) => CommentModel.fromFirestore(doc, postId))
          .toList();

      final List<CommentModel> sortedComments = [];
      final parentComments = allComments.where((c) => c.parentId == null).toList();
      
      for (final parent in parentComments) {
        sortedComments.add(parent);
        final replies = allComments
            .where((c) => c.parentId == parent.id)
            .toList();
        sortedComments.addAll(replies);
      }
      
      return sortedComments;
    });
  }

  // 댓글 작성
  Future<void> createComment({
    required String postId,
    required String authorId,
    required String authorGender,
    required String content,
    String? parentId,
    String? voiceUrl,
    int? voiceDuration,
  }) async {
    final batch = _firestore.batch();

    final commentRef = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc();

    batch.set(commentRef, {
      'authorId': authorId,
      'authorGender': authorGender,
      'content': content,
      'parentId': parentId,
      'depth': parentId == null ? 0 : 1,
      'createdAt': FieldValue.serverTimestamp(),
      'wardCount': 0,
      'replyCount': 0,
      'isDeleted': false,
      'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration,
    });

    final postRef = _firestore.collection('posts').doc(postId);
    batch.update(postRef, {
      'commentCount': FieldValue.increment(1),
    });

    if (parentId != null) {
      final parentRef = _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(parentId);
      batch.update(parentRef, {
        'replyCount': FieldValue.increment(1),
      });
    }

    await batch.commit();

    // 알림 전송
    final previewText = voiceUrl != null ? '🎤 음성 댓글' : content;
    
    if (parentId != null) {
      // 답글인 경우: 부모 댓글 작성자에게 알림
      final parentComment = await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(parentId)
          .get();
      
      if (parentComment.exists) {
        final parentAuthorId = parentComment.data()?['authorId'];
        if (parentAuthorId != null && parentAuthorId != authorId) {
          await _notificationService.sendReplyNotification(
            toUserId: parentAuthorId,
            postId: postId,
            replierId: authorId,
            replierGender: authorGender,
            replyPreview: previewText,
          );
        }
      }
    } else {
      // 댓글인 경우: 게시글 작성자에게 알림
      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (postDoc.exists) {
        final postAuthorId = postDoc.data()?['authorId'];
        if (postAuthorId != null && postAuthorId != authorId) {
          await _notificationService.sendCommentNotification(
            toUserId: postAuthorId,
            postId: postId,
            commenterId: authorId,
            commenterGender: authorGender,
            commentPreview: previewText,
          );
        }
      }
    }
  }

  // 댓글 삭제
  Future<void> deleteComment(String postId, String commentId, {String? parentId}) async {
    final batch = _firestore.batch();

    final commentRef = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);

    batch.update(commentRef, {'isDeleted': true});

    final postRef = _firestore.collection('posts').doc(postId);
    batch.update(postRef, {
      'commentCount': FieldValue.increment(-1),
    });

    if (parentId != null) {
      final parentRef = _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(parentId);
      batch.update(parentRef, {
        'replyCount': FieldValue.increment(-1),
      });
    }

    await batch.commit();
  }
}
