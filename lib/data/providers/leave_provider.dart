import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_setting.dart';
import '../services/google_calendar_service.dart';

final calendarServiceProvider = Provider((ref) => GoogleCalendarService());

final leaveStateProvider = StateNotifierProvider<LeaveNotifier, UserSetting?>((ref) {
  return LeaveNotifier();
});

class LeaveNotifier extends StateNotifier<UserSetting?> {
  LeaveNotifier() : super(null) {
    _init();
  }

  void _init() {
    final box = Hive.box<UserSetting>('settings');
    if (box.isNotEmpty) {
      state = box.get(0);
    }
  }

  // 입사일 기준 법정 연차 계산 (근로기준법)
  double calculateByEntryDate(DateTime entryDate) {
    final now = DateTime.now();
    int years = now.year - entryDate.year;
    if (now.month < entryDate.month || (now.month == entryDate.month && now.day < entryDate.day)) {
      years--;
    }

    if (years < 1) {
      int months = (now.year - entryDate.year) * 12 + now.month - entryDate.month;
      if (now.day < entryDate.day) months--;
      return months.clamp(0, 11).toDouble();
    } else {
      int extra = (years - 1) ~/ 2;
      return (15.0 + extra).clamp(15.0, 25.0);
    }
  }

  // ★ entryDate 파라미터 추가
  Future<void> saveSettings(double total, DateTime reset, DateTime? entry) async {
    final box = Hive.box<UserSetting>('settings');
    final setting = UserSetting(
        totalLeave: total,
        resetDate: reset,
        entryDate: entry, // 입사일 저장
        isFirstRun: false
    );
    await box.put(0, setting);
    state = setting;
  }
}