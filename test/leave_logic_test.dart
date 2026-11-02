import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart'; // ★ hive_test 패키지가 필요합니다
import 'package:hive/hive.dart';
import 'package:leavesync/data/providers/leave_provider.dart';
import 'package:leavesync/data/models/user_setting.dart';

void main() {
  setUp(() async {
    await setUpTestHive();

    // 1. UserSetting 클래스를 위한 어댑터를 등록합니다.
    // 이 코드가 없으면 UserSetting 객체를 Hive에 저장하거나 읽을 수 없습니다.
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(UserSettingAdapter());
    }

    await Hive.openBox<UserSetting>('settings');
  });

  tearDown(() async {
    await Hive.close();
  });

  group('연차 자동 증분 로직 테스트', () {
    test('향후 5년치 연차 변화 시뮬레이션', () async {
      final box = Hive.box<UserSetting>('settings');
      final entryDate = DateTime(2026, 4, 13);

      final initialState = UserSetting(
        totalLeave: 0.0,
        resetDate: DateTime(2027, 4, 13), // 첫 리셋일
        entryDate: entryDate,
        lastAutoUpdate: null,
        schemaVersion: 2,
      );
      await box.put(0, initialState);

      final notifier = LeaveNotifier();
      await Future.delayed(Duration.zero);
      notifier.state = initialState;

      print('\n--- [향후 5년 시뮬레이션 시작] ---');

      // 5년(365일 * 5 + 윤달 고려) 동안 매일 체크
      for (int i = 0; i <= 3000; i++) {
        final mockDate = entryDate.add(Duration(days: i));
        final oldLeave = notifier.state!.totalLeave;

        notifier.refreshTotalLeave(mockDate: mockDate);

        final newLeave = notifier.state!.totalLeave;

        // 연차가 변했을 때만 로그 출력 (증분 혹은 리셋)
        if (oldLeave != newLeave) {
          print('날짜: ${mockDate.toString().split(' ')[0]} | 연차: $oldLeave -> $newLeave');
        }
      }
      print('--- [시뮬레이션 종료] ---\n');
    });

    test('초기화일 당일까지 사용 가능하고 다음 날 리셋되며, 다음 초기화일은 1년 뒤 같은 날', () async {
      final box = Hive.box<UserSetting>('settings');
      final initial = UserSetting(
        totalLeave: 15.0,
        resetDate: DateTime(2026, 12, 31),
        entryDate: DateTime(2020, 1, 1),
        lastAutoUpdate: DateTime(2026, 11, 1),
        schemaVersion: 2,
      );
      await box.put(0, initial);
      final notifier = LeaveNotifier();
      await Future.delayed(Duration.zero);
      notifier.state = initial;

      // 12.31 당일에는 아직 리셋되지 않음
      notifier.refreshTotalLeave(mockDate: DateTime(2026, 12, 31, 23));
      expect(notifier.state!.resetDate, DateTime(2026, 12, 31));

      // 1.1 이 되면 리셋되고 다음 초기화일은 2027.12.31
      notifier.refreshTotalLeave(mockDate: DateTime(2027, 1, 1));
      expect(notifier.state!.resetDate, DateTime(2027, 12, 31));
    });

    test('오래 안 열었다가 실행해도 다음 초기화일은 오늘 이후로 맞춰짐', () async {
      final box = Hive.box<UserSetting>('settings');
      final initial = UserSetting(
        totalLeave: 15.0,
        resetDate: DateTime(2024, 12, 31),
        entryDate: DateTime(2020, 1, 1),
        lastAutoUpdate: DateTime(2024, 11, 1),
        schemaVersion: 2,
      );
      await box.put(0, initial);
      final notifier = LeaveNotifier();
      await Future.delayed(Duration.zero);
      notifier.state = initial;

      notifier.refreshTotalLeave(mockDate: DateTime(2026, 11, 2));
      expect(notifier.state!.resetDate, DateTime(2026, 12, 31));
    });
  });

  group('집계 주기 계산', () {
    test('초기화일 12.31 → 1.1 ~ 12.31', () {
      final p = currentPeriod(DateTime(2026, 12, 31), now: DateTime(2026, 11, 2));
      expect(p.start, DateTime(2026, 1, 1));
      expect(p.end, DateTime(2026, 12, 31));
    });

    test('초기화일 당일도 현재 주기에 포함', () {
      final p = currentPeriod(DateTime(2026, 12, 31), now: DateTime(2026, 12, 31));
      expect(p.start, DateTime(2026, 1, 1));
      expect(p.end, DateTime(2026, 12, 31));
    });

    test('초기화일이 지나면 다음 주기 (1.1 → 올해 1.1 ~ 12.31)', () {
      final p = currentPeriod(DateTime(2026, 12, 31), now: DateTime(2027, 1, 1));
      expect(p.start, DateTime(2027, 1, 1));
      expect(p.end, DateTime(2027, 12, 31));
    });

    test('입사일 기준 초기화일 4.12 → 작년 4.13 ~ 올해 4.12', () {
      final p = currentPeriod(DateTime(2027, 4, 12), now: DateTime(2026, 11, 2));
      expect(p.start, DateTime(2026, 4, 13));
      expect(p.end, DateTime(2027, 4, 12));
    });
  });
}