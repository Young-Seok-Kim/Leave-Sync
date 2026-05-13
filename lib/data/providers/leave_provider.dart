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

  static const int _currentSchemaVersion = 2;

  LeaveNotifier() : super(null) {
    _init();
  }

  void _init() {
    final box = Hive.box<UserSetting>('settings');
    if (box.isNotEmpty) {
      UserSetting savedData = box.get(0)!;

      if ((savedData.schemaVersion ?? 0) < _currentSchemaVersion) {
        savedData = _migrate(savedData, savedData.schemaVersion ?? 0);
        box.put(0, savedData); // 최신 버전으로 갱신 저장
      }

      state = savedData;
      Future.microtask(() => refreshTotalLeave());
    }
  }

  UserSetting _migrate(UserSetting oldData, int oldVersion) {
    UserSetting newData = oldData;

    if (oldVersion < 1) {
      final now = DateTime.now();
      final entry = oldData.entryDate;

      if (entry != null) {
        // 1. 이번 달의 연차 지급 예정일 (예: 2026년 5월 13일)
        final thisMonthPayDay = DateTime(now.year, now.month, entry.day);

        // 2. 오늘이 지급일보다 같거나 지났는지 확인
        bool isPayDayPassed = !now.isBefore(thisMonthPayDay);

        if (isPayDayPassed) {
          // [케이스 A] 오늘이 13일 이후인데, 아직 lastAutoUpdate가 없어서 연차를 못 받은 상태라면?
          // -> 지난달 날짜를 넣어주어 refreshTotalLeave가 "이번 달(5월) 꺼 줘야지!" 하게 만듭니다.
          newData = newData.copyWith(
            lastAutoUpdate: DateTime(now.year, now.month - 1, entry.day),
            schemaVersion: 1,
          );
        } else {
          // [케이스 B] 아직 이번 달 지급일(13일)이 안 왔다면?
          // -> 역시 지난달 날짜를 넣어둡니다. 그러면 나중에 13일이 되었을 때 정상 지급됩니다.
          newData = newData.copyWith(
            lastAutoUpdate: DateTime(now.year, now.month - 1, entry.day),
            schemaVersion: 1,
          );
        }
      } else {
        // 입사일 정보가 아예 없는 예외 케이스
        newData = newData.copyWith(
          lastAutoUpdate: now,
          schemaVersion: 1,
        );
      }
    }

    // 버전 2 처리 (예: 새로운 필드 추가 시)
    if (oldVersion < 2) {
      newData = newData.copyWith(
        // 추가된 필드 초기화 로직
        schemaVersion: 2,
      );
    }

    return newData;
  }

  void refreshTotalLeave({DateTime? mockDate}) {
    if (state == null || state!.entryDate == null) return;

    final now = mockDate ?? DateTime.now();
    final entry = state!.entryDate!;
    final reset = state!.resetDate;

    // 1. [리셋 로직]
    if (!now.isBefore(reset)) {
      final newTotal = _calculateFullLegalLeave(entry);
      final nextReset = DateTime(reset.year + 1, reset.month, reset.day);
      saveSettings(newTotal, nextReset, entry, updateLastUpdate: true);
      return;
    }

    // 2. [증분 로직] 1년 미만
    int totalMonths = (now.year - entry.year) * 12 + now.month - entry.month;
    if (now.day < entry.day) totalMonths--;

    if (totalMonths < 12 && totalMonths > 0) {
      // 기록이 없으면 입사일 기준으로 판단
      final lastUpdate = state!.lastAutoUpdate ?? entry;

      bool alreadyUpdatedThisMonth =
          lastUpdate.year == now.year && lastUpdate.month == now.month;

      if (now.day >= entry.day && !alreadyUpdatedThisMonth) {
        final updatedState = state!.copyWith(
          totalLeave: state!.totalLeave + 1.0,
          lastAutoUpdate: now,
        );
        _saveState(updatedState);
      }
    }
  }


  Future<void> _saveState(UserSetting setting) async {
    state = setting;
    final box = Hive.box<UserSetting>('settings');
    await box.put(0, setting);
  }

  Future<void> saveSettings(
      double total,
      DateTime reset,
      DateTime? entry,
      {bool updateLastUpdate = true} // 기본값을 true로 두어 저장 시점 기록
      ) async {
    final now = DateTime.now();
    final setting = UserSetting(
        totalLeave: total,
        resetDate: reset,
        entryDate: entry,
        isFirstRun: false,
        lastAutoUpdate: updateLastUpdate ? now : state?.lastAutoUpdate
    );
    await _saveState(setting);
  }

  double _calculateFullLegalLeave(DateTime entryDate) {
    final now = DateTime.now();
    int totalMonths = (now.year - entryDate.year) * 12 + now.month - entryDate.month;
    if (now.day < entryDate.day) totalMonths--;

    if (totalMonths < 12) {
      return totalMonths.clamp(0, 11).toDouble();
    } else {
      int years = (totalMonths ~/ 12);
      int extra = (years - 1) ~/ 2;
      return (15.0 + extra).clamp(15.0, 25.0);
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
}

class HolidayListNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    return _fetchCalendarData();
  }

  Future<List<Map<String, dynamic>>> _fetchCalendarData() async {
    final service = ref.read(calendarServiceProvider);
    final settings = ref.read(leaveStateProvider);

    if (settings == null) return [];

    var account = await service.signInSilently() ?? await service.signIn();
    if (account == null) return [];

    // ★ 수정: 서비스 호출 시 입사일 정보 전달
    final result = await service.calculateUsedLeave(
        account,
        settings.resetDate,
        entryDate: settings.entryDate
    );

    final List<Map<String, dynamic>> allEvents = List.from(result.events);
    final now = DateTime.now();
    final r = settings.resetDate.toLocal();

    // 1. 이번 주기(Period) 계산
    DateTime periodStart = DateTime(now.year, r.month, r.day);
    if (periodStart.isAfter(now)) {
      periodStart = DateTime(now.year - 1, r.month, r.day);
    }
    final DateTime periodEnd = DateTime(periodStart.year + 1, r.month, r.day).subtract(const Duration(days: 1));

    // 2. 주기 내 필터링
    final List<Map<String, dynamic>> filteredEvents = allEvents.where((event) {
      final DateTime eventDate = (event['date'] is DateTime
          ? event['date']
          : DateTime.parse(event['date'].toString())).toLocal();
      final DateTime eventDateOnly = DateTime(eventDate.year, eventDate.month, eventDate.day);

      // 시작일 전이 아니고, 종료일 후가 아닌 데이터만 (주기 내 데이터)
      return !eventDateOnly.isBefore(periodStart) && !eventDateOnly.isAfter(periodEnd);
    }).toList();

    // 3. 정렬 (오늘 기준 과거/미래)
    final todayStart = DateTime(now.year, now.month, now.day);
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
    // 연차 증분 체크 후 리스트 갱신
    ref.read(leaveStateProvider.notifier).refreshTotalLeave();
    state = await AsyncValue.guard(() => _fetchCalendarData());
  }
}