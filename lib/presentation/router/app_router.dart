import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../logic/auth/auth_bloc.dart';
import '../../data/models/user_model.dart';
import '../pages/login_screen.dart';
import '../pages/accountant_dashboard.dart';
import '../pages/pro_dashboard.dart';
import '../pages/pro_add_rider_page.dart';
import '../pages/riders_page.dart';
import '../widgets/dashboard_layout.dart';
import '../pages/expenses_page.dart';
import '../pages/payroll_page.dart';
import '../pages/payroll_draft_screen.dart';
import '../pages/payroll_success_page.dart';
import '../pages/payslip_list_page.dart';
import '../pages/payslip_pdf_view.dart';
import '../pages/fines_page.dart';
import '../pages/drawer_page.dart';
import '../pages/actions_page.dart';
import '../pages/reports_page.dart';
import '../pages/fleet_screen.dart';
import '../pages/ledger_page.dart';
import '../pages/audit_log_page.dart';
import '../pages/journals_page.dart';
import '../pages/vendor_supplier_management_page.dart';
import '../pages/profile_page.dart';

import '../pages/rider_statement_page.dart';
import '../pages/alias_resolution_screen.dart';
import '../pages/rider_completion_form.dart';
import '../pages/rider_approval_screen.dart';
import '../pages/payslip_preview_screen.dart';
import '../../data/models/payroll_model.dart';

class AppRouter {
  final AuthBloc authBloc;

  AppRouter(this.authBloc);

