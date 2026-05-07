import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_setting.dart';
import '../services/google_calendar_service.dart';

final calendarServiceProvider = Provider((ref) => GoogleCalendarService());

final leaveStateProvider = StateNotifierProvider<LeaveNotifier, UserSetting?>((ref) {
  return LeaveNotifier();
});

final holidayListProvider = AsyncNotifierProvider<HolidayListNotifier, List<Map<String, dynamic>>>(() {
  return HolidayListNotifier();
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

  double calculateByEntryDate(DateTime entryDate) {
    final now = DateTime.now();

    // 1. 전체 근속 개월 수 계산
    int totalMonths = (now.year - entryDate.year) * 12 + now.month - entryDate.month;

    // 아직 해당 월의 입사일이 지나지 않았으면 한 달을 다 채운 게 아님
    if (now.day < entryDate.day) {
      totalMonths--;
    }

    // 2. 1년 미만인지 확인 (근속 12개월 미만)
    if (totalMonths < 12) {
      // 1개월 개근 시 1개씩 발생 (최대 11개)
      return totalMonths.clamp(0, 11).toDouble();
    } else {
      // 3. 1년 이상자 로직 (기존 로직 유지)
      int years = (totalMonths ~/ 12);
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

class HolidayListNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    // build는 처음 이 프로바이더가 호출될 때 실행됩니다.
    return _fetchCalendarData();
  }

  // ★ 중요: 이 함수가 반드시 클래스 중괄호 { } 안에 있어야 ref를 사용할 수 있습니다.
  Future<List<Map<String, dynamic>>> _fetchCalendarData() async {
    final service = ref.read(calendarServiceProvider);
    final settings = ref.read(leaveStateProvider);

    if (settings == null) return [];

    var account = await service.signInSilently() ?? await service.signIn();
    if (account == null) return [];

    final result = await service.calculateUsedLeave(account, settings.resetDate, entryDate: settings.entryDate);
    final List<Map<String, dynamic>> allEvents = List.from(result.events);

    final List<Map<String, dynamic>> filteredEvents = allEvents.where((event) {
      final DateTime eventDate = (event['date'] is DateTime
          ? event['date']
          : DateTime.parse(event['date'].toString())).toLocal();
      final DateTime eventDateOnly = DateTime(eventDate.year, eventDate.month, eventDate.day);

      final now = DateTime.now();
      final r = settings.resetDate.toLocal();

      // 1. 이번 주기의 시작일(periodStart) 계산
      DateTime periodStart = DateTime(now.year, r.month, r.day);
      if (periodStart.isAfter(now)) {
        periodStart = DateTime(now.year - 1, r.month, r.day);
      }

      // 2. 이번 주기의 종료일(periodEnd) 계산
      final DateTime periodEnd = DateTime(periodStart.year + 1, r.month, r.day).subtract(const Duration(days: 1));

      // ✅ 시작일보다 같거나 크고, 종료일보다 같거나 작을 때만 포함
      return !eventDateOnly.isBefore(periodStart) && !eventDateOnly.isAfter(periodEnd);
    }).toList();

    // 3. 필터링된 리스트 정렬 (오늘 기준 과거/미래)
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);

    filteredEvents.sort((a, b) {
      final dateA = a['date'] is DateTime ? a['date'] : DateTime.parse(a['date'].toString());
      final dateB = b['date'] is DateTime ? b['date'] : DateTime.parse(b['date'].toString());

      final dayA = DateTime(dateA.year, dateA.month, dateA.day);
      final dayB = DateTime(dateB.year, dateB.month, dateB.day);

      bool isPastA = dayA.isBefore(todayStart);
      bool isPastB = dayB.isBefore(todayStart);

      if (isPastA != isPastB) return isPastA ? 1 : -1;
      return isPastA ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
    });

    return filteredEvents;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _fetchCalendarData());
  }
}