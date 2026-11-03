import 'package:flutter/material.dart';

/// 앱 전체 색상 조합 (네이비 계열).
/// 색을 바꾸고 싶으면 이 파일의 값만 수정하면 된다.
class AppPalette {
  const AppPalette._();

  /// 버튼, 아이콘, 강조 텍스트, 선택 표시
  static const Color brand = Color(0xFF2C5AA0);

  /// 상단 요약 카드 그라데이션 (시작 → 끝)
  static const Color gradientStart = Color(0xFF4A7BD0);
  static const Color gradientEnd = Color(0xFF1F3F7A);

  /// 포인트 색 (차감 개수, 뱃지, 계산 결과 등). 파랑과 대비되는 부드러운 주황
  static const Color accent = Color(0xFFD98B2B);

  /// 화면 배경
  static const Color background = Color(0xFFF4F6FA);

  /// 칩·아바타 배경용 아주 연한 메인색
  static const Color brandLight = Color(0xFFE3E9F4);

  /// 테두리용 연한 메인색
  static const Color brandLighter = Color(0xFFBBCAE3);

  /// 포인트색 연한 배경
  static const Color accentLight = Color(0xFFFAEFE0);

  static const LinearGradient brandGradient =
      LinearGradient(colors: [gradientStart, gradientEnd]);
}