  late final GoRouter router = GoRouter(
    initialLocation: '/login',
    refreshListenable: StreamListenable(authBloc.stream),
    redirect: (BuildContext context, GoRouterState state) {
      final authState = authBloc.state;
      final isLoggingIn = state.uri.toString() == '/login';

      if (authState is AuthUnauthenticated) {
        return isLoggingIn ? null : '/login';
      }

      if (authState is AuthAuthenticated) {
        if (isLoggingIn) {
          if (authState.user.role == UserRole.accountant) {
            return '/accountant-dashboard';
          } else {
            return '/pro-dashboard';
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

      // Unified Shell for Accountant and PRO
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return DashboardLayout(navigationShell: navigationShell);
        },
        branches: [
          // Branch 0: Accountant Dashboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/accountant-dashboard',
                builder: (context, state) => const AccountantDashboard(),
                routes: [
                  GoRoute(
                    path: 'rider-completion',
                    builder: (context, state) {
                      final extra = state.extra as Map<String, dynamic>?;
                      if (extra == null) {
                        return const Scaffold(body: Center(child: Text("Error: Navigation state missing")));
                      }
                      return RiderCompletionForm(
                        riderId: extra['riderId'] as String,
                        actionItemId: extra['actionItemId'] as String,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'rider-approval',
                    builder: (context, state) {
                      final extra = state.extra as Map<String, dynamic>?;
                      if (extra == null) {
                        return const Scaffold(body: Center(child: Text("Error: Navigation state missing")));
                      }
                      return RiderApprovalScreen(
                        requestId: extra['requestId'] as String,
                        actionItemId: extra['actionItemId'] as String,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 1: PRO Dashboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/pro-dashboard',
                builder: (context, state) => const ProDashboard(),
              ),
            ],
          ),
          // Branch 1a: PRO Add Rider
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'pro_add_rider'),
            routes: [
              GoRoute(
                path: '/pro-add-rider',
                builder: (context, state) => const ProAddRiderPage(),
              ),
            ],
          ),
          // Branch 2: Riders
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/riders',
                builder: (context, state) => const RidersPage(),
                routes: [
                  GoRoute(
                    path: 'statement/:id',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      final name = state.uri.queryParameters['name'] ?? 'Rider';
                      return RiderStatementPage(riderId: id, riderName: name);
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 3: Payroll
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/payroll',
                builder: (context, state) => const PayrollPage(),
                routes: [
                  GoRoute(
                    path: 'draft',
                    builder: (context, state) => const PayrollDraftScreen(),
                  ),
                  GoRoute(
                    path: 'success',
                    builder: (context, state) => const PayrollSuccessPage(),
                  ),
                  GoRoute(
                    path: 'payslips/:batchId',
                    builder: (context, state) {
                      final batchId = state.pathParameters['batchId']!;
                      return PayslipListPage(batchId: batchId);
                    },
                  ),
                   GoRoute(
                    path: 'payslip/:id',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return PayslipPdfView(riderId: id);
                    },
                  ),
                  GoRoute(
                    path: 'preview',
                    builder: (context, state) {
                      final payslip = state.extra as PayslipDraftModel;
                      return PayslipPreviewScreen(payslip: payslip);
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 4: Expenses (ExpensesPage)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'expenses'),
            routes: [
              GoRoute(
                path: '/expenses',
                builder: (context, state) {
                  final authState = authBloc.state;
                  final isAccountant =
                      authState is AuthAuthenticated &&
                      authState.user.role == UserRole.accountant;
                  return ExpensesPage(isAccountant: isAccountant);
                },
              ),
            ],
          ),
          // Branch 5: Fines (FinesPage)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'fines'),
            routes: [
              GoRoute(
                path: '/fines',
                builder: (context, state) => const FinesPage(),
              ),
            ],
          ),
          // Branch 6: Ledger (LedgerPage)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ledger',
                builder: (context, state) => const LedgerPage(),
              ),
            ],
          ),
          // Branch 6: Treasury (DrawerPage)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'treasury'),
            routes: [
              GoRoute(
                path: '/drawers',
                builder: (context, state) => const DrawerPage(),
              ),
            ],
          ),
          // Branch 7: Actions (ActionsPage)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'actions'),
            routes: [
              GoRoute(
                path: '/actions',
                builder: (context, state) => const ActionsPage(),
              ),
            ],
          ),
          // Branch 8: Reports (ReportsPage)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'reports'),
            routes: [
              GoRoute(
                path: '/reports',
                builder: (context, state) => const ReportsPage(),
              ),
            ],
          ),
          // Branch 9: Fleet (FleetScreen)
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'fleet'),
            routes: [
              GoRoute(
                path: '/assets',
                builder: (context, state) => const FleetScreen(),
              ),
            ],
          ),
          // Branch 10: Audit Log
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'audit'),
            routes: [
              GoRoute(
                path: '/audit-log',
                builder: (context, state) => const AuditLogPage(),
              ),
            ],
          ),
          // Branch 11: Journals
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'journals'),
            routes: [
              GoRoute(
                path: '/journals',
                builder: (context, state) {
                  final extra = state.extra;
                  String? expenseId;
                  if (extra is String) expenseId = extra;
                  if (extra is Map<String, dynamic>) {
                    expenseId = extra['expenseId'] as String? ?? extra['argumentId'] as String?;
                  }
                  return JournalsPage(highlightExpenseId: expenseId);
                },
              ),
            ],
          ),

          // Branch 14: Vendor & Supplier Management
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'vendor_supplier_mgmt'),
            routes: [
              GoRoute(
                path: '/vendor-supplier-management',
                builder: (context, state) => const VendorSupplierManagementPage(),
              ),
            ],
          ),

          // Branch 15: Profile
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'profile'),
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/alias-resolution/:actionItemId',
        builder: (context, state) {
          final actionItemId = state.pathParameters['actionItemId']!;
          final extra = state.extra as Map<String, dynamic>?;
          return AliasResolutionScreen(
            actionItemId: actionItemId,
            payslipId: extra?['payslipId'],
            platform: extra?['platform'],
            platformRiderId: extra?['platformRiderId'],
            riderNameFromSheet: extra?['riderNameFromSheet'],
            grossSalary: extra?['grossSalary'],
            payrollMonth: extra?['payrollMonth'],
          );
        },
      ),
    ],
  );
}

class StreamListenable extends ChangeNotifier {
  final Stream stream;

  StreamListenable(this.stream) {
    stream.listen((event) => notifyListeners());
  }
}
