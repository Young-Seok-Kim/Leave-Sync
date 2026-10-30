import 'package:flutter/material.dart';

/// 캘린더 작성 규칙 안내 카드 (첫 실행 오버레이와 설정의 도움말에서 공용)
class GuideCard extends StatelessWidget {
  final VoidCallback onClose;
  final String buttonText;

  const GuideCard({super.key, required this.onClose, this.buttonText = "이해했습니다"});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 30),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_month, color: Color(0xFF764BA2), size: 48),
          const SizedBox(height: 16),
          const Text("💡 구글 캘린더 연동 안내", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            "본 앱은 구글 캘린더의 일정을 자동으로 읽어옵니다.\n아래 '연차 등록' 버튼으로 등록하거나,\n캘린더에 직접 아래 규칙으로 일정을 추가하세요.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black87, height: 1.5),
          ),
          const SizedBox(height: 24),
          _row("제목에 '연차' 포함 시", "1.0개 차감"),
          _row("제목에 '반차' 포함 시", "0.5개 차감"),
          _row("제목에 '반반차' 포함 시", "0.25개 차감"),
          const SizedBox(height: 8),
          const Text(
            "주말과 공휴일은 자동으로 제외됩니다.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF764BA2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(buttonText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String t, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t),
            Text(v, style: const TextStyle(color: Color(0xFF764BA2), fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

/// 설정 화면 등에서 안내를 다시 볼 때 사용
Future<void> showGuideDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: GuideCard(onClose: () => Navigator.pop(ctx), buttonText: "닫기"),
    ),
  );
}
