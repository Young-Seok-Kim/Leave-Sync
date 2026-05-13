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
  });
}