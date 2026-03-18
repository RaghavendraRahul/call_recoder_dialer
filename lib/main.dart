import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import 'dart:async';
import 'screens/active_call_screen.dart';
import 'services/permission_service.dart';
import 'services/call_state_service.dart';
import 'services/recording_service.dart';
import 'services/native_call_service.dart';
import 'services/playback_service.dart';
import 'services/theme_service.dart';
import 'screens/dialer_screen.dart';
import 'screens/call_log_screen.dart';
import 'screens/recordings_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'widgets/bouncing_button.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // try {
  //   await FlutterDisplayMode.setHighRefreshRate();
  // } catch (e) {
  //   // Fail silently if platform doesn't support it
  // }

  // No longer blocking main thread with heavy initialization
  // Initialization moved to HomeScreen for staggered execution

  // Enable Edge-to-Edge
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: CallStateService()),
        ChangeNotifierProvider(create: (_) => RecordingService()),
        ChangeNotifierProvider(create: (_) => PlaybackService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          navigatorKey: MyApp.navigatorKey,
          title: 'Call Recorder',
          debugShowCheckedModeBanner: false,
          themeMode: themeService.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 500),
          themeAnimationCurve: Curves.easeInOutCubic,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0F172A), // Deep Slate
              primary: const Color(0xFF4F46E5), // Indigo 600
              secondary: const Color(0xFF0D9488), // Teal 600
              surface: Colors.white,
              surfaceContainer: const Color(0xFFF1F5F9), // Slate 100
              onSurface: const Color(0xFF0F172A), // Slate 900
              outline: const Color(0xFFCBD5E1), // Slate 300
            ),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate 50
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF0F172A),
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF4F46E5),
                  width: 1.5,
                ),
              ),
              hintStyle: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 16,
              ),
              prefixIconColor: const Color(0xFF64748B),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
              color: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4F46E5),
              primary: const Color(0xFF818CF8), // Indigo 400
              secondary: const Color(0xFF2DD4BF), // Teal 400
              surface: const Color(0xFF0F172A), // Slate 900
              surfaceContainer: const Color(0xFF1E293B), // Slate 800
              onSurface: Colors.white,
              brightness: Brightness.dark,
              outline: const Color(0xFF334155), // Slate 700
            ),
            scaffoldBackgroundColor: const Color(0xFF020617), // Slate 950
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF020617),
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF818CF8),
                  width: 1.5,
                ),
              ),
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 16,
              ),
              prefixIconColor: const Color(0xFF94A3B8),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFF334155), width: 1),
              ),
              color: const Color(0xFF0F172A),
            ),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final CallStateService _callStateService = CallStateService();
  final NativeCallService _nativeCallService = NativeCallService();
  final PageController _pageController = PageController();
  bool _hideDefaultPrompt = false;

  final List<bool> _pagesLoaded = [
    true, // Dialer
    true, // Call Log - preloaded for instant access
    false, // Recordings - lazy loaded
  ];

  final List<Widget> _screens = const [
    DialerScreen(),
    CallLogScreen(),
    RecordingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _callStateService.addListener(_onCallStateChanged);
    _nativeCallService.onDefaultDialerResult = (isDefault) {
      if (mounted) {
        _callStateService.updateDefaultDialerStatus(isDefault);
        if (isDefault) {
          setState(() {
            _hideDefaultPrompt = true;
          });
        }
      }
    };
    // Defer heavy initializations until after first frame to avoid startup junk
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staggeredInitialization();
    });
  }

  Future<void> _staggeredInitialization() async {
    // 1. Initialize Call State Service (Critical for call detection)
    await CallStateService().initialize();

    if (mounted) {
      // 2. Check permissions and default dialer role
      await _initializePermissionsAndRole();

      // 3. Check accessibility status
      await _checkAccessibilityStatus();
      
      // Perform initial check to show UI if already in call
      _onCallStateChanged();
    }
  }

  Future<void> _initializePermissionsAndRole() async {
    // Check for default dialer first as it's the most critical "start" action
    await _checkDefaultDialerAndPrompt();
    // Then handle other permissions
    await _checkAndRequestPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Force checking the call state if we resume from the background (e.g., notification tap)
      _onCallStateChanged();
      _checkDefaultDialer();
    }
  }

  Future<void> _checkDefaultDialerAndPrompt() async {
    if (_hideDefaultPrompt) return;

    bool isDefault = await _nativeCallService.isDefaultDialer();
    if (mounted && !isDefault) {
      _showDefaultDialerDialog();
    }
  }

  void _showDefaultDialerDialog() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: Icon(
          Icons.phone_android_rounded,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Set as Default Phone App'),
        content: const Text(
          'To enable incoming call recording and professional dialer features, please set this app as your default phone companion.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _hideDefaultPrompt = true;
              });
              Navigator.pop(context);
            },
            child: Text(
              'NOT NOW',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _nativeCallService.requestDefaultDialer();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('SET AS DEFAULT'),
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actionsPadding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      ),
    );
  }

  Future<void> _checkDefaultDialer() async {
    bool isDefault = await _nativeCallService.isDefaultDialer();
    if (isDefault && mounted) {
      setState(() {
        _hideDefaultPrompt = true;
      });
    }
  }

  Future<void> _checkAccessibilityStatus() async {
    final recordingService = Provider.of<RecordingService>(
      context,
      listen: false,
    );
    await recordingService.updateAccessibilityStatus();
  }

  @override
  void dispose() {
    _callStateService.removeListener(_onCallStateChanged);
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!mounted) return;

    // We rely on the screens themselves to pop when CallState becomes disconnected.
    // main.dart's only job is to push them precisely once per Call cycle.
    
    // Helper to check current route name
    bool isCurrentRoute(String routeName) {
      bool isCurrent = false;
      MyApp.navigatorKey.currentState?.popUntil((route) {
        if (route.settings.name == routeName) {
           isCurrent = true;
        }
        return true; // Never actually pop anything
      });
      return isCurrent;
    }
    
    // Handle Incoming Call Navigation
    if (_callStateService.callState == CallState.ringing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Double check state is still ringing
        if (mounted && _callStateService.callState == CallState.ringing) {
          if (!isCurrentRoute('/incoming')) {
             try {
               MyApp.navigatorKey.currentState?.push(
                 PageRouteBuilder(
                   settings: const RouteSettings(name: '/incoming'),
                   pageBuilder: (context, animation, secondaryAnimation) => const IncomingCallScreen(),
                   transitionsBuilder: (context, animation, secondaryAnimation, child) {
                     return FadeTransition(opacity: animation, child: child);
                   },
                   transitionDuration: const Duration(milliseconds: 300),
                 ),
               );
            } catch (e) {
              print('Error pushing incoming call screen: $e');
            }
          }
        }
      });
      return;
    }

    // Handle Active/Dialing Call Navigation
    // When state goes to dialing or active, push ActiveCallScreen if we haven't already.
    if (_callStateService.isCallActive &&
        (_callStateService.callState == CallState.active ||
         _callStateService.callState == CallState.dialing)) {
         
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _callStateService.isCallActive) {
          if (!isCurrentRoute('/active')) {
             try {
               // First, pop the incoming screen if we are upgrading to active
               if (isCurrentRoute('/incoming')) {
                   MyApp.navigatorKey.currentState?.pop();
               }
               MyApp.navigatorKey.currentState?.push(
                 PageRouteBuilder(
                   settings: const RouteSettings(name: '/active'),
                   pageBuilder: (context, animation, secondaryAnimation) => const ActiveCallScreen(),
                   transitionsBuilder: (context, animation, secondaryAnimation, child) {
                     return FadeTransition(opacity: animation, child: child);
                   },
                   transitionDuration: const Duration(milliseconds: 300),
                 ),
               );
            } catch (e) {
              print('Error pushing active call screen: $e');
            }
          }
        }
      });
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    final granted = await PermissionService.areAllPermissionsGranted();

    if (!granted) {
      final permissions = await PermissionService.requestAllPermissions();
      final allGranted = permissions.values.every((v) => v == true);

      if (!allGranted && mounted) {
        _showPermissionDialog();
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'This app requires phone, microphone, and contacts permissions to function properly. '
          'Please grant all permissions in the app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _checkAndRequestPermissions();
            },
            child: const Text('Try Again'),
          ),
          TextButton(
            onPressed: () {
              PermissionService.openSystemSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          _onItemTapped(0);
        } else {
          // If already on dialer, minimize app or handle naturally
          SystemNavigator.pop();
        }
      },
      child: Builder(
        builder: (context) {
          final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
          
          final navBarWidget = Container(
            margin: isLandscape 
                ? const EdgeInsets.only(left: 24, top: 24, bottom: 24)
                : const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            width: isLandscape ? 72 : null,
            height: isLandscape ? null : 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(   
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Flex(
                  direction: isLandscape ? Axis.vertical : Axis.horizontal,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(0, Icons.dialpad_rounded, 'Dialer'),
                    _buildNavItem(1, Icons.history_rounded, 'Recent'),
                    _buildNavItem(2, Icons.mic_rounded, 'Records'),
                  ],
                ),
              ),
            ),
          );

          final pageViewWidget = PageView.builder(
            controller: _pageController,
            itemCount: _screens.length,
            physics: const ClampingScrollPhysics(),
            allowImplicitScrolling: true,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _pagesLoaded[index] = true;
              });
            },
            itemBuilder: (context, index) {
              if (!_pagesLoaded[index]) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              return _screens[index];
            },
          );

          return Scaffold(
            resizeToAvoidBottomInset: false, // Ensures keyboard pushing doesn't crush the whole nav if not needed
            extendBody: false,
            body: isLandscape 
                ? SafeArea(
                    child: Row(
                      children: [
                        navBarWidget,
                        Expanded(child: pageViewWidget),
                      ],
                    ),
                  )
                : pageViewWidget,
            bottomNavigationBar: isLandscape ? null : SafeArea(child: navBarWidget),
          );
        }
      ),
    );
  }

  void _onItemTapped(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      _pagesLoaded[index] = true;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return BouncingButton(
      onTap: () => _onItemTapped(index),
      scaleFactor: 0.92,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
