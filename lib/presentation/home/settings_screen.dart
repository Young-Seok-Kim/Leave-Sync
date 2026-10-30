import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/providers/leave_provider.dart';
import '../../data/services/google_calendar_service.dart';
import '../../data/services/notification_service.dart';
import 'guide_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  /// 로그아웃하고 돌아왔을 때 Navigator.pop 결과로 전달되는 값
  static const String resultLoggedOut = 'logged_out';

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _brand = Color(0xFF764BA2);

  late TextEditingController _totalController;
  late DateTime _selectedDate;
  DateTime? _entryDate; // 입사일 관리

  // 캘린더 선택
  List<CalendarInfo>? _calendars;
  String? _calendarError;
  late Set<String> _selectedCalendarIds;

  @override
  void initState() {
    super.initState();
    final currentSetting = ref.read(leaveStateProvider);
    _totalController = TextEditingController(text: currentSetting?.totalLeave.toString() ?? "15");
    _selectedDate = currentSetting?.resetDate ?? DateTime(DateTime.now().year, 12, 31);
    _entryDate = currentSetting?.entryDate;
    _selectedCalendarIds = {...(currentSetting?.effectiveCalendarIds ?? const ['primary'])};
    _loadCalendars();
  }

  @override
  void dispose() {
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _loadCalendars() async {
    try {
      final list = await ref.read(calendarServiceProvider).listCalendars();
      if (!mounted) return;
      setState(() {
        _calendars = list;
        _calendarError = null;
        // 저장된 ID 가 'primary' 별칭이면 실제 기본 캘린더 ID 로도 매칭되도록 보정
        final primary = list.where((c) => c.isPrimary).firstOrNull;
        if (primary != null && _selectedCalendarIds.contains('primary')) {
          _selectedCalendarIds
            ..remove('primary')
            ..add(primary.id);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _calendarError = e is NotSignedInException
          ? "구글 로그인 후 캘린더를 선택할 수 있습니다."
          : "캘린더 목록을 불러오지 못했습니다.");
    }
  }

  Future<void> _pickEntryDate() async {
    // 현재 저장된 날짜가 미래일 경우를 대비해 initialDate를 안전하게 설정
    DateTime initial = _entryDate ?? DateTime.now();
    final DateTime upperLimit = DateTime(2100, 12, 31);

    // initialDate는 반드시 firstDate와 lastDate 사이에 있어야 합니다.
    if (initial.isAfter(upperLimit)) {
      initial = DateTime.now();
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: upperLimit,
      helpText: "입사일을 선택하면 연차가 자동 계산됩니다",
    );

    if (picked != null) {
      setState(() {
        _entryDate = picked;
        final result = ref.read(leaveStateProvider.notifier).calculateByEntryDate(picked);
        _totalController.text = result.toString();
      });
    }
  }

  Future<void> _save() async {
    final total = double.tryParse(_totalController.text) ?? 15.0;

    // 선택된 캘린더 중 실제 기본 캘린더는 'primary' 별칭으로 저장 (계정 바꿔도 동작하도록)
    final primaryId = _calendars?.where((c) => c.isPrimary).firstOrNull?.id;
    final ids = _selectedCalendarIds
        .map((id) => id == primaryId ? 'primary' : id)
        .toSet()
        .toList();


    await ref.read(leaveStateProvider.notifier).saveSettings(
          total,
          _selectedDate,
          _entryDate,
          calendarIds: ids.isEmpty ? const ['primary'] : ids,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("로그아웃", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("구글 계정 연결을 해제합니다.\n입사일 등 설정은 그대로 유지되며,\n다음 실행 시 다시 로그인하면 됩니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("로그아웃", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', true);
    await ref.read(calendarServiceProvider).signOut();
    await NotificationService.instance.cancelAll();
    if (mounted) Navigator.pop(context, SettingsScreen.resultLoggedOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("설정", style: TextStyle(fontWeight: FontWeight.bold)), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("연차 기준"),
            const SizedBox(height: 12),
            TextField(
              controller: _totalController,
              decoration: InputDecoration(
                labelText: "총 연차 개수",
                helperText: _entryDate != null
                    ? "입사일 ${_entryDate!.year}.${_entryDate!.month}.${_entryDate!.day} 기준 · 아이콘을 눌러 다시 계산"
                    : "오른쪽 아이콘을 눌러 입사일로 자동 계산",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.auto_awesome, color: Colors.deepPurpleAccent),
                  tooltip: "입사일로 자동 계산",
                  onPressed: _pickEntryDate,
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text("연차 초기화 날짜"),
              subtitle: Text("${_selectedDate.year}.${_selectedDate.month}.${_selectedDate.day}"),
              trailing: const Icon(Icons.calendar_month),
              shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2040),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),

            const SizedBox(height: 32),
            _sectionTitle("휴가를 읽어올 캘린더"),
            const SizedBox(height: 4),
            const Text(
              "선택한 캘린더의 일정 중 '연차/반차/반반차'가 포함된 제목만 집계합니다.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildCalendarSection(),

            const SizedBox(height: 32),
            _sectionTitle("기타"),
            const SizedBox(height: 12),
            _menuTile(
              icon: Icons.help_outline,
              title: "캘린더 작성 규칙 보기",
              subtitle: "처음 실행 때 봤던 안내를 다시 봅니다",
              onTap: () => showGuideDialog(context),
            ),
            const SizedBox(height: 8),
            _menuTile(
              icon: Icons.logout,
              iconColor: Colors.redAccent,
              title: "구글 계정 로그아웃",
              subtitle: "다른 계정으로 바꾸거나 연결을 해제합니다",
              onTap: _confirmLogout,
            ),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("저장하기", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blueGrey),
      );

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = _brand,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }

  Widget _buildCalendarSection() {
    if (_calendarError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.grey, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(_calendarError!, style: const TextStyle(color: Colors.grey))),
            TextButton(onPressed: _loadCalendars, child: const Text("재시도")),
          ],
        ),
      );
    }
    if (_calendars == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final c in _calendars!)
            CheckboxListTile(
              value: _selectedCalendarIds.contains(c.id),
              activeColor: _brand,
              title: Text(c.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                c.isPrimary ? "기본 캘린더 · 앱에서 등록한 휴가가 여기에 저장됩니다" : (c.canWrite ? "편집 가능" : "읽기 전용"),
                style: const TextStyle(fontSize: 11),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedCalendarIds.add(c.id);
                  } else if (_selectedCalendarIds.length > 1) {
                    _selectedCalendarIds.remove(c.id);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("캘린더는 최소 1개 선택해야 합니다."), behavior: SnackBarBehavior.floating),
                    );
                  }
                });
              },
            ),
        ],
      ),
    );
  }
}
