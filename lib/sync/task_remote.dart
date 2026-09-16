import 'package:supabase_flutter/supabase_flutter.dart';

/// Server boundary for tasks. The interface keeps `SyncEngine` unit-testable
/// with an in-memory fake; production uses Supabase PostgREST against the
/// same `public.tasks` table + RLS as the native app.
abstract class TaskRemote {
  /// Upsert rows by PK. Returns the rows the server stored.
  Future<List<Map<String, dynamic>>> upsert(
      List<Map<String, dynamic>> rows);

  /// All rows for [userId], newest first. Mirrors native pull ordering.
  Future<List<Map<String, dynamic>>> fetchAll(String userId);

  /// Hard-deletes rows by PK. No-op when [ids] is empty. Requires an RLS
  /// DELETE policy letting users delete their own rows.
  Future<void> deleteByIds(Set<String> ids);
}

class SupabaseTaskRemote implements TaskRemote {
  SupabaseTaskRemote({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const table = 'tasks';

  @override
  Future<List<Map<String, dynamic>>> upsert(
      List<Map<String, dynamic>> rows) async {
    final res = await _client.from(table).upsert(rows).select();
    return List<Map<String, dynamic>>.from(res as List);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String userId) async {
    final res = await _client
        .from(table)
        .select()
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  @override
  Future<void> deleteByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    await _client.from(table).delete().inFilter('id', ids.toList());
  }
}
