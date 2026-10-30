import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/naver_place_service.dart';

/// 네이버 지역 검색으로 장소를 고르는 바텀 시트. 선택한 장소 문자열을 반환
Future<String?> showPlaceSearchSheet(BuildContext context, {String initialQuery = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _PlaceSearchSheet(initialQuery: initialQuery),
  );
}

class _PlaceSearchSheet extends StatefulWidget {
  final String initialQuery;
  const _PlaceSearchSheet({required this.initialQuery});

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  static const _brand = Color(0xFF764BA2);

  final _service = NaverPlaceService();
  late final TextEditingController _controller;
  Timer? _debounce;
  List<PlaceResult> _results = const [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty) _search(widget.initialQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _service.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "검색에 실패했습니다. 네트워크 또는 API 키를 확인하세요.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  const Text("장소 검색", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const Text("네이버 지역 검색", style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: "장소명, 상호, 지역을 입력하세요",
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _controller.clear();
                            _search('');
                          },
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _brand, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(child: _buildBody()),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, _controller.text.trim()),
                  child: Text(
                    "검색 결과 없이 '${_controller.text.trim().isEmpty ? '입력한 글자' : _controller.text.trim()}' 그대로 사용",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNaverMap(PlaceResult p) async {
    // 네이버 지도 앱이 있으면 앱으로, 없으면 웹 지도로
    try {
      final opened = await launchUrl(p.naverMapAppUri, mode: LaunchMode.externalNonBrowserApplication);
      if (opened) return;
    } catch (_) {}
    try {
      await launchUrl(p.naverMapWebUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("지도를 열 수 없습니다."), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: _brand)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
      );
    }
    if (!_searched) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text("검색어를 입력하면 결과가 표시됩니다.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }
    if (_results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text("검색 결과가 없습니다.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = _results[i];
        final addr = p.roadAddress.isNotEmpty ? p.roadAddress : p.address;
        return ListTile(
          // 왼쪽 아이콘: 네이버 지도에서 위치 보기 (돌아오면 이 화면이 그대로 유지됨)
          leading: IconButton(
            icon: const Icon(Icons.map_outlined, color: _brand),
            tooltip: "네이버 지도에서 보기",
            onPressed: () => _openNaverMap(p),
          ),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [if (p.category.isNotEmpty) p.category, if (addr.isNotEmpty) addr].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () => Navigator.pop(context, p.calendarLocation),
        );
      },
    );
  }
}
