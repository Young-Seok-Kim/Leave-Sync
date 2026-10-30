import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leavesync/presentation/home/add_leave_sheet.dart';
import 'package:leavesync/presentation/home/guide_dialog.dart';
import 'package:leavesync/presentation/home/leave_detail_sheet.dart';
import 'package:leavesync/presentation/home/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/providers/leave_provider.dart';
import '../../data/services/google_calendar_service.dart';
import '../../data/services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  bool _showGuide = false;
  bool _isAddingLeave = false;
  // 상세 사용 내역에 표시할 기간 (null 이면 현재 집계 주기)
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFirstLaunch();
    // 알림 권한은 홈 화면에 들어온 뒤 한 번 요청 (Android 13+)
    NotificationService.instance.requestPermission();
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
      // 구글 캘린더 앱에서 수정/삭제한 내용이 서버에 반영되기까지 시간이 걸리므로
      // 돌아온 직후 한 번, 몇 초 뒤 한 번 더 새로고침합니다.
      for (final delay in const [Duration(seconds: 1), Duration(seconds: 5)]) {
        Future.delayed(delay, () {
          if (mounted) ref.read(holidayListProvider.notifier).refresh();
        });
      }
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
              _openSettings();
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

  /// 설정 화면에서 돌아오면 (캘린더 선택이 바뀌었을 수 있으므로) 목록을 다시 읽어옴
  Future<void> _openSettings() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
    if (!mounted) return;
    if (result == SettingsScreen.resultLoggedOut) {
      // 로그아웃 → 다시 로그인 창을 띄우기 위해 목록을 처음부터 다시 로드
      setState(() => _showGuide = true);
      ref.invalidate(holidayListProvider);
    } else {
      ref.read(holidayListProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(leaveStateProvider);
    final holidayAsync = ref.watch(holidayListProvider);

    final total = settings?.totalLeave ?? 15.0;
    final DateTime? resetDate = settings?.resetDate;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text("내 연차 현황", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            tooltip: "설정",
            onPressed: _openSettings,
          ),
        ],
      ),
      // AsyncValue의 상태에 따라 분기 처리 (기존 UI 레이아웃 유지)
      body: holidayAsync.when(
        // skipLoadingOnRefresh: true를 주면
        // 새로고침(refresh) 중에도 로딩 화면으로 가지 않고 기존 data를 계속 보여줍니다.
        skipLoadingOnRefresh: true,
        data: (allEvents) {
          // 잔여 연차는 항상 '현재 집계 주기' 기준
          final List<Map<String, dynamic>> cycleEvents;
          DateTimeRange? cycleRange;
          if (resetDate != null) {
            final p = currentPeriod(resetDate);
            cycleRange = DateTimeRange(start: p.start, end: p.end);
            cycleEvents = filterLeaveEvents(allEvents, p.start, p.end);
          } else {
            cycleEvents = allEvents;
          }
          final usedLeave = cycleEvents.fold<double>(0.0, (sum, item) => sum + (item['deduction'] ?? 0.0));
          final remaining = (total - usedLeave).clamp(0.0, total);

          // 상세 내역은 사용자가 고른 기간(없으면 집계 주기) 기준
          final displayRange = _customRange ?? cycleRange;
          final displayEvents = displayRange == null
              ? allEvents
              : filterLeaveEvents(allEvents, displayRange.start, displayRange.end);

          return Stack(
            children: [
              _buildMainContent(total, remaining, allEvents, displayEvents, displayRange, cycleRange, resetDate),
              if (_showGuide)
                Container(
                  color: Colors.black.withOpacity(0.85),
                  width: double.infinity,
                  height: double.infinity,
                  child: Center(child: GuideCard(onClose: _closeGuide)),
                ),

              // 백그라운드 로딩(새로고침/등록) 중임을 작게 표시
              if (holidayAsync.isRefreshing || _isAddingLeave)
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
        error: (err, stack) => _buildErrorView(err),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAddingLeave ? null : _showAddLeaveSheet,
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

  /// 동기화 실패 화면: 원인에 따라 "다시 로그인" 또는 "다시 시도" 제공
  Widget _buildErrorView(Object err) {
    final bool needLogin = err is NotSignedInException;
    final String message = needLogin
        ? "구글 계정 로그인이 필요합니다.\n로그인 후 캘린더 일정을 읽어올 수 있어요."
        : "캘린더 동기화 중 오류가 발생했습니다.\n네트워크 상태를 확인한 뒤 다시 시도해 주세요.";

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(needLogin ? Icons.account_circle_outlined : Icons.cloud_off,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87, height: 1.5)),
            if (!needLogin) ...[
              const SizedBox(height: 8),
              Text(
                err.toString(),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.read(holidayListProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text("다시 시도"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF764BA2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => ref.read(holidayListProvider.notifier).reSignIn(),
              icon: const Icon(Icons.login, size: 18),
              label: const Text("다른 계정으로 다시 로그인"),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF764BA2)),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      "${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}";

  String _fmtNum(double n) {
    if (n == n.toInt()) return n.toInt().toString();
    return n.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  /// 다음 초기화일까지 남은 일수 텍스트 (오늘이면 "오늘", 지났으면 빈 문자열)
  String _dDayText(DateTime reset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(reset.year, reset.month, reset.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return "오늘";
    if (diff < 0) return "";
    return "D-$diff";
  }

  /// 초기화일까지 남은 개월 수 (이번 달 포함, 최소 1)
  int _monthsLeft(DateTime reset) {
    final now = DateTime.now();
    final months = (reset.year - now.year) * 12 + (reset.month - now.month) + 1;
    return months < 1 ? 1 : months;
  }

  /// 남은 연차를 남은 개월 수로 나눈 월 평균 (소수 첫째 자리까지)
  double _monthlyAverage(double remaining, DateTime reset) {
    final avg = remaining / _monthsLeft(reset);
    return (avg * 10).floorToDouble() / 10;
  }

  DateTime _eventStart(Map<String, dynamic> e) =>
      e['date'] is DateTime ? e['date'] : DateTime.parse(e['date'].toString());

  Widget _buildMainContent(
    double total,
    double remaining,
    List<Map<String, dynamic>> allEvents,
    List<Map<String, dynamic>> events,
    DateTimeRange? displayRange,
    DateTimeRange? cycleRange,
    DateTime? resetDate,
  ) {
    final bool isCustom = _customRange != null;

    return RefreshIndicator(
      onRefresh: () => ref.read(holidayListProvider.notifier).refresh(),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(20.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildDashboardCard(total, remaining, resetDate),
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text("상세 사용 내역", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (displayRange != null)
                      InkWell(
                        onTap: () => _pickDisplayRange(displayRange, cycleRange),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune, size: 14, color: isCustom ? const Color(0xFF764BA2) : Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                "${_fmtDate(displayRange.start)} ~ ${_fmtDate(displayRange.end)}",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isCustom ? const Color(0xFF764BA2) : Colors.grey,
                                  fontWeight: isCustom ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              if (isCustom) ...[
                                const SizedBox(width: 2),
                                GestureDetector(
                                  onTap: () => setState(() => _customRange = null),
                                  child: const Icon(Icons.close, size: 14, color: Color(0xFF764BA2)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildUsageSummary(allEvents),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          events.isEmpty
              ? const SliverToBoxAdapter(
              child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text("이 기간에 감지된 휴가 일정이 없습니다.", style: TextStyle(color: Colors.grey)),
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

  /// 이번 달 사용량과 다가오는 휴가를 한 줄로 요약
  /// 상세 내역 기간 선택 (기본값은 집계 주기)
  Future<void> _pickDisplayRange(DateTimeRange current, DateTimeRange? cycleRange) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: current,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: "상세 내역에 표시할 기간",
      saveText: "적용",
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF764BA2)),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final sameAsCycle = cycleRange != null &&
        DateUtils.isSameDay(picked.start, cycleRange.start) &&
        DateUtils.isSameDay(picked.end, cycleRange.end);
    setState(() => _customRange = sameAsCycle ? null : picked);
  }

  /// 이번 달 사용량과 다가오는 휴가를 한 줄로 요약. 탭하면 해당 목록을 보여줌
  Widget _buildUsageSummary(List<Map<String, dynamic>> events) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final List<Map<String, dynamic>> thisMonthEvents = [];
    final List<Map<String, dynamic>> upcomingEvents = [];
    double thisMonth = 0.0;
    double upcoming = 0.0;
    for (final e in events) {
      final d = _eventStart(e);
      final deduction = (e['deduction'] ?? 0.0) as double;
      if (d.year == now.year && d.month == now.month) {
        thisMonth += deduction;
        thisMonthEvents.add(e);
      }
      if (!DateTime(d.year, d.month, d.day).isBefore(todayStart)) {
        upcoming += deduction;
        upcomingEvents.add(e);
      }
    }

    Widget chip(IconData icon, String text, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: const Color(0xFF764BA2)),
                const SizedBox(width: 4),
                Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                const SizedBox(width: 2),
                const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.grey),
              ],
            ),
          ),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        chip(
          Icons.today,
          "${now.month}월 사용 ${_fmtNum(thisMonth)}개",
          () => _showEventListSheet("${now.year}년 ${now.month}월에 쓴 휴가", thisMonthEvents, thisMonth),
        ),
        chip(
          Icons.upcoming,
          "예정 ${upcomingEvents.length}건 · ${_fmtNum(upcoming)}개",
          () => _showEventListSheet("다가오는 휴가", upcomingEvents, upcoming),
        ),
      ],
    );
  }

  /// 요약 칩을 눌렀을 때 해당 휴가 목록을 보여주는 시트
  void _showEventListSheet(String title, List<Map<String, dynamic>> events, double totalDeduction) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF5F5F7),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  Text(
                    "${events.length}건 · ${_fmtNum(totalDeduction)}개",
                    style: const TextStyle(fontSize: 13, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Flexible(
              child: events.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text("해당하는 휴가가 없습니다.", style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: events.length,
                      itemBuilder: (_, i) => _buildEventTile(events[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard(double total, double remaining, DateTime? resetDate) {
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
              "${_fmtNum(remaining)} / ${_fmtNum(total)}",
              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 8,
          ),
          if (resetDate != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.event_repeat, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                const Text("다음 초기화일", style: TextStyle(color: Colors.white70, fontSize: 13)),
                const Spacer(),
                Text(
                  _fmtDate(resetDate.toLocal()),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                if (_dDayText(resetDate.toLocal()).isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _dDayText(resetDate.toLocal()),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_month, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                const Text("월 평균 사용 가능", style: TextStyle(color: Colors.white70, fontSize: 13)),
                const Spacer(),
                Text(
                  "${_fmtNum(_monthlyAverage(remaining, resetDate.toLocal()))}개",
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                Text(
                  "(${_monthsLeft(resetDate.toLocal())}개월 남음)",
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventTile(Map<String, dynamic> event) {
    final dynamic endDateValue = event['endDate'];

    final DateTime startDate = _eventStart(event);

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
    // 시작일까지 남은 일수 (아직 지나지 않은 일정에만 날짜 옆에 표시)
    final int daysLeft = eventDay.difference(todayStart).inDays;
    final bool isUpcoming = daysLeft > 0;

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
        onTap: () => showLeaveDetailSheet(
          context,
          event: event,
          onOpenCalendar: () => _openEventInGoogleCalendar(event['id']),
        ),
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
        subtitle: Text(
          isUpcoming ? "$dateStr (D-$daysLeft일)" : dateStr,
          style: TextStyle(color: isPast ? Colors.grey[500] : Colors.black54),
        ),
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

  /// 휴가 등록 시트에서 기간/종류/제목/장소/메모를 입력받아 앱에서 바로 캘린더에 등록
  Future<void> _showAddLeaveSheet() async {
    final request = await showAddLeaveSheet(context);
    if (request == null || !mounted) return;

    setState(() => _isAddingLeave = true);
    try {
      await ref.read(holidayListProvider.notifier).addLeave(request);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("'${request.title}' 일정을 캘린더에 등록했습니다."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("등록 실패: 캘린더 쓰기 권한을 확인해 주세요.\n$e"),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAddingLeave = false);
    }
  }

  Future<void> _openEventInGoogleCalendar(String? eventId) async {
    if (eventId == null || eventId.isEmpty) return;
    final email = ref.read(calendarServiceProvider).currentEmail;
    if (email == null) return;
    final String url = "https://www.google.com/calendar/event?eid=${_encodeId(eventId, email)}";
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 구글 캘린더 웹 링크의 eid 는 "<eventId> <계정이메일>" 을 base64 한 값
  String _encodeId(String id, String email) {
    return base64Encode(utf8.encode('$id $email')).replaceAll('=', '');
  }
}
