import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import '../../core/constants/app_constants.dart';
import '../../core/constants/country_codes.dart';
import '../../core/widgets/image_picker_helper.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../services/s3_service.dart';
import '../../models/user_model.dart';
import '../feed/home_screen.dart';

/// 프로필 저장 후 HomeScreen으로 이동하는 래퍼
class _ProfileCheckRedirect extends StatelessWidget {
  const _ProfileCheckRedirect();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const ProfileSetupScreen();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return const ProfileSetupScreen();
        }

        // isProfileComplete 체크
        final nickname = data['nickname'] ?? '';
        final birthYear = data['birthYear'] ?? 0;
        final gender = data['gender'] ?? '';
        final region = data['region'] ?? '';

        if (nickname.toString().isNotEmpty && 
            birthYear > 0 && 
            gender.toString().isNotEmpty && 
            region.toString().isNotEmpty) {
          return const HomeScreen();
        }

        return const ProfileSetupScreen();
      },
    );
  }
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();
  final _regionController = TextEditingController();
  final _userService = UserService();
  final _authService = AuthService();

  int? _selectedBirthYear;
  String? _selectedGender;
  String? _selectedRegion;
  File? _profileImage;
  bool _isLoading = false;

  /// 전화번호 국가 코드로 자동 판정된 국가명 (수정 불가)
  late final String _country;

  /// 해외 번호(+82가 아닌 번호)로 로그인했는지 여부
  /// true면 지역을 드롭다운 대신 직접 입력으로 받음
  late final bool _isOverseas;

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

    // 현재 로그인된 전화번호로 국가 자동 판정
    final phoneNumber = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    _isOverseas = !CountryCodes.isKorean(phoneNumber);
    _country = CountryCodes.fromPhoneNumber(phoneNumber);

    // 만 19세 이상만 선택 가능하도록 출생년도 리스트 생성
    // (출생년도만으로 계산: 올해 - 19 이하만 노출)
    final currentYear = DateTime.now().year;
    final maxBirthYear = currentYear - 19; // 만 19세가 되는 출생년도 상한
    const minBirthYear = 1945; // 하한 (기존 1945년과 동일)
    _birthYears = List.generate(
      maxBirthYear - minBirthYear + 1,
      (index) => maxBirthYear - index,
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePickerHelper.pickAndCrop(
      context,
      preset: ImageCropPreset.profile,
    );
    if (file != null && mounted) {
      setState(() => _profileImage = file);
    }
  }

  Future<void> _saveProfile() async {
    final nickname = _nicknameController.text.trim();
    final bio = _bioController.text.trim();

    // 해외: 직접 입력값, 국내: 드롭다운 선택값
    final region = _isOverseas
        ? _regionController.text.trim()
        : (_selectedRegion ?? '');

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
    if (region.isEmpty) {
      _showError(_isOverseas ? '지역을 입력해주세요' : '지역을 선택해주세요');
      return;
    }
    if (_isOverseas && region.length > 30) {
      _showError('지역은 30자 이내로 입력해주세요');
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
        country: _country,
        region: region,
        profileImageUrl: profileImageUrl,
      );

      await _userService.setOnlineStatus(uid, true);

      // StreamBuilder가 변경을 감지할 때까지 잠시 대기
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        // 명시적으로 AuthWrapper로 돌아가서 다시 체크하도록 함
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const _ProfileCheckRedirect()),
          (route) => false,
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

            // 국가 (전화번호 기준 자동 설정, 수정 불가)
            _buildSectionTitle('국가'),
            const SizedBox(height: 8),
            _buildLockedField(
              value: _country.isEmpty ? '알 수 없음' : _country,
              hint: '가입 시 전화번호를 기준으로 자동 설정됩니다',
            ),
            const SizedBox(height: 24),

            // 지역
            _buildSectionTitle('지역', required: true),
            const SizedBox(height: 8),
            if (_isOverseas)
              _buildTextField(
                controller: _regionController,
                hintText: '거주 중인 지역을 입력해주세요 (예: Tokyo)',
                maxLength: 30,
              )
            else
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

  Widget _buildLockedField({required String value, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              const Icon(Icons.lock_rounded, size: 16, color: AppColors.textTertiary),
            ],
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
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
