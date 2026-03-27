// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_setting.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserSettingAdapter extends TypeAdapter<UserSetting> {
  @override
  final int typeId = 0;

  @override
  UserSetting read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserSetting(
      totalLeave: fields[0] as double,
      resetDate: fields[1] as DateTime,
      isFirstRun: fields[2] as bool,
      entryDate: fields[3] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, UserSetting obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.totalLeave)
      ..writeByte(1)
      ..write(obj.resetDate)
      ..writeByte(2)
      ..write(obj.isFirstRun)
      ..writeByte(3)
      ..write(obj.entryDate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSettingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
