// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppConfigAdapter extends TypeAdapter<AppConfig> {
  @override
  final int typeId = 0;

  @override
  AppConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppConfig(
      packageName: fields[0] as String,
      appName: fields[1] as String,
      floor: fields[2] as int,
      isEmergency: fields[3] as bool,
      emergencyUntil: fields[4] as DateTime?,
      isPinned: fields[5] as bool,
      customName: fields[6] as String?,
      folderName: fields[7] as String?,
      mindfulDelay: fields[8] as bool,
      folderPinned: fields[9] as bool,
      folderPosition: fields[10] as String,
      permanentFloor: fields[11] as int?,
      temporaryFloorExpiry: fields[12] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, AppConfig obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.packageName)
      ..writeByte(1)
      ..write(obj.appName)
      ..writeByte(2)
      ..write(obj.floor)
      ..writeByte(3)
      ..write(obj.isEmergency)
      ..writeByte(4)
      ..write(obj.emergencyUntil)
      ..writeByte(5)
      ..write(obj.isPinned)
      ..writeByte(6)
      ..write(obj.customName)
      ..writeByte(7)
      ..write(obj.folderName)
      ..writeByte(8)
      ..write(obj.mindfulDelay)
      ..writeByte(9)
      ..write(obj.folderPinned)
      ..writeByte(10)
      ..write(obj.folderPosition)
      ..writeByte(11)
      ..write(obj.permanentFloor)
      ..writeByte(12)
      ..write(obj.temporaryFloorExpiry);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
