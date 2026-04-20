import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_theme.dart';
import 'core/supabase_config.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/payroll_repository.dart';
import 'data/repositories/supabase_payroll_repository.dart';
import 'data/repositories/journal_repository.dart';
import 'data/repositories/supabase_journal_repository.dart';
import 'data/repositories/journal_template_repository.dart';
import 'data/repositories/supabase_journal_template_repository.dart';
import 'data/repositories/audit_log_repository.dart';
import 'data/repositories/supabase_audit_log_repository.dart';
import 'data/repositories/vehicle_repository.dart';
import 'data/repositories/supabase_vehicle_repository.dart';
import 'data/repositories/report_repository.dart';
import 'data/repositories/supabase_report_repository.dart';
import 'data/repositories/ledger_repository.dart';
import 'data/repositories/supabase_ledger_repository.dart';
import 'data/repositories/rider_repository.dart';
import 'data/repositories/supabase_rider_repository.dart';
import 'data/repositories/fines_repository.dart';
import 'data/repositories/supabase_fines_repository.dart';
import 'data/repositories/drawer_repository.dart';
import 'data/repositories/supabase_drawer_repository.dart';
import 'data/repositories/action_repository.dart';
import 'data/repositories/supabase_action_repository.dart';
import 'data/repositories/expense_repository.dart';
import 'data/repositories/supabase_expense_repository.dart';
import 'logic/auth/auth_bloc.dart';
import 'logic/riders/riders_bloc.dart';
import 'logic/financial/journal_bloc.dart';
import 'logic/financial/expense_bloc.dart';
import 'logic/payroll/payroll_bloc.dart';
import 'logic/drawers/drawer_bloc.dart';
import 'logic/actions/action_bloc.dart';
import 'logic/fines/fines_bloc.dart';
import 'logic/reports/report_bloc.dart';
import 'logic/financial/ledger_bloc.dart';
import 'logic/financial/audit_log_bloc.dart';
import 'logic/financial/journal_template_bloc.dart';
import 'presentation/router/app_router.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  await runZonedGuarded(() async {
    await _bootstrapApp();
  }, (error, stackTrace) {
    debugPrint('Uncaught zone error: $error');
    debugPrintStack(stackTrace: stackTrace);
  });
}

Future<void> _bootstrapApp() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter framework error: ${details.exception}');
  };

  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher uncaught error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: FlutterAuthClientOptions(
      autoRefreshToken: !isDesktop,
    ),
  );

  // Enforce manual login on desktop runs and clear any stale persisted session.
  if (isDesktop) {
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
    } catch (_) {
      // Ignore startup sign-out failures; app will continue to login screen.
    }
  }

  final authRepository = AuthRepository();
  
  // AppRouter needs AuthBloc
  final authBloc = AuthBloc(authRepository: authRepository);
  final appRouter = AppRouter(authBloc);

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider<VehicleRepository>(
          create: (_) => SupabaseVehicleRepository(),
        ),
        RepositoryProvider<JournalTemplateRepository>(
          create: (_) => SupabaseJournalTemplateRepository(),
        ),
        RepositoryProvider<AuditLogRepository>(
          create: (_) => SupabaseAuditLogRepository(),
        ),
        RepositoryProvider<ReportRepository>(
          create: (_) => SupabaseReportRepository(),
        ),
        RepositoryProvider<LedgerRepository>(
          create: (_) => SupabaseLedgerRepository(),
        ),
        RepositoryProvider<RiderRepository>(
          create: (_) => SupabaseRiderRepository(),
        ),
        RepositoryProvider<FinesRepository>(
          create: (_) => SupabaseFinesRepository(),
        ),
        RepositoryProvider<PayrollRepository>(
          create: (_) => SupabasePayrollRepository(),
        ),
        RepositoryProvider<JournalRepository>(
          create: (_) => SupabaseJournalRepository(),
        ),
        RepositoryProvider<ExpenseRepository>(
          create: (_) => SupabaseExpenseRepository(),
        ),
        RepositoryProvider<DrawerRepository>(
          create: (_) => SupabaseDrawerRepository(),
        ),
        RepositoryProvider<ActionRepository>(
          create: (_) => SupabaseActionRepository(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(
            value: authBloc..add(AppStarted()),
          ),
          BlocProvider<RidersBloc>(
            create: (context) => RidersBloc(
              context.read<RiderRepository>(),
            )..add(LoadRiders()),
          ),
          BlocProvider<FinesBloc>(
            create: (context) => FinesBloc(
              context.read<FinesRepository>(),
              context.read<RiderRepository>(),
            )..add(LoadFines()),
          ),
          BlocProvider<PayrollBloc>(
            create: (context) => PayrollBloc(
              context.read<PayrollRepository>(),
              context.read<RiderRepository>(),
            )..add(LoadPayrollHistory()),
          ),
          BlocProvider<DrawerBloc>(
            create: (context) => DrawerBloc(
              context.read<DrawerRepository>(),
              context.read<JournalRepository>(),
            )..add(const LoadDrawers()),
          ),
          BlocProvider<ExpenseBloc>(
            create: (context) => ExpenseBloc(
              context.read<ExpenseRepository>(),
            )..add(const LoadExpenses()),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ActionBloc>(
                create: (context) => ActionBloc(
                  repository: context.read<ActionRepository>(),
                  finesBloc: context.read<FinesBloc>(),
                  expenseBloc: context.read<ExpenseBloc>(),
                  authBloc: context.read<AuthBloc>(),
                ),
            ),
            BlocProvider<JournalBloc>(
              create: (context) => JournalBloc(
                context.read<JournalRepository>(),
                drawerBloc: context.read<DrawerBloc>(),
                actionBloc: context.read<ActionBloc>(),
                expenseBloc: context.read<ExpenseBloc>(),
              ),
            ),
            BlocProvider<ReportBloc>(
              create: (context) => ReportBloc(context.read<ReportRepository>()),
            ),
            BlocProvider<LedgerBloc>(
              create: (context) => LedgerBloc(context.read<LedgerRepository>()),
            ),
            BlocProvider<AuditLogBloc>(
              create: (context) => AuditLogBloc(context.read<AuditLogRepository>()),
            ),
            BlocProvider<JournalTemplateBloc>(
              create: (context) => JournalTemplateBloc(
                context.read<JournalTemplateRepository>(),
              )..add(LoadTemplates()),
            ),
          ],
          child: MyApp(appRouter: appRouter),
        ),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final AppRouter appRouter;
  const MyApp({super.key, required this.appRouter});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        context.read<AuthBloc>().add(UserActivityDetected());
      },
      child: MaterialApp.router(
        title: 'Rider Payroll ERP',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: appRouter.router,
      ),
    );
  }
}
