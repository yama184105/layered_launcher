import 'package:hive/hive.dart';

part 'app_config.g.dart';

@HiveType(typeId: 0)
class AppConfig extends HiveObject {
  @HiveField(0)
  String packageName;

  @HiveField(1)
  String appName;

  @HiveField(2)
  int floor;

  @HiveField(3)
  bool isEmergency;

  @HiveField(4)
  DateTime? emergencyUntil;

  @HiveField(5)
  bool isPinned;

  @HiveField(6)
  String? customName;

  @HiveField(7)
  String? folderName;

  @HiveField(8)
  bool mindfulDelay;

  @HiveField(9)
  bool folderPinned;

  /// Values: 'top' | 'alphabetical' | 'bottom'. Default 'alphabetical'.
  @HiveField(10)
  String folderPosition;

  /// Underlying default floor saved before a temporary override took
  /// effect. Used to restore [floor] back to the user's normal
  /// placement once [temporaryFloorExpiry] passes. Null when no
  /// override is active.
  @HiveField(11)
  int? permanentFloor;

  /// When the current temporary floor override expires. After this
  /// timestamp, [floor] is restored from [permanentFloor]. Null when
  /// no override is active.
  @HiveField(12)
  DateTime? temporaryFloorExpiry;

  AppConfig({
    required this.packageName,
    required this.appName,
    this.floor = 1,
    this.isEmergency = false,
    this.emergencyUntil,
    this.isPinned = false,
    this.customName,
    this.folderName,
    this.mindfulDelay = false,
    this.folderPinned = false,
    this.folderPosition = 'alphabetical',
    this.permanentFloor,
    this.temporaryFloorExpiry,
  });
}

