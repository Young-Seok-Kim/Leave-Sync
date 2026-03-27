import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leavesync/presentation/home/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/providers/leave_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _usedLeave = 0.0;
  List<Map<String, dynamic>> _detectedEvents = [];
  bool _isLoading = false;
  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
    _syncData();
  }

  // 가이드 노출 여부 확인
  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    // 저장된 값이 없거나 true면 가이드를 보여줌
    final bool isFirst = prefs.getBool('is_first_launch') ?? true;
    if (isFirst) {
      setState(() => _showGuide = true);
    }
  }

  // 가이드 닫기 및 다시 보지 않기 설정
  Future<void> _closeGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', false);
    setState(() => _showGuide = false);
  }

  // ★ 로그아웃 시 가이드 상태 초기화
  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    // 가이드 상태를 다시 true로 초기화하여 다음 로그인 시 보이게 함
    await prefs.setBool('is_first_launch', true);

    await ref.read(calendarServiceProvider).signOut();

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Future<void> _syncData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final service = ref.read(calendarServiceProvider);
      final settings = ref.read(leaveStateProvider);
      if (settings == null) return;

      var account = await service.signInSilently() ?? await service.signIn();

      if (account != null) {
        final result = await service.calculateUsedLeave(account, settings.resetDate);
        if (mounted) {
          setState(() {
            _usedLeave = result.totalUsed;
            _detectedEvents = result.events;
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
            onPressed: _handleLogout, // 수정된 로그아웃 함수 호출
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _syncData,
        label: Text(_isLoading ? "동기화 중..." : "지금 동기화"),
        icon: const Icon(Icons.sync),
        backgroundColor: const Color(0xFF764BA2),
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          const Text("사용 가능한 연차", style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 8),
          Text("${remaining.toStringAsFixed(2)} / ${total.toStringAsFixed(1)}",
              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total > 0 ? (remaining / total).clamp(0, 1) : 0,
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
    String dateStr = "날짜 정보 없음";

    if (dateValue is DateTime) {
      dateStr = "${dateValue.year}.${dateValue.month}.${dateValue.day}";
    } else if (dateValue != null) {
      dateStr = dateValue.toString().split('T')[0].replaceAll('-', '.');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFF3E5F5), child: Icon(Icons.beach_access, color: Color(0xFF764BA2))),
        title: Text(event['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(dateStr),
        trailing: Text("-${event['deduction']}개", style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 16)),
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
                "본 앱은 본인의 구글 캘린더(Primary)에\n직접 입력하신 일정을 읽어오는 방식입니다.\n아래 규칙에 맞춰 일정을 등록해 주세요.",
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
                  onPressed: _closeGuide, // 가이드 닫으면서 false 저장
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
}