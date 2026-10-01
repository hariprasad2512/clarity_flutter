/// Google identity display for the sidebar footer. Port of native
/// account display (SidebarView footer: name + photo, not bare email).
///
/// Pure by design (plain maps, no Supabase types) so the precedence chain
/// is unit-testable. Supabase maps Google claims into `userMetadata`
/// with these keys (`full_name`/`avatar_url` standard; `name`/`picture`
/// fallbacks seen on some provider mappings).
class AccountProfile {
  const AccountProfile._();

  /// Display name: full name → given + family → email prefix → email →
  /// 'Local only'. Never empty.
  static String displayName({
    Map<String, dynamic>? metadata,
    String? email,
  }) {
    final meta = metadata ?? const {};
    String norm(Object? v) => (v is String ? v : '').trim();
    final full = norm(meta['full_name']);
    if (full.isNotEmpty) return full;
    final name = norm(meta['name']);
    if (name.isNotEmpty) return name;
    final given = norm(meta['given_name'] ?? meta['first_name']);
    final family = norm(meta['family_name'] ?? meta['last_name']);
    final combined = '$given $family'.trim();
    if (combined.isNotEmpty) return combined;
    final mail = (email ?? '').trim();
    if (mail.isNotEmpty) {
      final prefix = mail.split('@').first.trim();
      if (prefix.isNotEmpty) return prefix;
      return mail;
    }
    return 'Local only';
  }

  /// Photo URL: `avatar_url` → `picture`. Null when signed out or the
  /// provider sent no photo (caller falls back to the initial avatar).
  static String? photoUrl(Map<String, dynamic>? metadata) {
    final meta = metadata ?? const {};
    for (final key in ['avatar_url', 'picture']) {
      final v = meta[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// Avatar fallback letter from the display name (existing behavior).
  static String initial(String displayName) {
    final name = displayName.trim();
    if (name.isEmpty) return '○';
    return name[0].toUpperCase();
  }
}
