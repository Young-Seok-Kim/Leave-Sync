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
  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFirstLaunch();
    // 데이터 동기화는 Provider가 알아서 build 시점에 수행합니다.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 0.5초 정도의 미세한 딜레이를 주면 구글 서버 반영 시간을 벌 수 있습니다.
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          ref.read(holidayListProvider.notifier).refresh();
        }
      });
    }
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = ref.read(leaveStateProvider);
    final bool isFirst = prefs.getBool('is_first_launch') ?? true;

    if (isFirst) {
      setState(() => _showGuide = true);
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(leaveStateProvider);
    final holidayAsync = ref.watch(holidayListProvider);

    final total = settings?.totalLeave ?? 15.0;

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
      // AsyncValue의 상태에 따라 분기 처리 (기존 UI 레이아웃 유지)
      body: holidayAsync.when(
        // skipLoadingOnRefresh: true를 주면
        // 새로고침(refresh) 중에도 로딩 화면으로 가지 않고 기존 data를 계속 보여줍니다.
        skipLoadingOnRefresh: true,
        data: (events) {
          final usedLeave = events.fold<double>(0.0, (sum, item) => sum + (item['deduction'] ?? 0.0));
          final remaining = (total - usedLeave).clamp(0.0, total);

          return Stack(
            children: [
              _buildMainContent(total, remaining, events),
              if (_showGuide) _buildGuideOverlay(),

              // [선택 사항] 백그라운드 로딩 중임을 작게 표시하고 싶을 때
              if (holidayAsync.isRefreshing)
                const Positioned(
                  top: 10,
                  right: 10,
                  child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          );
        },
        // 진짜 데이터가 '아예' 없을 때(맨 처음 실행 등)만 이 로딩이 돕니다.
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF764BA2))),
        error: (err, stack) => Center(child: Text("동기화 오류가 발생했습니다.")),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showLeaveTypeSheet,
        label: const Text("연차 등록", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5)),
        icon: const Icon(Icons.add_task),
        backgroundColor: const Color(0xFF764BA2),
        foregroundColor: Colors.white,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1),
        ),
      ),
    );
  }

  Widget _buildMainContent(double total, double remaining, List<Map<String, dynamic>> events) {
    return RefreshIndicator(
      onRefresh: () => ref.read(holidayListProvider.notifier).refresh(),
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
          events.isEmpty
              ? const SliverToBoxAdapter(
              child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text("감지된 휴가 일정이 없습니다.", style: TextStyle(color: Colors.grey)),
                  )))
              : SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildEventTile(events[index]),
                childCount: events.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(double total, double remaining) {
    String formatNum(double n) {
      if (n == n.toInt()) return n.toInt().toString();
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
    final dynamic endDateValue = event['endDate'];

    final DateTime startDate = dateValue is DateTime
        ? dateValue
        : DateTime.parse(dateValue.toString());

    DateTime? endDate;
    if (endDateValue != null) {
      endDate = endDateValue is DateTime
          ? endDateValue
          : DateTime.parse(endDateValue.toString());
    }

    // ★ 방어 코드: 보정 로직 때문에 종료일이 시작일보다 전으로 갔다면 시작일과 같게 맞춤
    if (endDate != null && endDate.isBefore(startDate)) {
      endDate = startDate;
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(startDate.year, startDate.month, startDate.day);

    final bool isPast = eventDay.isBefore(todayStart);
    final bool isToday = DateUtils.isSameDay(eventDay, now);

    String dateStr = "${startDate.year}.${startDate.month.toString().padLeft(2, '0')}.${startDate.day.toString().padLeft(2, '0')}";

    // 시작일과 종료일이 '다른 날'일 때만 범위(~)를 표시
    if (endDate != null && !DateUtils.isSameDay(startDate, endDate)) {
      dateStr += " ~ ${endDate.month.toString().padLeft(2, '0')}.${endDate.day.toString().padLeft(2, '0')}";
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPast ? 0 : 2,
      color: isPast ? const Color(0xFFF1F1F1) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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
            Expanded( // 제목이 길 경우 대비
              child: Text(
                  event['title'],
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isPast ? Colors.grey[600] : Colors.black87,
                  )
              ),
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

  Future<void> _showLeaveTypeSheet() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF764BA2)),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null) return;
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

  Widget _leaveAction(DateTime date, String type, int startHour, int endHour) {
    return CupertinoActionSheetAction(
      onPressed: () {
        Navigator.pop(context);
        _openGoogleCalendar(date, type, startHour, endHour);
      },
      child: Text("$type ($startHour시 - $endHour시)"),
    );
  }

  Future<void> _openGoogleCalendar(DateTime date, String type, int startH, int endH) async {
    final start = DateTime(date.year, date.month, date.day, startH);
    final end = DateTime(date.year, date.month, date.day, endH);

    // 날짜 포맷 (UTC 기준 ISO8601, 특수기호 제거)
    String formatTime(DateTime dt) =>
        dt.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]|\.\d+'), '');

    final String dateParam = "${formatTime(start)}/${formatTime(end)}";

    // ✅ 가장 범용적으로 앱 등록 화면을 띄워주는 URL 패턴
    final Uri uri = Uri.parse("https://www.google.com/calendar/render").replace(
      queryParameters: {
        'action': 'TEMPLATE',
        'text': '[$type]',
        'dates': dateParam,
        'details': '연차매니저 앱에서 등록된 $type 일정입니다.',
        'sf': 'true', // Show Form (등록 폼을 강제로 보여줌)
        'output': 'xml', // 앱 딥링크 처리 시 인식이 더 잘 되는 구형 파라미터
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        // ✅ 'externalApplication'으로 먼저 테스트해보세요.
        // 일부 기기에서는 'externalNonBrowserApplication'이 앱 내부의 특정 Activity를 못 찾을 수 있습니다.
        mode: LaunchMode.externalApplication,
      );
    }
  }

  Future<void> _openEventInGoogleCalendar(String? eventId) async {
    if (eventId == null || eventId.isEmpty) return;
    final String url = "https://www.google.com/calendar/event?eid=${_encodeId(eventId)}";
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _encodeId(String id) {
    return base64Encode(utf8.encode('$id user@gmail.com')).replaceAll('=', '');
  }
}