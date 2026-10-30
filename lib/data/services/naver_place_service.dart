import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// 네이버 지역 검색 결과 한 건
class PlaceResult {
  final String name;
  final String roadAddress;
  final String address;
  final String category;
  // WGS84 좌표 (API 는 1e7 배 정수 문자열로 내려줌). 없으면 null
  final double? lat;
  final double? lng;

  const PlaceResult({
    required this.name,
    required this.roadAddress,
    required this.address,
    required this.category,
    this.lat,
    this.lng,
  });

  /// 네이버 지도 앱 딥링크 (좌표가 있으면 장소 핀, 없으면 검색)
  Uri get naverMapAppUri {
    const app = 'appname=com.youngs.leavesync';
    if (lat != null && lng != null) {
      return Uri.parse("nmap://place?lat=$lat&lng=$lng&name=${Uri.encodeComponent(name)}&$app");
    }
    return Uri.parse("nmap://search?query=${Uri.encodeComponent(name)}&$app");
  }

  /// 네이버 지도 앱이 없을 때 쓸 웹 링크
  Uri get naverMapWebUri => Uri.parse("https://map.naver.com/p/search/${Uri.encodeComponent(name)}");

  /// 캘린더 장소 칸에 넣을 문자열 ("장소명, 도로명주소")
  String get calendarLocation {
    final addr = roadAddress.isNotEmpty ? roadAddress : address;
    return addr.isEmpty ? name : "$name, $addr";
  }
}

/// 네이버 개발자센터 "검색 > 지역" API (https://developers.naver.com)
/// .env 에 NAVER_CLIENT_ID / NAVER_CLIENT_SECRET 이 있어야 동작
class NaverPlaceService {
  static String? get _clientId => dotenv.env['NAVER_CLIENT_ID'];
  static String? get _clientSecret => dotenv.env['NAVER_CLIENT_SECRET'];

  /// 키가 설정되어 있는지 (없으면 장소는 직접 입력만 가능)
  static bool get isConfigured =>
      (_clientId ?? '').trim().isNotEmpty && (_clientSecret ?? '').trim().isNotEmpty;

  Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty || !isConfigured) return const [];

    final uri = Uri.https('openapi.naver.com', '/v1/search/local.json', {
      'query': q,
      'display': '5', // API 최대값
      'sort': 'random', // 정확도순
    });

    final res = await http.get(uri, headers: {
      'X-Naver-Client-Id': _clientId!.trim(),
      'X-Naver-Client-Secret': _clientSecret!.trim(),
    });

    if (res.statusCode != 200) {
      debugPrint("⚠️ 네이버 지역 검색 실패 (${res.statusCode}): ${res.body}");
      throw Exception("네이버 검색 오류 (${res.statusCode})");
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final items = (body['items'] as List<dynamic>? ?? []);
    return items.map((raw) {
      final item = raw as Map<String, dynamic>;
      return PlaceResult(
        name: _stripTags(item['title']?.toString() ?? ''),
        roadAddress: item['roadAddress']?.toString() ?? '',
        address: item['address']?.toString() ?? '',
        category: item['category']?.toString() ?? '',
        lng: _coord(item['mapx']),
        lat: _coord(item['mapy']),
      );
    }).toList();
  }

  /// "1265032011" 같은 1e7 배 정수 문자열 → 126.5032011
  double? _coord(dynamic raw) {
    final v = int.tryParse(raw?.toString() ?? '');
    if (v == null || v == 0) return null;
    return v / 10000000.0;
  }

  /// 결과 제목에 포함된 <b></b> 태그와 HTML 엔티티 제거
  String _stripTags(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
