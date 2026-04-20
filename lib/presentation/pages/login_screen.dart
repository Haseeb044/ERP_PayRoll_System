import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../data/models/user_model.dart';
import '../../logic/auth/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  UserRole? _selectedRole;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    final selectedRole = _selectedRole;
    if (selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your role before signing in.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
        SignInRequested(
          _emailController.text.trim(),
          _passwordController.text.trim(),
          selectedRole,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      body: Stack(
        children: [
          // Background Layer: Vibrant Gradient & Abstract Shapes
          _buildBackground(size),

          // Content Layer
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isDesktop) _buildWelcomeSide(size),
                  _buildLoginCard(size, isDesktop),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(Size size) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor,
            Color(0xFF056D41),
            AppTheme.secondaryColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Animated or Abstract Shapes could go here
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSide(Size size) {
    return Container(
      width: 400,
      padding: const EdgeInsets.only(right: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              "POWERED BY ANTIGRAVITY",
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Simplify Your Fleet\nManagement.",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Securely manage riders, payroll, and expenses with our state-of-the-art ERP system.",
            style: GoogleFonts.poppins(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard(Size size, bool isDesktop) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state is AuthError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: AppTheme.errorColor,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        color: AppTheme.primaryColor,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    "Welcome Back",
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    "Sign in to your account",
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  _buildTextField(
                    controller: _emailController,
                    hint: "Email address",
                    icon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 24),
                  _buildTextField(
                    controller: _passwordController,
                    hint: "Password",
                    icon: Icons.lock_outline_rounded,
                    isPassword: true,
                    obscureText: !_isPasswordVisible,
                    onToggleVisibility: () {
                      setState(() => _isPasswordVisible = !_isPasswordVisible);
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildRoleSelector(),
                  const SizedBox(height: 40),
                  _buildLoginButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        prefixIcon: Icon(icon, color: Colors.white70, size: 22),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white70,
                  size: 20,
                ),
                onPressed: onToggleVisibility,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppTheme.secondaryColor,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.all(20),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your $hint';
        }
        if (hint == 'Email address' && !value.contains('@')) {
          return 'Please enter a valid email';
        }
        return null;
      },
    );
  }

  Widget _buildRoleSelector() {
    return DropdownButtonFormField<UserRole>(
      initialValue: _selectedRole,
      dropdownColor: const Color(0xFF0F5132),
      iconEnabledColor: Colors.white70,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Select role',
        hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        prefixIcon: const Icon(Icons.badge_outlined, color: Colors.white70),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.secondaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.all(20),
      ),
      items: const [
        DropdownMenuItem(
          value: UserRole.accountant,
          child: Text('Accountant'),
        ),
        DropdownMenuItem(
          value: UserRole.pro,
          child: Text('PRO'),
        ),
      ],
      onChanged: (value) => setState(() => _selectedRole = value),
      validator: (value) {
        if (value == null) return 'Please select your role';
        return null;
      },
    );
  }

  Widget _buildLoginButton() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        final canSubmit = _selectedRole != null;

        return Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [AppTheme.secondaryColor, Color(0xFF198754)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.secondaryColor.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: (isLoading || !canSubmit) ? null : _onLoginPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    "Sign In",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        );
      },
    );
  }

}

