import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import '../../core/constants/app_constants.dart';
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
    '서울특별시', '부산광역시', '대구광역시', '인천광역시', '광주광역시',
    '대전광역시', '울산광역시', '세종특별자치시', '경기도', '강원도',
    '충청북도', '충청남도', '전라북도', '전라남도', '경상북도',
    '경상남도', '제주특별자치도',
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
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '프로필 이미지 편집',
            toolbarColor: AppColors.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: '프로필 이미지 편집',
            aspectRatioLockEnabled: true,
            aspectRatioPresets: [CropAspectRatioPreset.square],
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

    _nicknameChanged = nickname != widget.user.nickname;
    if (_nicknameChanged && !widget.user.canChangeNickname) {
      _showError('닉네임은 30일에 한 번만 변경 가능합니다.\n${widget.user.daysUntilNicknameChange}일 후에 변경 가능해요.');
      return;
    }

    setState(() => _isLoading = true);

    try {
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('프로필 수정'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.arrow_back_ios_rounded, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : GestureDetector(
                    onTap: _saveProfile,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 프로필 이미지
            _buildSectionTitle('프로필 이미지', subtitle: '최대 3장까지 등록 가능'),
            const SizedBox(height: 12),
            SizedBox(
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (int i = 0; i < _existingImageUrls.length; i++)
                    _buildImageItem(
                      imageUrl: _existingImageUrls[i],
                      onRemove: () => _removeExistingImage(i),
                    ),
                  for (int i = 0; i < _newImages.length; i++)
                    _buildImageItem(
                      file: _newImages[i],
                      onRemove: () => _removeNewImage(i),
                    ),
                  if (_totalImageCount < 3) _buildAddImageButton(),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // 닉네임
            Row(
              children: [
                _buildSectionTitle('닉네임'),
                if (!widget.user.canChangeNickname) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.user.daysUntilNicknameChange}일 후 변경 가능',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _nicknameController,
              hintText: '2~10자 입력',
              maxLength: 10,
              enabled: widget.user.canChangeNickname,
            ),
            const SizedBox(height: 24),

            // 자기소개
            _buildSectionTitle('자기소개'),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _bioController,
              hintText: '간단한 자기소개를 입력해주세요',
              maxLength: 100,
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // 출생년도 (수정 불가)
            _buildSectionTitle('출생년도'),
            const SizedBox(height: 10),
            _buildLockedField(
              value: '${widget.user.birthYear}년 (만 ${widget.user.age}세)',
            ),
            const SizedBox(height: 24),

            // 성별 (수정 불가)
            _buildSectionTitle('성별'),
            const SizedBox(height: 10),
            _buildLockedField(
              value: widget.user.gender == 'male' ? '남자' : '여자',
            ),
            const SizedBox(height: 24),

            // 지역
            _buildSectionTitle('지역'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonFormField<String>(
                value: _selectedRegion,
                dropdownColor: AppColors.card,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
                items: _regions.map((region) {
                  return DropdownMenuItem(value: region, child: Text(region));
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedRegion = value);
                },
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLength = 100,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      enabled: enabled,
      style: TextStyle(
        color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: AppColors.textHint),
        counterStyle: const TextStyle(color: AppColors.textTertiary),
        filled: true,
        fillColor: enabled ? AppColors.card : AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border.withValues(alpha:0.5)),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildLockedField({required String value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textTertiary,
            ),
          ),
          const Spacer(),
          const Icon(Icons.lock_rounded, size: 16, color: AppColors.textTertiary),
        ],
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
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
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
          right: 14,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddImageButton() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: AppColors.textTertiary, size: 24),
            const SizedBox(height: 4),
            Text(
              '$_totalImageCount/3',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
