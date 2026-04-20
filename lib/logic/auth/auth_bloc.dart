import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../utils/user_friendly_error.dart';

// Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object> get props => [];
}

class AppStarted extends AuthEvent {}

class SignInRequested extends AuthEvent {
  final String email;
  final String password;
  final UserRole expectedRole;

  const SignInRequested(this.email, this.password, this.expectedRole);

  @override
  List<Object> get props => [email, password, expectedRole];
}

class SignOutRequested extends AuthEvent {}

class UserActivityDetected extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final UserModel user;

  const AuthAuthenticated(this.user);

  @override
  List<Object> get props => [user];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object> get props => [message];
}

// Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  Timer? _inactivityTimer;
  static const Duration _idleTimeout = Duration(minutes: 30);

  AuthBloc({required AuthRepository authRepository})
    : _authRepository = authRepository,
      super(AuthInitial()) {
    on<AppStarted>(_onAppStarted);
    on<SignInRequested>(_onSignInRequested);
    on<SignOutRequested>(_onSignOutRequested);
    on<UserActivityDetected>(_onUserActivityDetected);
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_idleTimeout, () {
      add(SignOutRequested());
    });
  }

  void _stopInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  Future<void> _onAppStarted(AppStarted event, Emitter<AuthState> emit) async {
    try {
      final isSignedIn = _authRepository.isSignedIn;
      if (isSignedIn) {
        final userProfile = await _authRepository.getUserProfile();
        if (userProfile != null) {
          emit(AuthAuthenticated(userProfile));
          _resetInactivityTimer();
        } else {
          // Profile missing: treat as unauthenticated and require explicit login.
          emit(AuthUnauthenticated());
          _stopInactivityTimer();
        }
      } else {
        emit(AuthUnauthenticated());
        _stopInactivityTimer();
      }
    } catch (_) {
      // Startup auth/profile checks failed; keep app on login without extra signout retries.
      emit(AuthUnauthenticated());
      _stopInactivityTimer();
    }
  }

  Future<void> _onSignInRequested(
    SignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.signIn(event.email, event.password);
      final userProfile = await _authRepository.getUserProfile();

      if (userProfile != null) {
        if (userProfile.role != event.expectedRole) {
          await _authRepository.signOut();
          emit(
            AuthError(
              'Selected role does not match this account. Please choose ${userProfile.role.name.toUpperCase()} and try again.',
            ),
          );
          _stopInactivityTimer();
          return;
        }
        emit(AuthAuthenticated(userProfile));
        _resetInactivityTimer();
      } else {
        emit(const AuthError("User profile not found"));
        // Optionally sign out if profile is missing
        await _authRepository.signOut();
        _stopInactivityTimer();
      }
    } catch (e) {
      emit(AuthError(toUserFriendlyError(e)));
      _stopInactivityTimer();
    }
  }

  Future<void> _onSignOutRequested(
    SignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.signOut();
    emit(AuthUnauthenticated());
    _stopInactivityTimer();
  }

  Future<void> _onUserActivityDetected(
    UserActivityDetected event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthAuthenticated) {
      _resetInactivityTimer();
    }
  }

  @override
  Future<void> close() {
    _stopInactivityTimer();
    return super.close();
  }
}
