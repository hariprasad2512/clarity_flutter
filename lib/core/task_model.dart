import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

/// Filter tabs. Mirrors native `TaskFilter` (SidebarView.swift).
enum TaskFilter {
  today('Today'),
  inbox('Inbox'),
  done('Done');

  const TaskFilter(this.label);
  final String label;
}

/// Local task. Mirrors native `TodoTask` property-for-property
/// (Task.swift) plus the §3 wire contract (`public.tasks`).
///
/// Hive box key = [id]. `needsSync` marks rows not yet pushed (Phase 3).
class TodoTask extends HiveObject {
  TodoTask({
    required this.id,
    required this.title,
    this.dueDate,
    this.isCompleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.needsSync = true,
  });

  /// Permanent client-generated UUID — also the Supabase PK (offline-safe).
  String id;
  String title;
  DateTime? dueDate;
  bool isCompleted;
  DateTime createdAt;

  /// Last local mutation time. Drives last-write-wins sync + `updated_at`.
  DateTime updatedAt;

  /// True when local changes haven't been pushed to Supabase yet.
  bool needsSync;

  factory TodoTask.create({required String title, DateTime? dueDate}) {
    final now = DateTime.now();
    return TodoTask(
      id: const Uuid().v4(),
      title: title,
      dueDate: dueDate,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Call after any local mutation so sync picks it up.
  void touch() {
    updatedAt = DateTime.now();
    needsSync = true;
  }

  /// Display sort: earliest due first, undated after dated,
  /// ties broken by creation time. Mirrors `sortForDisplay`.
  static int sortForDisplay(TodoTask a, TodoTask b) {
    final ad = a.dueDate, bd = b.dueDate;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
      return a.createdAt.compareTo(b.createdAt);
    }
    if (ad == null && bd == null) return a.createdAt.compareTo(b.createdAt);
    return ad != null ? -1 : 1;
  }

  bool get isDueTodayOrOverdue {
    final due = dueDate;
    if (due == null || isCompleted) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due.year, due.month, due.day);
    return !day.isAfter(today);
  }

  // -- §3 wire mapping (Phase 3 sync; ISO-8601, fractional seconds) --------

  Map<String, dynamic> toServerRow(String userId) => {
        'id': id,
        'user_id': userId,
        'title': title,
        'due_at': dueDate?.toUtc().toIso8601String(),
        'is_completed': isCompleted,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  static DateTime? _parseWireDate(String? s) {
    if (s == null) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  factory TodoTask.fromServerRow(Map<String, dynamic> row) {
    final task = TodoTask(
      id: row['id'] as String,
      title: row['title'] as String,
      dueDate: _parseWireDate(row['due_at'] as String?),
      isCompleted: (row['is_completed'] as bool?) ?? false,
      createdAt:
          _parseWireDate(row['created_at'] as String?) ?? DateTime.now(),
      updatedAt:
          _parseWireDate(row['updated_at'] as String?) ?? DateTime.now(),
      needsSync: false,
    );
    return task;
  }
}

/// Manual Hive adapter — no codegen, works on all 5 platforms incl. web.
class TodoTaskAdapter extends TypeAdapter<TodoTask> {
  @override
  int get typeId => 0;

  @override
  TodoTask read(BinaryReader reader) {
    return TodoTask(
      id: reader.readString(),
      title: reader.readString(),
      dueDate: reader.readBool() ? DateTime.fromMillisecondsSinceEpoch(reader.readInt()) : null,
      isCompleted: reader.readBool(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      needsSync: reader.readBool(),
    );
  }

  @override
  void write(BinaryWriter writer, TodoTask obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeBool(obj.dueDate != null);
    if (obj.dueDate != null) {
      writer.writeInt(obj.dueDate!.millisecondsSinceEpoch);
    }
    writer.writeBool(obj.isCompleted);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeInt(obj.updatedAt.millisecondsSinceEpoch);
    writer.writeBool(obj.needsSync);
  }
}
