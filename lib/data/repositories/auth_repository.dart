import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class AuthRepository {
  SupabaseClient? _supabase;

  AuthRepository({SupabaseClient? supabase}) {
    if (supabase != null) {
      _supabase = supabase;
    } else {
      try {
        _supabase = Supabase.instance.client;
      } catch (_) {
        // Supabase not initialized, running in dummy-only mode
        _supabase = null;
      }
    }
  }

  bool get isSignedIn => _supabase?.auth.currentUser != null;

  /// Signs in with email + password against Supabase Auth (auth.users).
  /// After authentication, the user's profile is fetched from public.profiles
  /// which is auto-populated by the handle_new_user database trigger.
  Future<void> signIn(String email, String password) async {
    if (_supabase == null) {
      throw const AuthException('Supabase not initialized');
    }
    await _supabase!.auth.signInWithPassword(email: email, password: password);
  }

  /// Fetches the user's profile from public.profiles.
  /// The public.profiles table stores the role (PRO / ACCOUNTANT)
  /// while auth.users stores the email + hashed password.
  /// Both tables share the same UUID as primary key.
  Future<UserModel?> getUserProfile() async {
    final authUser = _supabase?.auth.currentUser;
    if (authUser == null || _supabase == null) return null;

    try {
      final response = await _supabase!
          .from('profiles')
          .select()
          .eq('id', authUser.id)
          .single();

      return UserModel.fromJson(response);
    } catch (e) {
      // Fallback: build a partial UserModel from auth data + metadata.
      // The handle_new_user trigger should have created the public.profiles row,
      // but this covers edge cases (e.g. trigger not yet deployed).
      final metaRole = authUser.userMetadata?['role'] as String?;
      return UserModel.fromAuthUser(authUser, metaRole ?? 'PRO');
    }
  }

  // Helper to check current session
  User? get currentUser => _supabase?.auth.currentUser;

  String? get sessionToken {
    return _supabase?.auth.currentSession?.accessToken;
  }

  Stream<AuthState> get authStateChanges =>
      _supabase?.auth.onAuthStateChange ?? const Stream.empty();

  Future<void> signOut() async {
    await _supabase?.auth.signOut();
  }
}
