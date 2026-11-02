import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/leave_provider.dart';

enum _Step { checking, login, form }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _brand = Color(0xFF764BA2);

  // ★ 수동 수정을 위해 TextEditingController를 다시 도입합니다.
  final _totalController = TextEditingController(text: "15.0");
  DateTime _resetDate = DateTime(DateTime.now().year, 12, 31);
  DateTime? _entryDate;

  /// 화면 단계: 기기에 남은 로그인 확인 중 → 구글 로그인 → (백업이 없을 때만) 입사일 입력
  _Step _step = _Step.checking;
  bool _restoring = false;
  String? _email; // 로그인된 계정 (입력 화면 안내용)

  @override
  void initState() {
    super.initState();
    // 앱을 지웠다 다시 설치한 경우: 기기에 남은 구글 로그인으로 조용히 이전 설정 복원 시도
    _restoreFromAccount(silent: true);
  }

  @override
  void dispose() {
    _totalController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 구글 로그인 뒤 계정에 백업된 설정(입사일·연차·초기화일·캘린더)을 불러온다.
  /// - 백업이 있으면 그대로 적용 → leaveStateProvider 가 채워져 MyApp 이 자동으로 홈 화면으로 넘어간다.
  /// - 백업이 없으면 그때만 입사일 입력 화면을 보여준다.
  Future<void> _restoreFromAccount({required bool silent}) async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      final service = ref.read(calendarServiceProvider);
      final account = await service.signInSilently() ??
          (silent ? null : await service.signIn());
      if (account == null) {
        if (!silent) _toast("구글 로그인이 취소되었습니다.");
        if (mounted) setState(() => _step = _Step.login);
        return;
      }
      await service.ensureScopes();
      final restored = await ref.read(settingsBackupProvider).restore();
      if (restored == null) {
        if (mounted) {
          setState(() {
            _email = account.email;
            _step = _Step.form;
          });
        }
        return;
      }
      await ref
          .read(leaveStateProvider.notifier)
          .applyRestored(restored, account.email);
    } catch (e) {
      if (!silent) _toast("설정을 불러오지 못했습니다: $e");
      if (mounted) setState(() => _step = _Step.login);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  // ★ 입사일 선택 시 로직 수정
  Future<void> _pickEntryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: "입사일을 선택하세요",
    );
    if (picked != null) {
      setState(() {
        _entryDate = picked;

        // 1. 연차 개수 계산 (21.05.17 입사 -> 현재 16개 나오도록 로직 보정)
        final double result = _calculateLegally(picked);
        _totalController.text =
            result.toStringAsFixed(result.truncateToDouble() == result ? 0 : 2);

        // 2. ★ 초기화 날짜: 다음 입사기념일의 '하루 전'으로 세팅
        // 오늘 날짜 기준으로 아직 올해 입사일이 안 지났으면 올해, 지났으면 내년 날짜의 하루 전
        final now = DateTime.now();
        DateTime nextAnniversary = DateTime(now.year, picked.month, picked.day);
        if (nextAnniversary.isBefore(now)) {
          nextAnniversary = DateTime(now.year + 1, picked.month, picked.day);
        }
        _resetDate = nextAnniversary.subtract(const Duration(days: 1));
      });
    }
  }

  // ★ 보정된 근로기준법 계산 로직
  double _calculateLegally(DateTime entry) {
    final now = DateTime.now();
    // 만 근속연수 계산
    int years = now.year - entry.year;
    if (now.month < entry.month ||
        (now.month == entry.month && now.day < entry.day)) {
      years--;
    }

    if (years < 1) {
      int months = (now.year - entry.year) * 12 + now.month - entry.month;
      if (now.day < entry.day) months--;
      return months.clamp(0, 11).toDouble();
    } else {
      // 1년(15개), 2년(15개), 3년(16개), 4년(16개), 5년(17개)...
      // 가산 연차 = (근속연수 - 1) / 2
      int extra = (years - 1) ~/ 2;
      return (15.0 + extra).clamp(15.0, 25.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("초기 설정",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: switch (_step) {
        _Step.checking =>
          const Center(child: CircularProgressIndicator(color: _brand)),
        _Step.login => _buildLoginStep(),
        _Step.form => _buildFormStep(),
      },
    );
  }

  /// 1단계: 구글 로그인. 백업된 설정이 있으면 여기서 바로 홈으로 넘어간다.
  Widget _buildLoginStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("반갑습니다! 👋\n구글 계정으로 시작하세요.",
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, height: 1.4)),
          const SizedBox(height: 12),
          const Text(
            "구글 캘린더의 휴가 일정을 읽어와 연차를 계산하고,\n입사일 등 설정은 계정에 저장되어 앱을 다시 설치해도 그대로 복원됩니다.",
            style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed:
                  _restoring ? null : () => _restoreFromAccount(silent: false),
              icon: _restoring
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.login),
              label: Text(_restoring ? "확인하는 중..." : "구글 계정으로 시작하기",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2단계: 계정에 백업이 없을 때만 보이는 입사일/연차 입력 화면
  Widget _buildFormStep() {
    return SingleChildScrollView(
      // 키보드 대응
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("처음 오셨네요! 👋\n정보를 입력하면 자동으로 계산됩니다.",
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, height: 1.4)),
          if (_email != null) ...[
            const SizedBox(height: 8),
            Text("$_email 계정에 저장된 설정이 없어 새로 설정합니다.",
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          const SizedBox(height: 32),

          const Text("1. 본인의 입사일을 선택하세요",
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey)),
          const SizedBox(height: 12),
          _buildSelectionTile(
            title: "입사일",
            subtitle: _entryDate != null
                ? "${_entryDate!.year}.${_entryDate!.month}.${_entryDate!.day}"
                : "날짜를 선택하세요",
            icon: Icons.auto_awesome_outlined,
            iconColor: const Color(0xFF764BA2),
            onTap: _pickEntryDate,
          ),

          const SizedBox(height: 32),

          const Text("2. 총 연차 개수 (자동 계산 후 수정 가능)",
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey)),
          const SizedBox(height: 12),
          // ★ 수정 가능하도록 다시 TextField를 사용한 Tile로 변경
          _buildEditableResultTile(),

          const SizedBox(height: 32),

          const Text("3. 연차 초기화 날짜 (입사일 기준 자동 세팅)",
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey)),
          const SizedBox(height: 12),
          _buildSelectionTile(
            title: "연차 초기화 날짜",
            subtitle:
                "${_resetDate.year}.${_resetDate.month}.${_resetDate.day}",
            icon: Icons.calendar_today,
            iconColor: const Color(0xFFFFB74D),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _resetDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _resetDate = picked);
            },
          ),

          const SizedBox(height: 40),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () async {
                final total = double.tryParse(_totalController.text) ?? 15.0;
                // 저장되면 MyApp 이 leaveStateProvider 변화를 보고 홈 화면으로 바꿔 주므로 따로 이동하지 않는다
                // ('/home' 라우트가 없어 pushReplacementNamed 는 예외만 냈음)
                await ref
                    .read(leaveStateProvider.notifier)
                    .saveSettings(total, _resetDate, _entryDate);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF764BA2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text("설정 완료",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  // ★ 총 연차를 직접 수정할 수 있는 타일 UI
  Widget _buildEditableResultTile() {
    bool isCalculated = _entryDate != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isCalculated ? const Color(0xFFF3E5F5) : Colors.grey.shade100,
        border: Border.all(
            color:
                isCalculated ? const Color(0xFFE1BEE7) : Colors.grey.shade300,
            width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: Colors.deepPurpleAccent.withOpacity(0.1),
              radius: 24,
              child: const Icon(Icons.beach_access_outlined,
                  color: Colors.deepPurpleAccent)),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _totalController,
              decoration: const InputDecoration(
                labelText: "총 연차 개수",
                border: InputBorder.none,
                labelStyle: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrangeAccent),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const Text("개",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSelectionTile(
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color iconColor,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            CircleAvatar(
                backgroundColor: iconColor.withOpacity(0.1),
                radius: 24,
                child: Icon(icon, color: iconColor, size: 24)),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style:
                        const TextStyle(fontSize: 14, color: Colors.black87)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }
}
