import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../services/s3_service.dart';

class ProfileEditScreen extends StatefulWidget {
  final UserModel user;

  const ProfileEditScreen({super.key, required this.user});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();
  final _userService = UserService();

  String? _selectedRegion;
  List<File> _newImages = [];
  List<String> _existingImageUrls = [];
  bool _isLoading = false;
  bool _nicknameChanged = false;

  final List<String> _regions = [
    '서울특별시',
    '부산광역시',
    '대구광역시',
    '인천광역시',
    '광주광역시',
    '대전광역시',
    '울산광역시',
    '세종특별자치시',
    '경기도',
    '강원도',
    '충청북도',
    '충청남도',
    '전라북도',
    '전라남도',
    '경상북도',
    '경상남도',
    '제주특별자치도',
  ];

  @override
  void initState() {
    super.initState();
    _nicknameController.text = widget.user.nickname;
    _bioController.text = widget.user.bio;
    _selectedRegion = widget.user.region;
    _existingImageUrls = List.from(widget.user.profileImageUrls);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  int get _totalImageCount => _existingImageUrls.length + _newImages.length;

  Future<void> _pickImage() async {
    if (_totalImageCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필 이미지는 최대 3개까지 등록 가능합니다')),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      // 이미지 크롭
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '프로필 이미지 편집',
            toolbarColor: const Color(0xFF6C63FF),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
            ],
          ),
          IOSUiSettings(
            title: '프로필 이미지 편집',
            aspectRatioLockEnabled: true,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
            ],
          ),
        ],
      );

      if (croppedFile != null) {
        setState(() {
          _newImages.add(File(croppedFile.path));
        });
      }
    }
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
    });
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  Future<void> _saveProfile() async {
    final nickname = _nicknameController.text.trim();
    final bio = _bioController.text.trim();

    if (nickname.isEmpty) {
      _showError('닉네임을 입력해주세요');
      return;
    }
    if (nickname.length < 2 || nickname.length > 10) {
      _showError('닉네임은 2~10자로 입력해주세요');
      return;
    }
    if (_selectedRegion == null) {
      _showError('지역을 선택해주세요');
      return;
    }

    // 닉네임 변경 체크
    _nicknameChanged = nickname != widget.user.nickname;
    if (_nicknameChanged && !widget.user.canChangeNickname) {
      _showError('닉네임은 30일에 한 번만 변경 가능합니다.\n${widget.user.daysUntilNicknameChange}일 후에 변경 가능해요.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 새 이미지 S3 업로드
      List<String> allImageUrls = List.from(_existingImageUrls);
      for (final file in _newImages) {
        final url = await S3Service.uploadProfileImage(
          file,
          userId: widget.user.uid,
        );
        if (url != null) {
          allImageUrls.add(url);
        }
      }

      await _userService.updateProfileWithImages(
        uid: widget.user.uid,
        nickname: nickname,
        bio: bio,
        birthYear: widget.user.birthYear,
        gender: widget.user.gender,
        region: _selectedRegion!,
        profileImageUrls: allImageUrls,
        nicknameChanged: _nicknameChanged,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필이 수정되었습니다')),
        );
      }
    } catch (e) {
      _showError('프로필 수정 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('프로필 수정'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF6C63FF),
                    ),
                  )
                : GestureDetector(
                    onTap: _saveProfile,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '저장',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 프로필 이미지들 (최대 3개)
            const Text(
              '프로필 이미지',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '최대 3장까지 등록 가능합니다',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // 기존 이미지
                  for (int i = 0; i < _existingImageUrls.length; i++)
                    _buildImageItem(
                      imageUrl: _existingImageUrls[i],
                      onRemove: () => _removeExistingImage(i),
                    ),
                  // 새 이미지
                  for (int i = 0; i < _newImages.length; i++)
                    _buildImageItem(
                      file: _newImages[i],
                      onRemove: () => _removeNewImage(i),
                    ),
                  // 추가 버튼
                  if (_totalImageCount < 3)
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate,
                                color: Colors.grey[500]),
                            const SizedBox(height: 4),
                            Text(
                              '$_totalImageCount/3',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 닉네임
            Row(
              children: [
                const Text(
                  '닉네임',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                if (!widget.user.canChangeNickname) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.user.daysUntilNicknameChange}일 후 변경 가능',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nicknameController,
              maxLength: 10,
              enabled: widget.user.canChangeNickname,
              decoration: InputDecoration(
                hintText: '2~10자 입력',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF6C63FF),
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: widget.user.canChangeNickname ? Colors.white : Colors.grey[100],
              ),
            ),
            const SizedBox(height: 16),

            // 자기소개
            const Text(
              '자기소개',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bioController,
              maxLength: 100,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '간단한 자기소개를 입력해주세요',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF6C63FF),
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 출생년도 (수정 불가)
            const Text(
              '출생년도',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Text(
                    '${widget.user.birthYear}년 (만 ${widget.user.age}세)',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  Icon(Icons.lock, size: 18, color: Colors.grey[400]),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 성별 (수정 불가)
            const Text(
              '성별',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Text(
                    widget.user.gender == 'male' ? '남자' : '여자',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  Icon(Icons.lock, size: 18, color: Colors.grey[400]),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 지역
            const Text(
              '지역',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedRegion,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF6C63FF),
                    width: 2,
                  ),
                ),
              ),
              items: _regions.map((region) {
                return DropdownMenuItem(value: region, child: Text(region));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedRegion = value;
                });
              },
            ),
            // 하단 여백 추가
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildImageItem({
    String? imageUrl,
    File? file,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(
              image: file != null
                  ? FileImage(file) as ImageProvider
                  : NetworkImage(imageUrl!),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 12,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
