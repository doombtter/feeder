import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../core/constants/app_constants.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../services/s3_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();
  final _userService = UserService();
  final _authService = AuthService();

  int? _selectedBirthYear;
  String? _selectedGender;
  String? _selectedRegion;
  File? _profileImage;
  bool _isLoading = false;

  late final List<int> _birthYears;
  
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
    final currentYear = DateTime.now().year;
    _birthYears = List.generate(
      currentYear - 1944 - 13,
      (index) => currentYear - 14 - index,
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
      });
    }
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
    if (_selectedBirthYear == null) {
      _showError('출생년도를 선택해주세요');
      return;
    }
    if (_selectedGender == null) {
      _showError('성별을 선택해주세요');
      return;
    }
    if (_selectedRegion == null) {
      _showError('지역을 선택해주세요');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = _authService.currentUser!.uid;
      String? profileImageUrl;

      if (_profileImage != null) {
        profileImageUrl = await S3Service.uploadProfileImage(
          _profileImage!,
          userId: uid,
        );
      }

      await _userService.updateProfile(
        uid: uid,
        nickname: nickname,
        bio: bio,
        birthYear: _selectedBirthYear!,
        gender: _selectedGender!,
        region: _selectedRegion!,
        profileImageUrl: profileImageUrl,
      );

      await _userService.setOnlineStatus(uid, true);

      // ProfileCheckWrapper의 StreamBuilder가 자동으로 감지하므로
      // 별도의 네비게이션 필요 없음
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필이 저장되었습니다')),
        );
      }
    } catch (e) {
      _showError('프로필 저장 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // 뒤로가기 시 로그아웃 확인
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('로그아웃', style: TextStyle(color: AppColors.textPrimary)),
            content: const Text('프로필 설정을 취소하고 로그아웃하시겠습니까?', style: TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소', style: TextStyle(color: AppColors.textTertiary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('로그아웃', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _authService.signOut();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('프로필 설정'),
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 프로필 이미지
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.card,
                        border: Border.all(color: AppColors.border, width: 2),
                        image: _profileImage != null
                            ? DecorationImage(
                                image: FileImage(_profileImage!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _profileImage == null
                          ? const Icon(
                              Icons.person_rounded,
                              size: 60,
                              color: AppColors.textTertiary,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.background, width: 3),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '프로필 사진 (선택)',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 32),

            // 닉네임
            _buildSectionTitle('닉네임', required: true),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _nicknameController,
              hintText: '2~10자 사이로 입력',
              maxLength: 10,
            ),
            const SizedBox(height: 24),

            // 자기소개
            _buildSectionTitle('자기소개'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _bioController,
              hintText: '간단한 자기소개 (선택)',
              maxLines: 3,
              maxLength: 100,
            ),
            const SizedBox(height: 24),

            // 출생년도
            _buildSectionTitle('출생년도', required: true),
            const SizedBox(height: 8),
            _buildDropdown<int>(
              value: _selectedBirthYear,
              hint: '출생년도 선택',
              items: _birthYears.map((year) {
                return DropdownMenuItem(
                  value: year,
                  child: Text('$year년'),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedBirthYear = value),
            ),
            const SizedBox(height: 24),

            // 성별
            _buildSectionTitle('성별', required: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildGenderButton(
                    label: '남성',
                    value: 'male',
                    icon: Icons.male_rounded,
                    color: AppColors.male,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildGenderButton(
                    label: '여성',
                    value: 'female',
                    icon: Icons.female_rounded,
                    color: AppColors.female,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 지역
            _buildSectionTitle('지역', required: true),
            const SizedBox(height: 8),
            _buildDropdown<String>(
              value: _selectedRegion,
              hint: '지역 선택',
              items: _regions.map((region) {
                return DropdownMenuItem(
                  value: region,
                  child: Text(region),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedRegion = value),
            ),
            const SizedBox(height: 40),

            // 저장 버튼
            SizedBox(
              width: double.infinity,
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha:0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          '시작하기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildSectionTitle(String title, {bool required = false}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
          ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
    int maxLength = 100,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.textHint),
        counterStyle: TextStyle(color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.card,
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
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: TextStyle(color: AppColors.textHint)),
          isExpanded: true,
          dropdownColor: AppColors.card,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textTertiary),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildGenderButton({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedGender == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedGender = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha:0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : AppColors.textTertiary,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
