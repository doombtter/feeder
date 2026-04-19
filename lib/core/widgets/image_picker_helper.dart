import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_constants.dart';

/// 이미지 크롭 프리셋 (용도별)
enum ImageCropPreset {
  /// 프로필 이미지: 1:1 정사각형 고정
  profile,

  /// Shot(세로 영상 썸네일 스타일): 9:16 세로 고정
  shot,

  /// 피드 글 첨부: 비율 자유 (사용자 선택)
  post,

  /// 채팅 이미지: 비율 자유 (사용자 선택)
  chat,
}

/// 이미지 선택 + 크롭을 한 번에 처리하는 공통 유틸
///
/// 사용 예:
/// ```dart
/// final file = await ImagePickerHelper.pickAndCrop(
///   context,
///   preset: ImageCropPreset.profile,
/// );
/// if (file != null) setState(() => _image = file);
/// ```
class ImagePickerHelper {
  ImagePickerHelper._();

  /// 갤러리에서 이미지 선택 → 크롭 → File 반환.
  /// 사용자가 취소하면 null.
  static Future<File?> pickAndCrop(
    BuildContext context, {
    required ImageCropPreset preset,
    ImageSource source = ImageSource.gallery,
  }) async {
    final config = _configFor(preset);

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: config.pickMaxDimension.toDouble(),
      maxHeight: config.pickMaxDimension.toDouble(),
      imageQuality: config.pickQuality,
    );

    if (pickedFile == null) return null;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      compressQuality: config.cropQuality,
      aspectRatio: config.lockedRatio,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: config.toolbarTitle,
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          statusBarColor: AppColors.primary,
          backgroundColor: AppColors.background,
          activeControlsWidgetColor: AppColors.primary,
          // 크롭 프레임 및 격자 스타일
          dimmedLayerColor: Colors.black.withValues(alpha: 0.6),
          cropFrameColor: AppColors.primary,
          cropGridColor: Colors.white.withValues(alpha: 0.4),
          cropFrameStrokeWidth: 3,
          cropGridStrokeWidth: 1,
          showCropGrid: true,
          // 비율 설정
          initAspectRatio: config.initialRatioPreset,
          lockAspectRatio: config.lockAspectRatio,
          aspectRatioPresets: config.ratioPresets,
          hideBottomControls: config.hideBottomControls,
        ),
        IOSUiSettings(
          title: config.toolbarTitle,
          doneButtonTitle: '완료',
          cancelButtonTitle: '취소',
          aspectRatioLockEnabled: config.lockAspectRatio,
          aspectRatioPresets: config.ratioPresets,
          resetAspectRatioEnabled: !config.lockAspectRatio,
          aspectRatioPickerButtonHidden: config.lockAspectRatio,
          rotateButtonsHidden: false,
          resetButtonHidden: false,
        ),
      ],
    );

    if (croppedFile == null) return null;
    return File(croppedFile.path);
  }

  /// 여러 장을 순서대로 픽 + 크롭 (각 장마다 크롭 UI 표시)
  /// [maxCount]를 넘으면 즉시 종료. 사용자가 중간에 취소하면 그 시점까지 수집된 것만 반환.
  static Future<List<File>> pickAndCropMultiple(
    BuildContext context, {
    required ImageCropPreset preset,
    required int maxCount,
    int currentCount = 0,
  }) async {
    final result = <File>[];
    for (var i = 0; i < (maxCount - currentCount); i++) {
      if (!context.mounted) break;
      final file = await pickAndCrop(context, preset: preset);
      if (file == null) break; // 사용자 취소
      result.add(file);
    }
    return result;
  }

  static _CropConfig _configFor(ImageCropPreset preset) {
    switch (preset) {
      case ImageCropPreset.profile:
        return const _CropConfig(
          toolbarTitle: '프로필 이미지 편집',
          pickMaxDimension: 1024,
          pickQuality: 85,
          cropQuality: 80,
          lockAspectRatio: true,
          initialRatioPreset: CropAspectRatioPreset.square,
          ratioPresets: [CropAspectRatioPreset.square],
          lockedRatio: CropAspectRatio(ratioX: 1, ratioY: 1),
          hideBottomControls: true,
        );

      case ImageCropPreset.shot:
        return const _CropConfig(
          toolbarTitle: 'Shot 이미지 편집',
          pickMaxDimension: 1440,
          pickQuality: 85,
          cropQuality: 80,
          lockAspectRatio: true,
          // lockedRatio로 9:16이 강제되므로 initialRatioPreset/ratioPresets는
          // 실제 비율에 영향을 주지 않음. 다만 UCrop이 빈 ratioPresets 리스트면
          // IllegalArgumentException을 던지므로 최소 1개는 전달해야 함.
          // hideBottomControls: true라 UI에는 노출되지 않음.
          initialRatioPreset: CropAspectRatioPreset.original,
          ratioPresets: [CropAspectRatioPreset.original],
          lockedRatio: CropAspectRatio(ratioX: 9, ratioY: 16),
          hideBottomControls: true,
        );

      case ImageCropPreset.post:
        return const _CropConfig(
          toolbarTitle: '이미지 편집',
          pickMaxDimension: 1024,
          pickQuality: 75,
          cropQuality: 70,
          lockAspectRatio: false,
          initialRatioPreset: CropAspectRatioPreset.original,
          ratioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
          lockedRatio: null,
          hideBottomControls: false,
        );

      case ImageCropPreset.chat:
        return const _CropConfig(
          toolbarTitle: '이미지 편집',
          pickMaxDimension: 1024,
          pickQuality: 75,
          cropQuality: 70,
          lockAspectRatio: false,
          initialRatioPreset: CropAspectRatioPreset.original,
          ratioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
          lockedRatio: null,
          hideBottomControls: false,
        );
    }
  }
}

class _CropConfig {
  final String toolbarTitle;
  final int pickMaxDimension;
  final int pickQuality;
  final int cropQuality;
  final bool lockAspectRatio;
  final CropAspectRatioPreset initialRatioPreset;
  final List<CropAspectRatioPreset> ratioPresets;
  final CropAspectRatio? lockedRatio;
  final bool hideBottomControls;

  const _CropConfig({
    required this.toolbarTitle,
    required this.pickMaxDimension,
    required this.pickQuality,
    required this.cropQuality,
    required this.lockAspectRatio,
    required this.initialRatioPreset,
    required this.ratioPresets,
    required this.lockedRatio,
    required this.hideBottomControls,
  });
}
