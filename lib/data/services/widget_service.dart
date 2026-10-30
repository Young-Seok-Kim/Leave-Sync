import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

/// 홈 화면 위젯에 잔여 연차 정보를 전달
class WidgetService {
  static const _androidProvider = 'LeaveWidgetProvider';

  static Future<void> update({
    required double total,
    required double remaining,
    required DateTime? resetDate,
  }) async {
    try {
      String fmt(double n) => n == n.toInt()
          ? n.toInt().toString()
          : n.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');

      String resetText = '';
      String ddayText = '';
      if (resetDate != null) {
        final r = resetDate.toLocal();
        resetText =
            "${r.year}.${r.month.toString().padLeft(2, '0')}.${r.day.toString().padLeft(2, '0')}";
        final now = DateTime.now();
        final diff = DateTime(r.year, r.month, r.day)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        ddayText = diff == 0 ? "오늘" : (diff > 0 ? "D-$diff" : "");
      }

      final progress = total > 0 ? ((remaining / total) * 100).clamp(0, 100).round() : 0;

      await HomeWidget.saveWidgetData<String>('remaining', fmt(remaining));
      await HomeWidget.saveWidgetData<String>('total', fmt(total));
      await HomeWidget.saveWidgetData<int>('progress', progress);
      await HomeWidget.saveWidgetData<String>('reset_date', resetText);
      await HomeWidget.saveWidgetData<String>('dday', ddayText);
      await HomeWidget.updateWidget(androidName: _androidProvider);
    } catch (e) {
      debugPrint("⚠️ 위젯 갱신 실패: $e");
    }
  }
}
