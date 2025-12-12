import 'package:hive/hive.dart';

@HiveType(typeId: 100) // Same as adapter's typeId
class IncomeSchedule extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String title;
  @HiveField(2)
  double amount;
  @HiveField(3)
  String recurrenceRule; // e.g., 'monthly_1st', 'weekly_mon'
  @HiveField(4)
  DateTime nextDueDate;
  @HiveField(5)
  bool isFavorite;
  @HiveField(6)
  DateTime? lastRemindedAt;
  @HiveField(7)
  int order; // For manual sorting

  IncomeSchedule({
    required this.id,
    required this.title,
    required this.amount,
    required this.recurrenceRule,
    required this.nextDueDate,
    this.isFavorite = false,
    this.lastRemindedAt,
    this.order = 0,
  });
}

class IncomeScheduleAdapter extends TypeAdapter<IncomeSchedule> {
  @override
  final int typeId = 100; // Unique ID for this type (Safe)

  @override
  IncomeSchedule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return IncomeSchedule(
      id: fields[0] as String,
      title: fields[1] as String,
      amount: fields[2] as double,
      recurrenceRule: fields[3] as String,
      nextDueDate: fields[4] as DateTime,
      isFavorite: fields[5] as bool,
      lastRemindedAt: fields[6] as DateTime?,
      order: fields.containsKey(7) ? fields[7] as int : 0,
    );
  }

  @override
  void write(BinaryWriter writer, IncomeSchedule obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.recurrenceRule)
      ..writeByte(4)
      ..write(obj.nextDueDate)
      ..writeByte(5)
      ..write(obj.isFavorite)
      ..writeByte(6)
      ..write(obj.lastRemindedAt)
      ..writeByte(7)
      ..write(obj.order);
  }
}
