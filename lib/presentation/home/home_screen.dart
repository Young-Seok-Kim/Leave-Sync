import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leavesync/presentation/home/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/providers/leave_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  double _usedLeave = 0.0;
  List<Map<String, dynamic>> _detectedEvents = [];
  bool _isLoading = false;
  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFirstLaunch();
    _syncData();
  }

  @override
  void dispose() {
    // 3. 옵저버 해제 (메모리 누수 방지)
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 다시 화면으로 돌아왔을 때 (resumed)
    if (state == AppLifecycleState.resumed) {
      debugPrint("앱 복귀 감지: 데이터 새로고침 시작");
      _syncData();
    }
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = ref.read(leaveStateProvider);

    final bool isFirst = prefs.getBool('is_first_launch') ?? true;

    if (isFirst) {
      setState(() => _showGuide = true);

      // ★ 설정 데이터가 없으면 다이얼로그 노출
      if (settings == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showInitSettingDialog();
        });
      }
    }
  }

  void _showInitSettingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("설정이 필요합니다 📅", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("정확한 연차 관리를 위해\n먼저 입사일을 설정해주세요."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
            },
            child: const Text("설정하러 가기", style: TextStyle(color: Color(0xFF764BA2), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _closeGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', false);
    setState(() => _showGuide = false);
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', true);
    await ref.read(calendarServiceProvider).signOut();

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Future<void> _syncData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _detectedEvents = []; // 동기화 시작 시 리스트 초기화
    });

    try {
      final service = ref.read(calendarServiceProvider);
      final settings = ref.read(leaveStateProvider);
      if (settings == null) return;

      var account = await service.signInSilently() ?? await service.signIn();

      if (account != null) {
        final result = await service.calculateUsedLeave(account, settings.resetDate);
        if (mounted) {
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);

          List<Map<String, dynamic>> sortedEvents = List.from(result.events);

          sortedEvents.sort((a, b) {
            final DateTime dateA = a['date'] is DateTime ? a['date'] : DateTime.parse(a['date'].toString());
            final DateTime dateB = b['date'] is DateTime ? b['date'] : DateTime.parse(b['date'].toString());

            // ★ 날짜만 비교하기 위해 시간 정보 제거
            final dayA = DateTime(dateA.year, dateA.month, dateA.day);
            final dayB = DateTime(dateB.year, dateB.month, dateB.day);

            // 오늘이거나 미래면 false, 어제 이전이면 true
            bool isPastA = dayA.isBefore(todayStart);
            bool isPastB = dayB.isBefore(todayStart);

            if (isPastA != isPastB) {
              return isPastA ? 1 : -1;
            }
            return isPastA ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
          });

          setState(() {
            _usedLeave = result.totalUsed;
            _detectedEvents = sortedEvents;
          });
        }
      }
    } catch (e) {
      debugPrint("동기화 오류: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(leaveStateProvider);
    final total = settings?.totalLeave ?? 15.0;
    final remaining = (total - _usedLeave).clamp(0.0, total);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text("내 연차 현황", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _handleLogout,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen())),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildMainContent(total, remaining),
          if (_showGuide) _buildGuideOverlay(),
        ],
      ),
      // 가독성과 클릭 편의성을 모두 잡은 FAB 스타일
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showLeaveTypeSheet,
        label: const Text(
          "연차 등록",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        icon: const Icon(Icons.add_task),
        backgroundColor: const Color(0xFF764BA2),
        foregroundColor: Colors.white,
        elevation: 10, // 그림자를 강화해서 리스트와 시각적으로 분리
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1), // 미세한 테두리로 경계 명확화
        ),
      ),
    );
  }

  Widget _buildMainContent(double total, double remaining) {
    return RefreshIndicator(
      onRefresh: _syncData,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(20.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildDashboardCard(total, remaining),
                const SizedBox(height: 32),
                const Text("상세 사용 내역", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
              ]),
            ),
          ),
          _detectedEvents.isEmpty
              ? const SliverToBoxAdapter(
              child: Center(child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text("감지된 휴가 일정이 없습니다.", style: TextStyle(color: Colors.grey)),
              )))
              : SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildEventTile(_detectedEvents[index]),
                childCount: _detectedEvents.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(double total, double remaining) {
    // 🎯 소수점이 .00이면 정수로, 아니면 불필요한 0만 제거하는 헬퍼 함수
    String formatNum(double n) {
      if (n == n.toInt()) return n.toInt().toString(); // 15.0 -> 15
      // toStringAsFixed(2) 후 소수점 뒤의 불필요한 0과 마침표 제거 (14.50 -> 14.5)
      return n.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.blueAccent.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 8)
          )
        ],
      ),
      child: Column(
        children: [
          const Text("사용 가능한 연차", style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 8),
          // 🎯 포맷팅된 숫자 적용 (remaining과 total 둘 다 적용)
          Text(
              "${formatNum(remaining)} / ${formatNum(total)}",
              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 8,
          ),
        ],
      ),
    );
  }

  Widget _buildEventTile(Map<String, dynamic> event) {
    final dynamic dateValue = event['date'];
    final DateTime eventDate = dateValue is DateTime ? dateValue : DateTime.parse(dateValue.toString());

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(eventDate.year, eventDate.month, eventDate.day);

    // 어제 이전이면 true (회색), 오늘 포함 미래면 false (하얀색)
    final bool isPast = eventDay.isBefore(todayStart);
    final bool isToday = DateUtils.isSameDay(eventDay, now);

    String dateStr = "${eventDate.year}.${eventDate.month.toString().padLeft(2, '0')}.${eventDate.day.toString().padLeft(2, '0')}";

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPast ? 0 : 2,
      // ★ 오늘인 경우에도 다른 미래 휴가와 똑같이 'Colors.white'로 설정
      color: isPast ? const Color(0xFFF1F1F1) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // ★ 색상 대신 깔끔하게 '테두리'만 포인트로 줌
        side: isToday ? const BorderSide(color: Color(0xFF764BA2), width: 2.0) : BorderSide.none,
      ),
      child: ListTile(
        onTap: () => _openEventInGoogleCalendar(event['id']),
        leading: CircleAvatar(
          backgroundColor: isPast ? Colors.grey[300] : const Color(0xFFF3E5F5),
          child: Icon(
              Icons.beach_access,
              color: isPast ? Colors.grey[600] : const Color(0xFF764BA2)
          ),
        ),
        title: Row(
          children: [
            Text(
                event['title'],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPast ? Colors.grey[600] : Colors.black87,
                )
            ),
            if (isToday) ...[
              const SizedBox(width: 8),
              const Badge(
                label: Text("오늘", style: TextStyle(fontSize: 10, color: Colors.white)),
                backgroundColor: Color(0xFF764BA2),
              ),
            ]
          ],
        ),
        subtitle: Text(dateStr, style: TextStyle(color: isPast ? Colors.grey[500] : Colors.black54)),
        trailing: Text(
            "-${event['deduction']}개",
            style: TextStyle(
                color: isPast ? Colors.grey[400] : Colors.deepOrange,
                fontWeight: FontWeight.bold,
                fontSize: 16
            )
        ),
      ),
    );
  }

  Widget _buildGuideOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 30),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_month, color: Color(0xFF764BA2), size: 48),
              const SizedBox(height: 16),
              const Text("💡 필수: 구글 캘린더 연동 안내", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                "본 앱은 본인의 구글 캘린더에\n직접 입력하신 일정을 자동으로 읽어오는 방식입니다.\n로그인한 구글 계정의 캘린더에 \n아래 규칙에 맞춰 일정을 등록해 주세요.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black87, height: 1.5),
              ),
              const SizedBox(height: 24),
              _guideRow("제목에 '연차' 포함 시", "1.0개 차감"),
              _guideRow("제목에 '반차' 포함 시", "0.5개 차감"),
              _guideRow("제목에 '반반차' 포함 시", "0.25개 차감"),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _closeGuide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF764BA2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("이해했습니다", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideRow(String t, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t), Text(v, style: const TextStyle(color: Color(0xFF764BA2), fontWeight: FontWeight.bold))]),
  );

  // 1. 날짜를 먼저 선택받는 함수
  Future<void> _showLeaveTypeSheet() async {
    // 오늘부터 1년 후까지 선택 가능하도록 설정
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)), // 한달 전부터
      lastDate: DateTime.now().add(const Duration(days: 365)), // 1년 후까지
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF764BA2), // 우리 앱 메인 컬러로 달력 색상 변경
            ),
          ),
          child: child!,
        );
      },
    );

    // 날짜 선택 안 하고 취소하면 종료
    if (pickedDate == null) return;

    // 2. 날짜 선택 후 어떤 휴가인지 물어봄 (Context 유지 필요)
    if (!mounted) return;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text("${pickedDate.year}.${pickedDate.month}.${pickedDate.day} 휴가 종류"),
        actions: [
          _leaveAction(pickedDate, "연차", 9, 18),
          _leaveAction(pickedDate, "반차", 13, 18),
          _leaveAction(pickedDate, "반반차", 16, 18),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text("취소", style: TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }

// 3. 반복되는 액션 생성용 헬퍼 함수
  Widget _leaveAction(DateTime date, String type, int startHour, int endHour) {
    return CupertinoActionSheetAction(
      onPressed: () {
        Navigator.pop(context);
        _openGoogleCalendar(date, type, startHour, endHour);
      },
      child: Text("$type ($startHour시 - $endHour시)"),
    );
  }

// 4. 최종 캘린더 실행 함수 (시간 계산 로직 포함)
  Future<void> _openGoogleCalendar(DateTime date, String type, int startH, int endH) async {
    final start = DateTime(date.year, date.month, date.day, startH);
    final end = DateTime(date.year, date.month, date.day, endH);

    // 구글 캘린더 포맷팅 (UTC 변환 필수)
    String formatTime(DateTime dt) =>
        dt.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]|\.\d+'), '');

    final String dateParam = "${formatTime(start)}/${formatTime(end)}";

    final Uri uri = Uri.parse("https://www.google.com/calendar/render").replace(
      queryParameters: {
        'action': 'TEMPLATE',
        'text': '[$type]',
        'dates': dateParam,
        'details': '연차매니저 앱에서 등록된 $type 일정입니다.',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openEventInGoogleCalendar(String? eventId) async {
    if (eventId == null || eventId.isEmpty) {
      debugPrint("에러: eventId가 없습니다!");
      return;
    }

    // eid 방식 대신 'view' 혹은 'edit' 경로를 사용 (더 잘 열림)
    final String url = "https://www.google.com/calendar/event?eid=${_encodeId(eventId)}";
    // 또는 가장 확실한 방법:
    // final String url = "https://calendar.google.com/calendar/r/eventedit/$eventId";

    final Uri uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint("실행 실패: $url");
    }
  }

// 구글 API ID를 딥링크용 ID로 변환해야 할 수도 있음
  String _encodeId(String id) {
    return base64Encode(utf8.encode('$id user@gmail.com')).replaceAll('=', '');
    // 실제로는 본인 이메일 주소가 포함된 문자열을 base64 인코딩해야 함
  }
}