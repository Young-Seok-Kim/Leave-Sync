import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../models/user_setting.dart';
import 'google_calendar_service.dart';

/// 입사일·연차 설정을 구글 드라이브 앱 전용 폴더(appDataFolder)에 백업/복원
///
/// 앱 전용 폴더는 사용자 드라이브 화면에 보이지 않고 이 앱만 읽고 쓸 수 있으며,
/// 계정에 묶여 있어 앱을 지웠다 다시 설치하거나 다른 기기에서 로그인해도 그대로 남아 있다.
class SettingsBackupService {
  static const String fileName = 'leavesync_settings.json';

  final GoogleCalendarService _auth;

  SettingsBackupService(this._auth);

  Future<drive.DriveApi?> _api() async {
    final client = await _auth.authClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  Future<String?> _findFileId(drive.DriveApi api) async {
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$fileName' and trashed = false",
      $fields: 'files(id)',
      pageSize: 1,
    );
    return res.files?.firstOrNull?.id;
  }

  /// 현재 로그인된 계정의 백업을 읽어온다. 없거나 실패하면 null
  Future<UserSetting?> restore() async {
    try {
      final api = await _api();
      if (api == null) return null;
      final id = await _findFileId(api);
      if (id == null) return null;

      final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final bytes = await media.stream.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) return null;
      final setting = UserSetting.fromJson(json);
      debugPrint("☁️ 설정 복원: ${setting?.accountEmail} 입사일 ${setting?.entryDate}");
      return setting;
    } catch (e) {
      debugPrint("⚠️ 설정 복원 실패: $e");
      return null;
    }
  }

  /// 현재 로그인된 계정의 앱 전용 폴더에 설정을 저장한다 (로그인 전이면 조용히 건너뜀)
  Future<bool> backup(UserSetting setting) async {
    try {
      final api = await _api();
      if (api == null) return false;

      final bytes = utf8.encode(jsonEncode(setting.toJson()));
      final media = drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/json');
      final id = await _findFileId(api);
      if (id == null) {
        await api.files.create(
          drive.File()
            ..name = fileName
            ..parents = ['appDataFolder'],
          uploadMedia: media,
        );
      } else {
        await api.files.update(drive.File(), id, uploadMedia: media);
      }
      debugPrint("☁️ 설정 백업 완료 (${setting.accountEmail})");
      return true;
    } catch (e) {
      debugPrint("⚠️ 설정 백업 실패: $e");
      return false;
    }
  }
}
