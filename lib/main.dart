import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:leavesync/presentation/home/home_screen.dart';
import 'package:leavesync/presentation/onboarding/onboarding_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'data/models/user_setting.dart';
import 'data/providers/leave_provider.dart';

void main() async {
  await Hive.initFlutter();
  Hive.registerAdapter(UserSettingAdapter());
  await Hive.openBox<UserSetting>('settings');
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // 2. .env 파일 로드
    await dotenv.load(fileName: ".env");
    debugPrint("✅ 환경변수 로드 완료");
  } catch (e) {
    debugPrint("❌ .env 파일을 찾을 수 없습니다: $e");
  }
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userSetting = ref.watch(leaveStateProvider);

    return MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'), // 한국어
        Locale('en', 'US'), // 영어
      ],
      // 기기 설정에 맞춰 자동으로 언어 선택
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale != null) {
          for (var supportedLocale in supportedLocales) {
            if (supportedLocale.languageCode == locale.languageCode) {
              return supportedLocale;
            }
          }
        }
        return supportedLocales.first;
      },
      home: userSetting == null || userSetting.isFirstRun == true
          ? const OnboardingScreen()
          : const AuthCheck(),
    );
  }
}

class AuthCheck extends ConsumerWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(calendarServiceProvider).signInSilently(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return const HomeScreen();
      },
    );
  }
}