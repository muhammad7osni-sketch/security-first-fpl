/// Mirrors a row in the `users` table (schema.sql), which wraps
/// Supabase's `auth.users` with app-specific fields — notably
/// `fplManagerId`, the public FPL manager number the user links (a
/// public identifier, never a credential — plan section 0).
class AppUser {
  final String id; // users.id (uuid)
  final String authUserId; // auth.users.id
  final String email;
  final String? displayName;
  final int? fplManagerId;

  const AppUser({
    required this.id,
    required this.authUserId,
    required this.email,
    this.displayName,
    this.fplManagerId,
  });

  bool get hasLinkedFplAccount => fplManagerId != null;

  factory AppUser.fromSupabaseRow(Map<String, dynamic> row) {
    return AppUser(
      id: row['id'] as String,
      authUserId: row['auth_user_id'] as String,
      email: row['email'] as String,
      displayName: row['display_name'] as String?,
      fplManagerId: row['fpl_manager_id'] as int?,
    );
  }
}
