import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'screens/landing_page.dart';
import 'screens/login_page.dart';
import 'screens/dashboard_page.dart';
import 'screens/registration_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PharmaTraceApp());
}

class PharmaTraceApp extends StatefulWidget {
  const PharmaTraceApp({super.key});

  @override
  State<PharmaTraceApp> createState() => _PharmaTraceAppState();
}

class _PharmaTraceAppState extends State<PharmaTraceApp> {
  String _currentRoute = '/';

  void _navigateTo(String route) {
    setState(() {
      _currentRoute = route;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PharmaTrace — Supply Chain Traceability',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: _buildPage(),
    );
  }

  Widget _buildPage() {
    switch (_currentRoute) {
      case '/login':
        return LoginPage(
          onLoginSuccess: () => _navigateTo('/dashboard'),
          onCancel: () => _navigateTo('/'),
          onRegister: () => _navigateTo('/register'),
        );
      case '/register':
        return RegistrationPage(
          onBack: () => _navigateTo('/'),
          onRegistered: () => _navigateTo('/login'),
        );
      case '/dashboard':
        return DashboardPage(
          onLogout: () => _navigateTo('/'),
        );
      case '/':
      default:
        return LandingPage(
          onNavigateLogin: () => _navigateTo('/login'),
          onNavigateDashboard: () => _navigateTo('/dashboard'),
          onNavigateRegister: () => _navigateTo('/register'),
        );
    }
  }
}
