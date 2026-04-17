import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notice_board.dart';
import 'pdf_viewer.dart';
import 'theme_provider.dart';

class AdManager {
  AdManager._private();
  static final AdManager instance = AdManager._private();

  InterstitialAd? _interstitial;
  RewardedAd? _rewardedAd;
  bool _isInterstitialReady = false;
  bool _isRewardedReady = false;
  VoidCallback? _pendingInterstitialCallback;

  void initialize() {
    loadInterstitial();
    loadRewardedAd();
  }

  String get _interstitialAdUnit {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/1033173712';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/3911809640';
    } else {
      return 'ca-app-pub-3940256099942544/1033173712';
    }
  }

  String get _rewardedAdUnit {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/5224354917';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    } else {
      return 'ca-app-pub-3940256099942544/5224354917';
    }
  }

  void loadInterstitial() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _isInterstitialReady = true;
          _interstitial!.setImmersiveMode(true);
          _interstitial!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitial = null;
              _isInterstitialReady = false;
              final cb = _pendingInterstitialCallback;
              _pendingInterstitialCallback = null;
              if (cb != null) cb();
              Future.delayed(const Duration(seconds: 1), loadInterstitial);
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _interstitial = null;
              _isInterstitialReady = false;
              _pendingInterstitialCallback = null;
              Future.delayed(const Duration(seconds: 3), loadInterstitial);
            },
          );
        },
        onAdFailedToLoad: (err) {
          _isInterstitialReady = false;
          Future.delayed(const Duration(seconds: 3), loadInterstitial);
        },
      ),
    );
  }

  void showInterstitial({VoidCallback? onAdClosed}) {
    if (_isInterstitialReady && _interstitial != null) {
      _pendingInterstitialCallback = onAdClosed;
      _interstitial!.show();
    } else {
      if (onAdClosed != null) onAdClosed();
      loadInterstitial();
    }
  }

  void loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _rewardedAdUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedReady = true;
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;
              _isRewardedReady = false;
              Future.delayed(const Duration(seconds: 1), loadRewardedAd);
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _rewardedAd = null;
              _isRewardedReady = false;
              Future.delayed(const Duration(seconds: 3), loadRewardedAd);
            },
          );
        },
        onAdFailedToLoad: (err) {
          _isRewardedReady = false;
          Future.delayed(const Duration(seconds: 3), loadRewardedAd);
        },
      ),
    );
  }

  void showRewarded({void Function(RewardItem)? onEarned}) {
    if (_isRewardedReady && _rewardedAd != null) {
      _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          if (onEarned != null) onEarned(reward);
        },
      );
    } else {
      loadRewardedAd();
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optimise rendering pipeline
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Initialize theme before running app
  await ThemeNotifier.instance.init();

  // Initialise ads after the first frame so the UI renders immediately
  MobileAds.instance.initialize().then((_) {
    AdManager.instance.initialize();
  });

  runApp(const NUResultsApp());
}

// ─── Grading Logic ────────────────────────────────────────────────────────────
String _calculateLetterGrade(double cgpa, int failCount) {
  if (failCount >= 4) return 'FAIL';
  if (cgpa >= 4.00) return 'A+';
  if (cgpa >= 3.75) return 'A';
  if (cgpa >= 3.50) return 'A-';
  if (cgpa >= 3.25) return 'B+';
  if (cgpa >= 3.00) return 'B';
  if (cgpa >= 2.75) return 'B-';
  if (cgpa >= 2.50) return 'C+';
  if (cgpa >= 2.25) return 'C';
  if (cgpa >= 2.00) return 'D';
  if (failCount > 0) return 'F';
  if (cgpa == 0.0) return 'F';
  return 'F';
}

// ─── Design tokens (delegates to AppColors from theme_provider) ─────────────
class _Colors {
  static const primary = AppColors.primary;
  static const gold = AppColors.gold;
  static const heroTop = AppColors.heroTop;
  static const heroBottom = AppColors.heroBottom;
  static Color surface(BuildContext context) =>
      AppColors.surface(Theme.of(context).brightness == Brightness.dark);
  static Color textDark(BuildContext context) =>
      AppColors.textPrimary(Theme.of(context).brightness == Brightness.dark);
}

class NUResultsApp extends StatelessWidget {
  const NUResultsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeNotifier.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NU Results Portal',
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeNotifier.instance.mode,
        home: const _AppOpeningAnimation(child: NUResultsHomePage()),
      ),
    );
  }
}

class _AppOpeningAnimation extends StatefulWidget {
  const _AppOpeningAnimation({required this.child});

  final Widget child;

  @override
  State<_AppOpeningAnimation> createState() => _AppOpeningAnimationState();
}

class _AppOpeningAnimationState extends State<_AppOpeningAnimation>
    with SingleTickerProviderStateMixin {
  static const AssetImage _appIcon = AssetImage('assets/app_icon_cropped.png');

  late final AnimationController _controller;
  late final Animation<double> _iconScale;
  late final Animation<double> _iconOpacity;
  late final Animation<double> _iconFloat;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleOffset;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;
  bool _showHome = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1850),
    );
    _iconScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.72,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 45,
      ),
    ]).animate(_controller);
    _iconOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
    );
    _iconFloat = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.12, 0.58, curve: Curves.easeOutCubic),
      ),
    );
    _titleOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 0.72, curve: Curves.easeOut),
    );
    _titleOffset = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.24, 0.72, curve: Curves.easeOutCubic),
          ),
        );
    _ringScale = Tween<double>(begin: 0.8, end: 1.55).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.62, curve: Curves.easeOutCubic),
      ),
    );
    _ringOpacity = Tween<double>(begin: 0.34, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.08, 0.64, curve: Curves.easeOut),
      ),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _showHome = true;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(_appIcon, context);
    if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _showHome ? widget.child : _buildSplashScreen(context),
    );
  }

  Widget _buildSplashScreen(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.primary;
    final topColor = isDark ? const Color(0xFF071120) : const Color(0xFFF7FAFF);
    final bottomColor = isDark
        ? const Color(0xFF0D2038)
        : const Color(0xFFE4F0FF);
    final surfaceColor = isDark ? const Color(0xFF0F1E32) : Colors.white;
    final textColor = AppColors.textPrimary(isDark);
    final subtitleColor = AppColors.textSecondary(isDark);

    return Scaffold(
      key: const ValueKey('app-opening-animation'),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [topColor, bottomColor],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: -90,
                  right: -60,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -120,
                  left: -50,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                    ),
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 182,
                            height: 182,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Transform.scale(
                                  scale: _ringScale.value,
                                  child: Opacity(
                                    opacity: _ringOpacity.value,
                                    child: Container(
                                      width: 138,
                                      height: 138,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: accent.withValues(alpha: 0.28),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(0, _iconFloat.value),
                                  child: Opacity(
                                    opacity: _iconOpacity.value.clamp(0.0, 1.0),
                                    child: Transform.scale(
                                      scale: _iconScale.value,
                                      child: Container(
                                        width: 118,
                                        height: 118,
                                        decoration: BoxDecoration(
                                          color: surfaceColor,
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: isDark ? 0.28 : 0.12,
                                              ),
                                              blurRadius: 28,
                                              offset: const Offset(0, 16),
                                            ),
                                          ],
                                        ),
                                        padding: const EdgeInsets.all(18),
                                        child: const Image(
                                          image: _appIcon,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          FadeTransition(
                            opacity: _titleOpacity,
                            child: SlideTransition(
                              position: _titleOffset,
                              child: Column(
                                children: [
                                  Text(
                                    'NU Results Portal',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Fast result, notice and resource access for National University students',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.45,
                                      color: subtitleColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: 132,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 5,
                                value: _controller.value.clamp(0.0, 1.0),
                                backgroundColor: accent.withValues(alpha: 0.12),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  accent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum AppSection {
  home,
  archive,
  recent,
  calculator,
  notices,
  admissionPortal,
  // admitCard removed
}

class SearchHistoryEntry {
  const SearchHistoryEntry({
    required this.key,
    required this.url,
    required this.source,
    required this.label,
    required this.timestamp,
    this.studentName = '',
    this.roll = '',
    this.registrationNumber = '',
    this.cgpa = '',
    this.totalPoints = '',
    this.courseCount = 0,
    this.courses = const [],
  });

  final String key;
  final String url;
  final String source;
  final String label;
  final String timestamp;
  final String studentName;
  final String roll;
  final String registrationNumber;
  final String cgpa;
  final String totalPoints;
  final int courseCount;
  final List<ResultCourse> courses;

  Map<String, dynamic> toJson() => {
    'key': key,
    'url': url,
    'source': source,
    'label': label,
    'timestamp': timestamp,
    'studentName': studentName,
    'roll': roll,
    'registrationNumber': registrationNumber,
    'cgpa': cgpa,
    'totalPoints': totalPoints,
    'courseCount': courseCount,
    'courses': courses
        .map(
          (c) => {
            'code': c.code,
            'title': c.title,
            'grade': c.grade,
            'points': c.points,
          },
        )
        .toList(),
  };

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    final coursesJson = (json['courses'] as List?)?.cast<Map>() ?? <Map>[];
    return SearchHistoryEntry(
      key: json['key'] as String? ?? '',
      url: json['url'] as String? ?? '',
      source: json['source'] as String? ?? 'Result',
      label: json['label'] as String? ?? 'Result Summary',
      timestamp: json['timestamp'] as String? ?? '',
      studentName: json['studentName'] as String? ?? '',
      roll: json['roll'] as String? ?? '',
      registrationNumber: json['registrationNumber'] as String? ?? '',
      cgpa: json['cgpa'] as String? ?? '',
      totalPoints: json['totalPoints'] as String? ?? '',
      courseCount: (json['courseCount'] as num?)?.toInt() ?? 0,
      courses: coursesJson
          .map((item) => ResultCourse.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class ResultCourse {
  const ResultCourse({
    required this.code,
    required this.title,
    required this.grade,
    required this.points,
  });

  final String code;
  final String title;
  final String grade;
  final double? points;

  factory ResultCourse.fromJson(Map<String, dynamic> json) {
    return ResultCourse(
      code: json['code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      grade: json['grade'] as String? ?? '',
      points: (json['points'] as num?)?.toDouble(),
    );
  }
}

class ResultStudent {
  const ResultStudent({
    required this.name,
    required this.roll,
    this.registrationNumber = '',
  });

  final String name;
  final String roll;
  final String registrationNumber;

  factory ResultStudent.fromJson(Map<String, dynamic> json) {
    return ResultStudent(
      name: json['name'] as String? ?? '',
      roll: json['roll'] as String? ?? '',
      registrationNumber: json['registrationNumber'] as String? ?? '',
    );
  }
}

class ResultPayload {
  const ResultPayload({required this.student, required this.courses});

  final ResultStudent student;
  final List<ResultCourse> courses;

  // Exclude F (0.00) grades from calculation
  double get totalPoints {
    return courses.fold<double>(0, (sum, item) {
      final points = item.points ?? 0;
      return points > 0 ? sum + points : sum;
    });
  }

  int get countedCourses {
    return courses.where((item) => (item.points ?? 0) > 0).length;
  }

  String get cgpa {
    return countedCourses == 0
        ? '0.00'
        : (totalPoints / countedCourses).toStringAsFixed(2);
  }

  factory ResultPayload.fromJson(Map<String, dynamic> json) {
    final studentJson =
        (json['student'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final coursesJson = (json['courses'] as List?)?.cast<Map>() ?? <Map>[];
    return ResultPayload(
      student: ResultStudent.fromJson(studentJson),
      courses: coursesJson
          .map((item) => ResultCourse.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class NUResultsHomePage extends StatefulWidget {
  const NUResultsHomePage({super.key});

  @override
  State<NUResultsHomePage> createState() => _NUResultsHomePageState();
}

class _NUResultsHomePageState extends State<NUResultsHomePage> {
  // Helper for animated page transitions (fade + slide)
  PageRoute<T> _buildAnimatedRoute<T>({
    required WidgetBuilder builder,
    required String name,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.3, 0);
        const end = Offset.zero;
        const curve = Curves.easeInOutCubic;
        final tween = Tween(
          begin: begin,
          end: end,
        ).chain(CurveTween(curve: curve));
        final fadeTween = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: curve));
        return SlideTransition(
          position: animation.drive(tween),
          child: FadeTransition(
            opacity: animation.drive(fadeTween),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
      settings: RouteSettings(name: name),
    );
  }

  void _openNoticeScreen(Uri source, String title) {
    AdManager.instance.showInterstitial(
      onAdClosed: () {
        if (!mounted) return;
        Navigator.of(context).push(
          _buildAnimatedRoute<void>(
            name: 'notice_$title',
            builder: (ctx) => Scaffold(
              appBar: AppBar(
                title: Text(title),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkCard
                    : _Colors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              body: NoticeBoard(source: source, title: title),
            ),
          ),
        );
      },
    );
  }

  void _openPdfViewer(Uri source, String title) {
    AdManager.instance.showInterstitial(
      onAdClosed: () {
        if (!mounted) return;
        Navigator.of(context).push(
          _buildAnimatedRoute<void>(
            name: 'pdf_$title',
            builder: (ctx) =>
                PdfViewerPage(url: source.toString(), title: title),
          ),
        );
      },
    );
  }

  void _openSyllabusScreen() {
    Navigator.of(context).push(
      _buildAnimatedRoute<void>(
        name: 'syllabus',
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Syllabus'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkCard
                : _Colors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: _SyllabusPage(onOpenNoticeScreen: _openNoticeScreen),
        ),
      ),
    );
  }

  void _openResultsScreen() {
    AdManager.instance.showInterstitial(
      onAdClosed: () {
        if (!mounted) return;
        Navigator.of(context).push(
          _buildAnimatedRoute<void>(
            name: 'results',
            builder: (ctx) => const _ResultsPage(),
          ),
        );
      },
    );
  }

  void _openNoticesScreen() {
    Navigator.of(context).push(
      _buildAnimatedRoute<void>(
        name: 'notices',
        builder: (ctx) => _NoticesPage(
          onOpenNoticeScreen: _openNoticeScreen,
          onOpenPdf: _openPdfViewer,
        ),
      ),
    );
  }

  void _openAdmissionScreen() {
    AdManager.instance.showInterstitial(
      onAdClosed: () {
        if (!mounted) return;
        final uri = Uri.parse('http://app11.nu.edu.bd/');
        try {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
    );
  }

  void _openCalculatorScreen() {
    AdManager.instance.showInterstitial(
      onAdClosed: () {
        if (!mounted) return;
        Navigator.of(context).push(
          _buildAnimatedRoute<void>(
            name: 'calculator',
            builder: (ctx) => Scaffold(
              appBar: AppBar(
                title: const Text('CGPA Calculator'),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkCard
                    : _Colors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              body: const _ManualCGPACalculator(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareApp() async {
    const pkg = 'com.un_results_portal';
    const url = 'https://play.google.com/store/apps/details?id=$pkg';
    try {
      await Share.share(
        'Check out NU Results — National University results portal:\n\n$url',
      );
    } catch (_) {}
  }

  Future<void> _rateApp() async {
    const pkg = 'com.un_results_portal';
    final marketUri = Uri.parse('market://details?id=$pkg');
    final webUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$pkg',
    );
    try {
      if (Platform.isAndroid) {
        if (await canLaunchUrl(marketUri)) {
          await launchUrl(marketUri);
          return;
        }
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else if (Platform.isIOS) {
        final iosUri = Uri.parse('https://apps.apple.com/app/idYOUR_APP_ID');
        await launchUrl(iosUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _openPrivacyPolicyPage() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (ctx) => const _PrivacyPolicyPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _AnimatedHomeScreen(
          onOpenResults: _openResultsScreen,
          onOpenNotices: _openNoticesScreen,
          onOpenCalculator: _openCalculatorScreen,
          onOpenSyllabus: _openSyllabusScreen,
          onOpenAdmission: _openAdmissionScreen,
          onOpenGrading: () => _openPdfViewer(
            Uri.parse(
              'http://results.nu.ac.bd/honours/image/Hon_consolidated_result_rule.pdf',
            ),
            'Grading System',
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.transparent,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  TextButton.icon(
                    onPressed: _shareApp,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                    style: TextButton.styleFrom(
                      foregroundColor: _Colors.primary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openPrivacyPolicyPage,
                    icon: const Icon(Icons.privacy_tip_outlined),
                    label: const Text('Privacy'),
                    style: TextButton.styleFrom(
                      foregroundColor: _Colors.primary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _rateApp,
                    icon: const Icon(Icons.star_rate_rounded),
                    label: const Text('Rate'),
                    style: TextButton.styleFrom(
                      foregroundColor: _Colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 52, child: Center(child: _AppBannerAd())),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Logo Widget
// ═══════════════════════════════════════════════════════════════════════════
class _NULogo extends StatefulWidget {
  const _NULogo({this.size = 80});
  final double size;
  @override
  State<_NULogo> createState() => _NULogoState();
}

class _NULogoState extends State<_NULogo> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) =>
          Transform.scale(scale: _pulse.value, child: child),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF42A5F5), Color(0xFF0D47A1)],
          ),
          boxShadow: [
            BoxShadow(
              color: _Colors.primary.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'NU',
                style: TextStyle(
                  fontSize: widget.size * 0.30,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.5,
                  height: 1.1,
                ),
              ),
              Container(
                width: widget.size * 0.45,
                height: 2,
                decoration: BoxDecoration(
                  color: _Colors.gold,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              Text(
                'BD',
                style: TextStyle(
                  fontSize: widget.size * 0.14,
                  fontWeight: FontWeight.w700,
                  color: _Colors.gold,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Animated Home Screen
// ═══════════════════════════════════════════════════════════════════════════
class _AnimatedHomeScreen extends StatefulWidget {
  const _AnimatedHomeScreen({
    required this.onOpenResults,
    required this.onOpenNotices,
    required this.onOpenCalculator,
    required this.onOpenSyllabus,
    required this.onOpenAdmission,
    required this.onOpenGrading,
  });

  final VoidCallback onOpenResults;
  final VoidCallback onOpenNotices;
  final VoidCallback onOpenCalculator;
  final VoidCallback onOpenSyllabus;
  final VoidCallback onOpenAdmission;
  final VoidCallback onOpenGrading;

  @override
  State<_AnimatedHomeScreen> createState() => _AnimatedHomeScreenState();
}

class _AnimatedHomeScreenState extends State<_AnimatedHomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _headerCtrl;
  late final AnimationController _cardsCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _cardsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut));

    _headerCtrl.forward();
    Future.delayed(
      const Duration(milliseconds: 200),
      () => _cardsCtrl.forward(),
    );
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _cardsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionItem(
        icon: Icons.query_stats_rounded,
        label: 'Results',
        color: const Color(0xFF1565C0),
        accent: const Color(0xFF42A5F5),
        onTap: widget.onOpenResults,
      ),
      _ActionItem(
        icon: Icons.campaign_rounded,
        label: 'Notices',
        color: const Color(0xFFB71C1C),
        accent: const Color(0xFFEF5350),
        onTap: widget.onOpenNotices,
      ),
      _ActionItem(
        icon: Icons.auto_graph_rounded,
        label: 'CGPA\nCalculator',
        color: const Color(0xFF6A1B9A),
        accent: const Color(0xFFAB47BC),
        onTap: widget.onOpenCalculator,
      ),
      _ActionItem(
        icon: Icons.local_library_rounded,
        label: 'Syllabus',
        color: const Color(0xFF0A7E3A),
        accent: const Color(0xFF3EC47F),
        onTap: widget.onOpenSyllabus,
      ),
      _ActionItem(
        icon: Icons.rule_rounded,
        label: 'Grading\nSystem',
        color: const Color(0xFF283593),
        accent: const Color(0xFF536DFE),
        onTap: widget.onOpenGrading,
      ),
      _ActionItem(
        icon: Icons.travel_explore_rounded,
        label: 'Admission\nPortal',
        color: const Color(0xFF0D47A1),
        accent: const Color(0xFF42A5F5),
        onTap: widget.onOpenAdmission,
      ),
      // Admit Card removed
    ];

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(color: _Colors.surface(context)),
          child: CustomScrollView(
            slivers: [
              // ── Hero Header ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _headerFade,
                  child: SlideTransition(
                    position: _headerSlide,
                    child: Stack(children: [_HeroHeader()]),
                  ),
                ),
              ),
              // ── Section Label ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Text(
                    'Quick Access',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _Colors.textDark(context),
                    ),
                  ),
                ),
              ),
              // ── Action Grid ──────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = actions[index];
                    final delay = index * 80;
                    return _AnimatedCard(
                      controller: _cardsCtrl,
                      delay: delay,
                      child: _ActionGridCard(item: item),
                    );
                  }, childCount: actions.length),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.25,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Animated Card wrapper ───────────────────────────────────────────────────
class _AnimatedCard extends StatelessWidget {
  const _AnimatedCard({
    required this.controller,
    required this.delay,
    required this.child,
  });
  final AnimationController controller;
  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (delay / 1000).clamp(0.0, 0.8);
    final end = (start + 0.5).clamp(0.0, 1.0);
    final fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
    );
    final slide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: controller,
            curve: Interval(start, end, curve: Curves.easeOut),
          ),
        );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

// ─── Hero header (logo + title + theme toggle) ──────────────────────────────
class _HeroHeader extends StatefulWidget {
  @override
  State<_HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<_HeroHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _themeIconCtrl;

  @override
  void initState() {
    super.initState();
    _themeIconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    if (ThemeNotifier.instance.isDark) _themeIconCtrl.value = 1.0;
  }

  @override
  void dispose() {
    _themeIconCtrl.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    ThemeNotifier.instance.toggle();
    if (ThemeNotifier.instance.isDark) {
      _themeIconCtrl.forward();
    } else {
      _themeIconCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF0A1628), const Color(0xFF132040)]
              : [_Colors.heroTop, _Colors.heroBottom],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: Column(
            children: [
              // Theme toggle button
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: _toggleTheme,
                  child: AnimatedBuilder(
                    animation: _themeIconCtrl,
                    builder: (context, child) => Transform.rotate(
                      angle: _themeIconCtrl.value * 3.14159,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(
                          isDark
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          color: isDark
                              ? const Color(0xFFFDE68A)
                              : Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const _NULogo(size: 88),
              const SizedBox(height: 20),
              const Text(
                'National University',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Results & Notices Portal',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.8),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Action grid card ─────────────────────────────────────────────────────────
class _ActionItem {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color accent;
  final VoidCallback onTap;
}

class _ActionGridCard extends StatefulWidget {
  const _ActionGridCard({required this.item});
  final _ActionItem item;

  @override
  State<_ActionGridCard> createState() => _ActionGridCardState();
}

class _ActionGridCardState extends State<_ActionGridCard>
    with TickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _iconPulse;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.94,
    ).animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeIn));
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _iconPulse = Tween<double>(
      begin: 0.92,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    _shimmerCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTapDown: (_) => _pressCtrl.forward(),
        onTapUp: (_) {
          _pressCtrl.reverse();
          widget.item.onTap();
        },
        onTapCancel: () => _pressCtrl.reverse(),
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            final glow = 0.25 + 0.15 * _pulseCtrl.value;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.0 + 0.3 * _pulseCtrl.value, -1.0),
                  end: Alignment(1.0, 1.0 - 0.3 * _pulseCtrl.value),
                  colors: [widget.item.color, widget.item.accent],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.item.accent.withValues(alpha: glow),
                    blurRadius: 14 + 8 * _pulseCtrl.value,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Shimmer sweep
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _shimmerCtrl,
                      builder: (context, _) {
                        final dx = _shimmerCtrl.value * 3 - 1;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(dx - 0.5, -0.3),
                              end: Alignment(dx + 0.5, 0.3),
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.15),
                                Colors.white.withValues(alpha: 0),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AnimatedBuilder(
                        animation: _iconPulse,
                        builder: (context, child) => Transform.scale(
                          scale: _iconPulse.value,
                          child: child,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.10),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.item.icon,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      Text(
                        widget.item.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Syllabus list page ───────────────────────────────────────────────────────
class _SyllabusPage extends StatefulWidget {
  const _SyllabusPage({required this.onOpenNoticeScreen});
  final void Function(Uri, String) onOpenNoticeScreen;

  @override
  State<_SyllabusPage> createState() => _SyllabusPageState();
}

class _SyllabusPageState extends State<_SyllabusPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _staggerCtrl;

  static const List<Map<String, dynamic>> _sections = [
    {
      'title': 'Honours',
      'subtitle': 'B.A. / B.S.S. / B.Sc. / B.B.S.',
      'url': 'https://www.nu.ac.bd/syllabus-honours.php',
      'icon': Icons.school_rounded,
      'color': Color(0xFF1565C0),
      'accent': Color(0xFF42A5F5),
    },
    {
      'title': 'Degree Pass',
      'subtitle': 'Pass course programs',
      'url': 'https://www.nu.ac.bd/syllabus-degree-pass.php',
      'icon': Icons.workspace_premium_rounded,
      'color': Color(0xFF00695C),
      'accent': Color(0xFF26A69A),
    },
    {
      'title': 'Masters',
      'subtitle': 'Post-graduate programs',
      'url': 'https://www.nu.ac.bd/syllabus-masters.php',
      'icon': Icons.military_tech_rounded,
      'color': Color(0xFF6A1B9A),
      'accent': Color(0xFFAB47BC),
    },
    {
      'title': 'Professionals',
      'subtitle': 'Professional degree programs',
      'url': 'https://www.nu.ac.bd/syllabus-professionals.php',
      'icon': Icons.business_center_rounded,
      'color': Color(0xFFE65100),
      'accent': Color(0xFFFFA726),
    },
    {
      'title': 'Preliminary to Masters',
      'subtitle': 'Pre-masters preparation',
      'url': 'https://www.nu.ac.bd/preliminary-to-masters.php',
      'icon': Icons.auto_stories_rounded,
      'color': Color(0xFF1B5E20),
      'accent': Color(0xFF66BB6A),
    },
    {
      'title': 'Post Graduate Diploma (PGD)',
      'subtitle': 'PGD programs',
      'url': 'https://www.nu.ac.bd/post-graduate-diploma-(pgd).php',
      'icon': Icons.card_membership_rounded,
      'color': Color(0xFF283593),
      'accent': Color(0xFF536DFE),
    },
  ];

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.gradientTop(isDark),
            AppColors.gradientBottom(isDark),
          ],
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _sections.length,
        itemBuilder: (context, index) {
          final item = _sections[index];
          final title = item['title'] as String;
          final subtitle = item['subtitle'] as String;
          final url = item['url'] as String;
          final icon = item['icon'] as IconData;
          final color = item['color'] as Color;
          final accent = item['accent'] as Color;

          // Stagger animation per item
          final start = (index * 0.10).clamp(0.0, 0.5);
          final end = (start + 0.5).clamp(0.0, 1.0);
          final fade = Tween<double>(begin: 0, end: 1).animate(
            CurvedAnimation(
              parent: _staggerCtrl,
              curve: Interval(start, end, curve: Curves.easeOut),
            ),
          );
          final slide =
              Tween<Offset>(
                begin: const Offset(0.15, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _staggerCtrl,
                  curve: Interval(start, end, curve: Curves.easeOut),
                ),
              );

          return FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: AppColors.card(isDark),
                  borderRadius: BorderRadius.circular(18),
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () =>
                        widget.onOpenNoticeScreen(Uri.parse(url), title),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border(isDark)),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cardShadow(isDark),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Gradient icon panel
                          Container(
                            width: 72,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [color, accent],
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(18),
                                bottomLeft: Radius.circular(18),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icon, color: Colors.white, size: 26),
                                const SizedBox(height: 4),
                                Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Text content
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary(isDark),
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary(isDark),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Arrow button
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: color,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final SearchHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  Color _cgpaColor(String cgpa) {
    final val = double.tryParse(cgpa) ?? 0;
    if (val >= 3.5) return const Color(0xFF10B981);
    if (val >= 3.0) return const Color(0xFF3B82F6);
    if (val >= 2.5) return const Color(0xFF8B5CF6);
    if (val >= 2.0) return const Color(0xFFF59E0B);
    return const Color(0xFF94A3B8);
  }

  @override
  Widget build(BuildContext context) {
    final cgpaColor = _cgpaColor(entry.cgpa);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String letterGrade = '';
    if (entry.cgpa.isNotEmpty) {
      int failCount = entry.courses
          .where((c) => c.grade.toUpperCase() == 'F')
          .length;
      final val = double.tryParse(entry.cgpa) ?? 0.0;
      letterGrade = ' • ${_calculateLetterGrade(val, failCount)}';
    }

    final initials = entry.studentName.isNotEmpty
        ? entry.studentName
              .trim()
              .split(' ')
              .take(2)
              .map((w) => w.isNotEmpty ? w[0] : '')
              .join()
              .toUpperCase()
        : '?';

    return Material(
      color: AppColors.card(isDark),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border(isDark)),
            boxShadow: [
              BoxShadow(
                color: AppColors.cardShadow(isDark),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent bar
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: cgpaColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Avatar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cgpaColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: cgpaColor,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Main content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.studentName.isNotEmpty
                              ? entry.studentName
                              : entry.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(isDark),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.roll.isNotEmpty
                              ? 'Roll: ${entry.roll}'
                              : entry.source,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary(isDark),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (entry.cgpa.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: cgpaColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: cgpaColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  'CGPA ${entry.cgpa}$letterGrade',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: cgpaColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${entry.courseCount} courses',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary(isDark),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Right: delete + date
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      color: const Color(0xFFCBD5E1),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 14),
                      child: Text(
                        entry.timestamp.length > 10
                            ? entry.timestamp.substring(0, 10)
                            : entry.timestamp,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFCBD5E1),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistorySummarySheet extends StatefulWidget {
  const _HistorySummarySheet({required this.entry});

  final SearchHistoryEntry entry;

  @override
  State<_HistorySummarySheet> createState() => _HistorySummarySheetState();
}

class _HistorySummarySheetState extends State<_HistorySummarySheet>
    with SingleTickerProviderStateMixin {
  static const AssetImage _shareFooterLogo = AssetImage(
    'assets/app_icon_cropped.png',
  );

  late AnimationController _expandController;
  late Animation<double> _heightAnimation;
  final GlobalKey _shareBoundaryKey = GlobalKey();
  bool _isExpanded = false;
  bool _isPreparingShare = false;
  bool _isSharingImage = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _heightAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  void _handleBottomSheetDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (!_isExpanded && velocity < -250) {
      _toggleExpand();
    }
  }

  Future<void> _shareSummaryImage() async {
    if (_isSharingImage) return;

    setState(() {
      _isSharingImage = true;
      _isPreparingShare = true;
    });

    try {
      await precacheImage(_shareFooterLogo, context);
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          _shareBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Share image is not ready yet.');
      }

      final view = ui.PlatformDispatcher.instance.views.first;
      final image = await boundary.toImage(
        pixelRatio: (view.devicePixelRatio * 1.8).clamp(2.0, 4.0),
      );

      // Composite onto a white background to ensure opaque white export
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final width = image.width.toDouble();
      final height = image.height.toDouble();
      final whitePaint = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, width, height), whitePaint);
      canvas.drawImage(image, ui.Offset.zero, ui.Paint());
      final picture = recorder.endRecording();
      final imgWithBg = await picture.toImage(image.width, image.height);
      final byteData = await imgWithBg.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null || pngBytes.isEmpty) {
        throw StateError('Could not generate the share image.');
      }

      final tempDir = await getTemporaryDirectory();
      final safeName = widget.entry.studentName
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}${safeName.isEmpty ? 'nu_result_summary' : safeName}_summary.png',
      );
      await file.writeAsBytes(pngBytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'Result summary from NU Results Portal${widget.entry.studentName.isNotEmpty ? ' for ${widget.entry.studentName}' : ''}',
        subject: 'NU Result Summary',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to share summary image: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingShare = false;
          _isSharingImage = false;
        });
      }
    }
  }

  Color _getGradeColor(String grade) {
    final normalized = grade.toUpperCase().replaceAll('-', '');
    if (normalized.startsWith('A')) return const Color(0xFF10B981);
    if (normalized.startsWith('B')) return const Color(0xFF3B82F6);
    if (normalized.startsWith('C')) return const Color(0xFF8B5CF6);
    if (normalized.startsWith('D')) return const Color(0xFFF59E0B);
    if (normalized.startsWith('F')) return const Color(0xFFEF4444);
    return const Color(0xFF64748B);
  }

  Color _cgpaColor(String cgpa) {
    final val = double.tryParse(cgpa) ?? 0;
    if (val >= 3.5) return const Color(0xFF10B981);
    if (val >= 3.0) return const Color(0xFF3B82F6);
    if (val >= 2.5) return const Color(0xFF8B5CF6);
    if (val >= 2.0) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpanded) {
      return _buildFullScreenSheet();
    }
    return _buildBottomSheet();
  }

  Widget _buildFullScreenSheet() {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.95, end: 1.0).animate(_heightAnimation),
      child: FadeTransition(
        opacity: _heightAnimation,
        child: Container(
          color: const Color(0xFFF8FAFC),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 28),
                        color: const Color(0xFF0F172A),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(child: _buildContentBody()),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSharingImage
                              ? null
                              : _shareSummaryImage,
                          icon: _isSharingImage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.image_outlined, size: 18),
                          label: const Text(
                            'Share Result',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1565C0),
                            side: const BorderSide(color: Color(0xFFBFDBFE)),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text(
                            'Close',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x280F172A),
              blurRadius: 32,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: _handleBottomSheetDragEnd,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _toggleExpand,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '⬆ Slide up to expand',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: _buildContentBody(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSharingImage
                              ? null
                              : _shareSummaryImage,
                          icon: _isSharingImage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.image_outlined, size: 18),
                          label: const Text(
                            'Share Result',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1565C0),
                            side: const BorderSide(color: Color(0xFFBFDBFE)),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text(
                            'Close',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentBody() {
    final entry = widget.entry;
    final cgpaColor = _cgpaColor(entry.cgpa);
    final cgpaVal = double.tryParse(entry.cgpa) ?? 0.0;
    final cgpaProgress = (cgpaVal / 4.0).clamp(0.0, 1.0);
    final showAllCourses = _isExpanded || _isPreparingShare;
    final initials = entry.studentName.isNotEmpty
        ? entry.studentName
              .trim()
              .split(' ')
              .take(2)
              .map((w) => w.isNotEmpty ? w[0] : '')
              .join()
              .toUpperCase()
        : '?';
    final letterGrade = entry.cgpa.isNotEmpty
        ? _calculateLetterGrade(
            cgpaVal,
            entry.courses.where((c) => c.grade.toUpperCase() == 'F').length,
          )
        : initials;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildSummaryContent(
          entry: entry,
          cgpaColor: cgpaColor,
          cgpaProgress: cgpaProgress,
          showAllCourses: showAllCourses,
          initials: initials,
          letterGrade: letterGrade,
          includeExportFooter: false,
        ),
        if (_isPreparingShare || _isSharingImage)
          Positioned(
            left: MediaQuery.sizeOf(context).width + 200,
            top: 0,
            child: IgnorePointer(
              child: RepaintBoundary(
                key: _shareBoundaryKey,
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width - 24,
                  child: _buildSummaryContent(
                    entry: entry,
                    cgpaColor: cgpaColor,
                    cgpaProgress: cgpaProgress,
                    showAllCourses: true,
                    initials: initials,
                    letterGrade: letterGrade,
                    includeExportFooter: true,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryContent({
    required SearchHistoryEntry entry,
    required Color cgpaColor,
    required double cgpaProgress,
    required bool showAllCourses,
    required String initials,
    required String letterGrade,
    required bool includeExportFooter,
  }) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gradient header card
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0D47A1),
                  cgpaColor.withValues(alpha: 0.9),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      entry.cgpa.isNotEmpty ? letterGrade : initials,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.studentName.isNotEmpty
                            ? entry.studentName
                            : 'Result Summary',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.registrationNumber.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Reg: ${entry.registrationNumber}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                      if (entry.roll.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Roll: ${entry.roll}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          entry.source,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 68,
                  height: 68,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 68,
                        height: 68,
                        child: CircularProgressIndicator(
                          value: 1.0,
                          strokeWidth: 6,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      SizedBox(
                        width: 68,
                        height: 68,
                        child: CircularProgressIndicator(
                          value: cgpaProgress,
                          strokeWidth: 6,
                          color: Colors.white,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.cgpa.isNotEmpty ? entry.cgpa : '--',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'CGPA',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryStatTile(
                    label: 'Total Points',
                    value: entry.totalPoints.isNotEmpty
                        ? entry.totalPoints
                        : '--',
                    icon: Icons.stars_rounded,
                    color: const Color(0xFF1565C0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryStatTile(
                    label: 'Courses',
                    value: '${entry.courseCount}',
                    icon: Icons.menu_book_rounded,
                    color: const Color(0xFF6A1B9A),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryStatTile(
                    label: 'Saved',
                    value: entry.timestamp.length > 10
                        ? entry.timestamp.substring(5, 10)
                        : entry.timestamp,
                    icon: Icons.bookmark_rounded,
                    color: const Color(0xFF00695C),
                  ),
                ),
              ],
            ),
          ),
          if (entry.courses.isNotEmpty) ...[
            if (showAllCourses)
              Column(
                children: List.generate(entry.courses.length, (index) {
                  final course = entry.courses[index];
                  final gradeColor = _getGradeColor(course.grade);
                  final isEven = index % 2 == 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: gradeColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: gradeColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                course.code.isNotEmpty
                                    ? course.code
                                    : 'Course ${index + 1}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0D1B2A),
                                ),
                              ),
                              if (course.title.isNotEmpty)
                                Text(
                                  course.title,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: gradeColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                course.grade,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (course.points != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                course.points!.toStringAsFixed(2),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: gradeColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  itemCount: entry.courses.length,
                  itemBuilder: (_, index) {
                    final course = entry.courses[index];
                    final gradeColor = _getGradeColor(course.grade);
                    final isEven = index % 2 == 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: gradeColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: gradeColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  course.code.isNotEmpty
                                      ? course.code
                                      : 'Course ${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0D1B2A),
                                  ),
                                ),
                                if (course.title.isNotEmpty)
                                  Text(
                                    course.title,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF94A3B8),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: gradeColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  course.grade,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (course.points != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  course.points!.toStringAsFixed(2),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: gradeColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
          if (includeExportFooter)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: const Image(
                          image: _shareFooterLogo,
                          width: 26,
                          height: 26,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Powered by NU Results Portal',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Summary stat tile (used in result summary sheet) ────────────────────────
class _SummaryStatTile extends StatelessWidget {
  const _SummaryStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat pill (used in CGPA calculator header) ───────────────────────────────
class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualCGPACalculator extends StatefulWidget {
  const _ManualCGPACalculator();

  @override
  State<_ManualCGPACalculator> createState() => _ManualCGPACalculatorState();
}

class _ManualCGPACalculatorState extends State<_ManualCGPACalculator> {
  List<_CourseEntry> courses = [];
  final TextEditingController _subjectNameController = TextEditingController();
  String? _selectedGrade;

  final List<String> _gradesList = [
    'A+',
    'A',
    'A-',
    'B+',
    'B',
    'B-',
    'C+',
    'C',
    'D',
    'F',
  ];

  double get calculatedCGPA {
    if (courses.isEmpty) return 0.0;
    double totalPoints = 0;
    int countedCourses = 0;
    for (var course in courses) {
      final points = _gradeToPoints(course.grade);
      // Exclude F grades (0.0 points) from calculation
      if (points != null && points > 0) {
        totalPoints += points;
        countedCourses++;
      }
    }
    return countedCourses == 0 ? 0.0 : totalPoints / countedCourses;
  }

  double? _gradeToPoints(String grade) {
    final gradeMap = {
      'A+': 4.0,
      'A': 3.75,
      'A-': 3.5,
      'B+': 3.25,
      'B': 3.0,
      'B-': 2.75,
      'C+': 2.5,
      'C': 2.25,
      'D': 2.0,
      'F': 0.0,
    };
    return gradeMap[grade.toUpperCase()];
  }

  Color _getGradeColor(String grade) {
    final normalized = grade.toUpperCase();
    if (normalized.startsWith('A')) return const Color(0xFF10B981);
    if (normalized.startsWith('B')) return const Color(0xFF3B82F6);
    if (normalized.startsWith('C')) return const Color(0xFF8B5CF6);
    if (normalized.startsWith('D')) return const Color(0xFFF59E0B);
    if (normalized.startsWith('F')) return const Color(0xFFEF4444);
    return const Color(0xFF64748B);
  }

  void _addCourse() {
    final subjectName = _subjectNameController.text.trim();
    final grade = _selectedGrade;

    if (grade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a grade'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      courses.add(
        _CourseEntry(
          subjectName: subjectName.isEmpty ? 'Course' : subjectName,
          grade: grade,
        ),
      );
      _subjectNameController.clear();
      _selectedGrade = null;
    });
  }

  void _removeCourse(int index) {
    setState(() {
      courses.removeAt(index);
    });
  }

  @override
  void dispose() {
    _subjectNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cgpa = calculatedCGPA;
    final cgpaProgress = (cgpa / 4.0).clamp(0.0, 1.0);
    final cgpaColor = cgpa >= 3.5
        ? const Color(0xFF10B981)
        : cgpa >= 3.0
        ? const Color(0xFF3B82F6)
        : cgpa >= 2.5
        ? const Color(0xFF8B5CF6)
        : cgpa >= 2.0
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444);

    return Container(
      decoration: BoxDecoration(color: AppColors.subtleBg(isDark)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── CGPA Gauge Header Card ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Circular CGPA gauge
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: courses.isEmpty ? 0 : cgpaProgress,
                    ),
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) {
                      return SizedBox(
                        width: 108,
                        height: 108,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 108,
                              height: 108,
                              child: CircularProgressIndicator(
                                value: 1.0,
                                strokeWidth: 10,
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            SizedBox(
                              width: 108,
                              height: 108,
                              child: CircularProgressIndicator(
                                value: value,
                                strokeWidth: 10,
                                color: courses.isEmpty
                                    ? Colors.white.withValues(alpha: 0.35)
                                    : cgpaColor,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  courses.isEmpty
                                      ? '--'
                                      : (value * 4.0).toStringAsFixed(2),
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    height: 1.0,
                                  ),
                                ),
                                if (courses.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2.0,
                                    ),
                                    child: Text(
                                      _calculateLetterGrade(
                                        value * 4.0,
                                        courses
                                            .where(
                                              (c) =>
                                                  c.grade.toUpperCase() == 'F',
                                            )
                                            .length,
                                      ),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                      ),
                                    ),
                                  ),
                                const Text(
                                  'CGPA',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 20),
                  // Info + stats
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CGPA Calculator',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'National Univercity',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _StatPill(
                              label: 'courses',
                              value: '${courses.length}',
                            ),
                            if (courses.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              _StatPill(
                                label: 'pts',
                                value: courses
                                    .map((c) => _gradeToPoints(c.grade) ?? 0.0)
                                    .fold(0.0, (a, b) => a + b)
                                    .toStringAsFixed(1),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Add Course Card ─────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(isDark),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border(isDark)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cardShadow(isDark),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card header
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface(isDark),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(color: AppColors.border(isDark)),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.add_circle_outline_rounded,
                          color: Color(0xFF1565C0),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Add Course',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Subject name field
                        TextField(
                          controller: _subjectNameController,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary(isDark),
                          ),
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.book_outlined,
                              color: AppColors.textTertiary(isDark),
                              size: 20,
                            ),
                            hintText: 'Subject name (optional)',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary(isDark),
                              fontSize: 14,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 12,
                            ),
                            filled: true,
                            fillColor: AppColors.surface(isDark),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColors.border(isDark),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColors.border(isDark),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF1565C0),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Grade label
                        Text(
                          'Select Grade',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary(isDark),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Grade chip selector
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _gradesList.map((grade) {
                            final isSelected = _selectedGrade == grade;
                            final gradeColor = _getGradeColor(grade);
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedGrade = grade),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? gradeColor
                                      : gradeColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? gradeColor
                                        : gradeColor.withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  grade,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : gradeColor,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        // Add button
                        FilledButton.icon(
                          onPressed: _addCourse,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text(
                            'Add Course',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Course List ─────────────────────────────────────────────
            if (courses.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Added Courses (${courses.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0D1B2A),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => courses.clear()),
                    icon: const Icon(
                      Icons.delete_sweep_rounded,
                      size: 18,
                      color: Color(0xFFEF4444),
                    ),
                    label: const Text(
                      'Clear All',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: courses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final course = courses[index];
                  final points = _gradeToPoints(course.grade);
                  final gradeColor = _getGradeColor(course.grade);
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.card(isDark),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border(isDark)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cardShadow(isDark),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Grade index panel
                        Container(
                          width: 56,
                          height: 62,
                          decoration: BoxDecoration(
                            color: gradeColor.withValues(alpha: 0.1),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(14),
                              bottomLeft: Radius.circular(14),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: gradeColor.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                course.grade,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: gradeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Subject name + points
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  course.subjectName.isNotEmpty
                                      ? course.subjectName
                                      : 'Course ${index + 1}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary(isDark),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${points?.toStringAsFixed(2) ?? '--'} grade points',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: gradeColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Delete
                        IconButton(
                          onPressed: () => _removeCourse(index),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                          color: AppColors.textTertiary(isDark),
                          padding: const EdgeInsets.all(12),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CourseEntry {
  final String subjectName;
  final String grade;

  _CourseEntry({required this.subjectName, required this.grade});
}

// ─── In-App WebView page ──────────────────────────────────────────────────────
class _InAppWebViewPage extends StatefulWidget {
  const _InAppWebViewPage({required this.url, required this.title});
  final String url;
  final String title;

  @override
  State<_InAppWebViewPage> createState() => _InAppWebViewPageState();
}

class _InAppWebViewPageState extends State<_InAppWebViewPage> {
  late WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = err.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkCard
            : _Colors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _controller.reload(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── App Banner Ad (Google Mobile Ads) ───────────────────────────────────────
class _AppBannerAd extends StatefulWidget {
  const _AppBannerAd();
  @override
  State<_AppBannerAd> createState() => _AppBannerAdState();
}

class _AppBannerAdState extends State<_AppBannerAd> {
  BannerAd? _banner;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _banner = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _banner == null) return const SizedBox.shrink();
    return SizedBox(
      width: _banner!.size.width.toDouble(),
      height: _banner!.size.height.toDouble(),
      child: AdWidget(ad: _banner!),
    );
  }
}

// ─── Privacy & Policy page ─────────────────────────────────────────────────
class _PrivacyPolicyPage extends StatelessWidget {
  const _PrivacyPolicyPage();

  static const _policyText =
      '''NU Results Portal displays National University results, notices and related resources.

  Information handled by the app:
  - Result information that appears on official NU result pages, such as student name, roll, registration number, CGPA and course results
  - Search history saved locally on your device for convenience
  - Theme preference saved locally on your device
  - Device and advertising identifiers, diagnostics and usage signals that may be collected by Google Mobile Ads

  How information is used:
  - To display official NU result and notice content inside the app
  - To remember recent result lookups on your device
  - To remember your selected theme
  - To show ads and support the app

  Storage and sharing:
  - Search history and theme settings are stored locally on your device using on-device app storage
  - PDF files you open may be cached or downloaded to your device when you choose to view or save them
  - If you use the share feature, the content you choose is shared through apps you select

  Third-party services:
  - Official National University websites and result pages loaded in the app's web views
  - Google Mobile Ads for advertising

  The app does not require account registration. Information entered into official NU result forms is submitted to the relevant NU website, and third-party services may process data under their own policies.

  Contact developer:
  - Name: Tanzil Ahmed
  - Email: tapallab00@gmail.com

  For privacy questions or requests, contact the developer using the email above.''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Policy'),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkCard
            : _Colors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Privacy & Policy',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            const Text(
              _policyText,
              style: TextStyle(fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.parse('https://www.nu.ac.bd/');
                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {}
              },
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('View NU website'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkCard
                    : _Colors.primary,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(
                  'https://pallab200.github.io/nu_results_portal/privacy-policy.html',
                );
                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {}
              },
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Open hosted privacy policy'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(
                  'https://pallab200.github.io/nu_results_portal/delete-data.html',
                );
                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {}
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Request data deletion'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        color: Theme.of(ctx).brightness == Brightness.dark
                            ? AppColors.darkCard
                            : Colors.white,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF1565C0),
                                    const Color(
                                      0xFF42A5F5,
                                    ).withValues(alpha: 0.8),
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.mail_outline_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Contact Developer',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Name: Tanzil Ahmed',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(ctx).brightness == Brightness.dark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const SelectableText(
                                'tapallab00@gmail.com',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FilledButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(
                                      const ClipboardData(
                                        text: 'tapallab00@gmail.com',
                                      ),
                                    );
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Email copied to clipboard',
                                        ),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.copy_rounded),
                                  label: const Text('Copy Email'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.grey.shade400,
                                    foregroundColor: Colors.black87,
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.mail_rounded),
              label: const Text('Contact developer'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Results page (tabbed: Recent | Archive | History) ───────────────────────
class _ResultsPage extends StatefulWidget {
  const _ResultsPage();

  @override
  State<_ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<_ResultsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<SearchHistoryEntry> _history = [];
  AnimationController? _staggerCtrl;
  static const String _historyKey = 'searchHistory';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _staggerCtrl?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) {
      if (mounted) setState(() => _history = []);
      return;
    }
    final decoded = (jsonDecode(raw) as List)
        .cast<Map>()
        .map(
          (item) => SearchHistoryEntry.fromJson(item.cast<String, dynamic>()),
        )
        .toList();
    if (mounted) {
      setState(() => _history = decoded);
      _staggerCtrl?.dispose();
      _staggerCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      )..forward();
    }
  }

  Future<void> _addHistoryEntry(SearchHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = [
      entry,
      ..._history.where((h) => h.key != entry.key),
    ].take(10).toList();
    await prefs.setString(
      _historyKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    if (!mounted) return;
    setState(() => _history = updated);
    _showResultPopup(entry);
  }

  Future<void> _removeHistoryEntry(SearchHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = _history.where((h) => h.key != entry.key).toList();
    await prefs.setString(
      _historyKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    if (!mounted) return;
    setState(() => _history = updated);
  }

  void _showResultPopup(SearchHistoryEntry entry) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HistorySummarySheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkCard
            : _Colors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _Colors.gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.update_rounded), text: 'Recent'),
            Tab(icon: Icon(Icons.folder_open_rounded), text: 'Archive'),
            Tab(icon: Icon(Icons.history_rounded), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _ResultWebViewTab(
            url: 'http://result.nu.ac.bd/',
            source: 'Recent Result',
            onHistoryEntry: _addHistoryEntry,
          ),
          _ResultWebViewTab(
            url: 'http://results.nu.ac.bd/',
            source: 'Results Archive',
            onHistoryEntry: _addHistoryEntry,
          ),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.manage_search_rounded,
                size: 40,
                color: Color(0xFF1565C0),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Search History',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0D1B2A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Search for a result and it will\nappear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF94A3B8),
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: Theme.of(context).brightness == Brightness.dark
              ? [AppColors.subtleBg(true), AppColors.surface(true)]
              : const [Color(0xFFEFF8FF), Color(0xFFF8FAFC)],
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _history[index];
          Widget card = _HistoryCard(
            entry: item,
            onTap: () => _showResultPopup(item),
            onDelete: () => _removeHistoryEntry(item),
          );

          if (_staggerCtrl != null) {
            final start = (index * 0.1).clamp(0.0, 0.7);
            final end = (start + 0.3).clamp(0.0, 1.0);
            final fade = Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(
                parent: _staggerCtrl!,
                curve: Interval(start, end, curve: Curves.easeOutCubic),
              ),
            );
            final slide =
                Tween<Offset>(
                  begin: const Offset(0.2, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _staggerCtrl!,
                    curve: Interval(start, end, curve: Curves.easeOutCubic),
                  ),
                );
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(position: slide, child: card),
            );
          }
          return card;
        },
      ),
    );
  }
}

// ─── Result WebView tab (with JS injection + history capture) ────────────────
class _ResultWebViewTab extends StatefulWidget {
  const _ResultWebViewTab({
    required this.url,
    required this.source,
    required this.onHistoryEntry,
  });
  final String url;
  final String source;
  final void Function(SearchHistoryEntry) onHistoryEntry;

  @override
  State<_ResultWebViewTab> createState() => _ResultWebViewTabState();
}

class _ResultWebViewTabState extends State<_ResultWebViewTab>
    with AutomaticKeepAliveClientMixin {
  late WebViewController _controller;
  static const double _initialPageZoom = 1.0;
  bool _isLoading = true;
  bool _hasError = false;
  String _currentUrl = '';
  double _lastScale = 1.0;
  bool _isZooming = false;
  double _currentZoom = _initialPageZoom;

  final Map<int, Offset> _activePointers = {};
  double _initialDistance = 0.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
                _currentUrl = url;
              });
            }
          },
          onPageFinished: (url) async {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
                _currentZoom = _initialPageZoom;
              });
            }
            await _controller.runJavaScript(_injectedScript);
            await _syncZoomFromPage();
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'NUBridge',
        onMessageReceived: (msg) {
          _handleBridgeMessage(msg.message);
        },
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _handleBridgeMessage(String message) {
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final payload = ResultPayload.fromJson(decoded);
      if (payload.courses.isEmpty) return;
      final entry = SearchHistoryEntry(
        key:
            '${widget.source}:${payload.student.roll.isNotEmpty ? payload.student.roll : _currentUrl}',
        url: _currentUrl,
        source: widget.source,
        label: 'Result Summary',
        studentName: payload.student.name,
        roll: payload.student.roll,
        registrationNumber: payload.student.registrationNumber,
        cgpa: payload.cgpa,
        totalPoints: payload.totalPoints.toStringAsFixed(2),
        courseCount: payload.courses.length,
        courses: payload.courses,
        timestamp: DateTime.now().toLocal().toString().substring(0, 19),
      );
      widget.onHistoryEntry(entry);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        Listener(
          onPointerDown: (event) {
            _activePointers[event.pointer] = event.position;
          },
          onPointerMove: (event) {
            _activePointers[event.pointer] = event.position;
            if (_activePointers.length == 2 && !_isZooming) {
              final positions = _activePointers.values.toList();
              final currentDistance = (positions[0] - positions[1]).distance;
              if (_initialDistance == 0.0) {
                _initialDistance = currentDistance;
                _lastScale = 1.0;
              } else {
                final scale = currentDistance / _initialDistance;
                final scaleDelta = scale / _lastScale;
                if (scaleDelta > 1.05 || scaleDelta < 0.95) {
                  _lastScale = scale;
                  _isZooming = true;
                  final factor = scaleDelta > 1.0 ? 1.05 : 0.95;
                  _zoomBy(factor).then((_) {
                    if (mounted) _isZooming = false;
                  });
                }
              }
            }
          },
          onPointerUp: (event) {
            _activePointers.remove(event.pointer);
            if (_activePointers.length < 2) {
              _initialDistance = 0.0;
              _lastScale = 1.0;
            }
          },
          onPointerCancel: (event) {
            _activePointers.remove(event.pointer);
            if (_activePointers.length < 2) {
              _initialDistance = 0.0;
              _lastScale = 1.0;
            }
          },
          behavior: HitTestBehavior.translucent,
          child: WebViewWidget(controller: _controller),
        ),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
        if (!_isLoading && _hasError)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: Colors.grey,
                ),
                const SizedBox(height: 12),
                const Text('Page failed to load'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _controller.reload(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        // Reload button in bottom right corner
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton(
            onPressed: () async {
              await _controller.clearCache();
              _controller.reload();
            },
            heroTag: 'reload_${widget.url}',
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white,
            child: const Icon(Icons.refresh_rounded),
          ),
        ),
      ],
    );
  }

  Future<void> _zoomBy(double factor) async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "(function(){try{if(window.__nuChangeZoomBy){return window.__nuChangeZoomBy($factor);}var cur=parseFloat(document.body.style.zoom||window.__nuZoom||1)||1;var next=cur*$factor;if(next<0.4)next=0.4;if(next>4)next=4;window.__nuZoom=next;document.body.style.zoom=next;console.log('Zoomed to '+next);return next;}catch(e){console.log('Zoom error: '+e);return null;}})();",
      );
      final newZoom =
          _parseZoomResult(result) ?? (_currentZoom * factor).clamp(0.4, 4.0);
      if (mounted) {
        setState(() {
          _currentZoom = newZoom;
        });
        // print('DEBUG: _currentZoom updated to $newZoom (factor: $factor)');
      }
    } catch (e) {
      // print('DEBUG: _zoomBy error: $e');
    }
  }

  Future<void> _syncZoomFromPage() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "(function(){try{return window.__nuGetZoom?window.__nuGetZoom():(parseFloat(document.body.style.zoom||window.__nuZoom||1)||1);}catch(e){return null;}})();",
      );
      final zoom = _parseZoomResult(result);
      if (zoom != null && mounted) {
        setState(() {
          _currentZoom = zoom;
        });
      }
    } catch (_) {}
  }

  double? _parseZoomResult(Object? result) {
    if (result is num) {
      return result.toDouble();
    }
    if (result == null) {
      return null;
    }
    final normalized = result.toString().replaceAll('"', '').trim();
    return double.tryParse(normalized);
  }
}

// ─── Notices page (category grid) ────────────────────────────────────────────
class _NoticesPage extends StatefulWidget {
  const _NoticesPage({
    required this.onOpenNoticeScreen,
    required this.onOpenPdf,
  });
  final void Function(Uri, String) onOpenNoticeScreen;
  final void Function(Uri, String) onOpenPdf;

  @override
  State<_NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<_NoticesPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categories = [
      _NoticeCategory(
        icon: Icons.new_releases_rounded,
        label: 'Recent Notices',
        color: const Color(0xFFB71C1C),
        accent: const Color(0xFFEF5350),
        onTap: () => widget.onOpenNoticeScreen(
          Uri.parse('https://www.nu.ac.bd/recent-news-notice.php'),
          'Recent Notices',
        ),
      ),
      _NoticeCategory(
        icon: Icons.app_registration_rounded,
        label: 'Admission Notices',
        color: const Color(0xFF1B5E20),
        accent: const Color(0xFF66BB6A),
        onTap: () => widget.onOpenNoticeScreen(
          Uri.parse('https://www.nu.ac.bd/admission-notice.php'),
          'Admission Notices',
        ),
      ),
      _NoticeCategory(
        icon: Icons.fact_check_rounded,
        label: 'Exam Notices',
        color: const Color(0xFFE65100),
        accent: const Color(0xFFFFA726),
        onTap: () => widget.onOpenNoticeScreen(
          Uri.parse('https://www.nu.ac.bd/examination-notice.php'),
          'Examination Notices',
        ),
      ),
      _NoticeCategory(
        icon: Icons.event_note_rounded,
        label: 'Academic Calendar',
        color: const Color(0xFF123E6B),
        accent: const Color(0xFF3AA0FF),
        onTap: () => widget.onOpenNoticeScreen(
          Uri.parse('https://www.nu.ac.bd/academic-calendar-list.php'),
          'Academic Calendar',
        ),
      ),
      // Grading System category removed per user request.
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notices'),
        backgroundColor: isDark ? AppColors.darkCard : _Colors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.gradientTop(isDark),
              AppColors.gradientBottom(isDark),
            ],
          ),
        ),
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.2,
          ),
          itemBuilder: (context, index) {
            final start = (index * 0.12).clamp(0.0, 0.6);
            final end = (start + 0.5).clamp(0.0, 1.0);
            final fade = Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(
                parent: _staggerCtrl,
                curve: Interval(start, end, curve: Curves.easeOut),
              ),
            );
            final slide =
                Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _staggerCtrl,
                    curve: Interval(start, end, curve: Curves.easeOut),
                  ),
                );
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: slide,
                child: _NoticeCategoryCard(category: categories[index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NoticeCategory {
  const _NoticeCategory({
    required this.icon,
    required this.label,
    required this.color,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color accent;
  final VoidCallback onTap;
}

class _NoticeCategoryCard extends StatefulWidget {
  const _NoticeCategoryCard({required this.category});
  final _NoticeCategory category;

  @override
  State<_NoticeCategoryCard> createState() => _NoticeCategoryCardState();
}

class _NoticeCategoryCardState extends State<_NoticeCategoryCard>
    with TickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _iconPulse;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.93,
    ).animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeIn));
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _iconPulse = Tween<double>(
      begin: 0.92,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    _shimmerCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTapDown: (_) => _pressCtrl.forward(),
        onTapUp: (_) {
          _pressCtrl.reverse();
          widget.category.onTap();
        },
        onTapCancel: () => _pressCtrl.reverse(),
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            final glow = 0.25 + 0.15 * _pulseCtrl.value;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.0 + 0.3 * _pulseCtrl.value, -1.0),
                  end: Alignment(1.0, 1.0 - 0.3 * _pulseCtrl.value),
                  colors: [widget.category.color, widget.category.accent],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.category.accent.withValues(alpha: glow),
                    blurRadius: 14 + 8 * _pulseCtrl.value,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Shimmer sweep
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _shimmerCtrl,
                      builder: (context, _) {
                        final dx = _shimmerCtrl.value * 3 - 1;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(dx - 0.5, -0.3),
                              end: Alignment(dx + 0.5, 0.3),
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.15),
                                Colors.white.withValues(alpha: 0),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AnimatedBuilder(
                        animation: _iconPulse,
                        builder: (context, child) => Transform.scale(
                          scale: _iconPulse.value,
                          child: child,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.10),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.category.icon,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      Text(
                        widget.category.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const String _injectedScript = r'''
(function () {
  if (window.__nuBridgeInstalled) {
    return;
  }
  window.__nuBridgeInstalled = true;

  const gradeMap = {'A+':4,'A':3.75,'A-':3.5,'B+':3.25,'B':3,'B-':2.75,'C+':2.5,'C':2.25,'D':2,'F':0};
  const validGrades = Object.keys(gradeMap).concat(['PASS', 'FAIL']);

  function normalizeText(value) {
    return (value || '').replace(/\s+/g, ' ').trim();
  }

  function ensureMobileViewport() {
    try {
      let viewport = document.querySelector('meta[name="viewport"]');
      if (!viewport) {
        viewport = document.createElement('meta');
        viewport.name = 'viewport';
        document.head.appendChild(viewport);
      }
      viewport.content = 'width=420, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';

      let style = document.getElementById('__nu_mobile_layout');
      if (!style) {
        style = document.createElement('style');
        style.id = '__nu_mobile_layout';
        document.head.appendChild(style);
      }

      style.textContent = [
        'html {',
        '  overflow-x: auto !important;',
        '}',
        'body {',
        '  overflow-x: auto !important;',
        '  max-width: none !important;',
        '  width: 100% !important;',
        '  transform-origin: top left !important;',
        '}',
        'table, img {',
        '  max-width: none !important;',
        '}',
        'input, select, textarea, button, a {',
        '  touch-action: manipulation;',
        '}',
      ].join('');
    } catch (_) {}
  }

  function parseStudentInfo(doc) {
    const info = {name: '', roll: '', registrationNumber: ''};
    const rows = doc.querySelectorAll('tr');
    for (let i = 0; i < rows.length; i += 1) {
      const cells = rows[i].querySelectorAll('th,td');
      for (let j = 0; j < cells.length; j += 1) {
        const label = normalizeText(cells[j].textContent).toLowerCase();
        if (!info.name && /^(name|student name)\b/.test(label)) {
          const nextName = cells[j + 1] ? normalizeText(cells[j + 1].textContent) : '';
          if (nextName && nextName !== ':' && nextName !== '-') {
            info.name = nextName.replace(/^[:\-]\s*/, '');
          }
        }
        if (!info.roll && /(exam\.?\s*roll|roll\s*no\.?|roll)\b/.test(label)) {
          const nextRoll = cells[j + 1] ? normalizeText(cells[j + 1].textContent) : '';
          if (nextRoll && nextRoll !== ':' && nextRoll !== '-') {
            info.roll = nextRoll.replace(/^[:\-]\s*/, '');
          }
        }
        if (!info.registrationNumber && /(reg|registration|reg\.?\s*no)\b/.test(label)) {
          const nextReg = cells[j + 1] ? normalizeText(cells[j + 1].textContent) : '';
          if (nextReg && nextReg !== ':' && nextReg !== '-') {
            info.registrationNumber = nextReg.replace(/^[:\-]\s*/, '');
          }
        }
      }
      if (info.name && info.roll && info.registrationNumber) {
        break;
      }
    }
    if (!info.name || !info.roll || !info.registrationNumber) {
      const text = normalizeText(doc.body ? doc.body.textContent : '');
      if (!info.name) {
        const nameMatch = text.match(/(?:student\s+name|name)\s*[:\-]?\s*([A-Za-z][A-Za-z .'-]{2,80})/i);
        if (nameMatch) info.name = normalizeText(nameMatch[1]);
      }
      if (!info.roll) {
        const rollMatch = text.match(/(?:exam\.?\s*roll|roll\s*no\.?|roll)\s*[:\-]?\s*(\d{4,})/i);
        if (rollMatch) info.roll = normalizeText(rollMatch[1]);
      }
      if (!info.registrationNumber) {
        const regMatch = text.match(/(?:reg|registration|reg\.?\s*no)\s*[:\-]?\s*([A-Z0-9\-]{4,20})/i);
        if (regMatch) info.registrationNumber = normalizeText(regMatch[1]);
      }
    }
    return info;
  }

  function parseCourses(doc) {
    const courses = [];
    const tables = doc.querySelectorAll('table');
    for (let t = 0; t < tables.length; t += 1) {
      const rows = tables[t].querySelectorAll('tr');
      if (!rows.length) continue;
      const headers = Array.from(rows[0].querySelectorAll('th,td')).map((cell) => normalizeText(cell.textContent).toLowerCase());
      const codeIndex = headers.findIndex((header) => header.includes('course code'));
      if (codeIndex < 0) continue;
      let gradeIndex = -1;
      headers.forEach((header, index) => {
        if (header.includes('letter') || header.includes('grade')) {
          gradeIndex = index;
        }
      });

      for (let r = 1; r < rows.length; r += 1) {
        const cells = rows[r].querySelectorAll('th,td');
        if (cells.length < 2) continue;
        const code = cells[codeIndex] ? normalizeText(cells[codeIndex].textContent) : '';
        if (!/^\d{5,6}$/.test(code)) continue;
        const title = cells[codeIndex + 1] ? normalizeText(cells[codeIndex + 1].textContent) : '';
        let grade = '';
        if (gradeIndex >= 0 && gradeIndex < cells.length) {
          grade = normalizeText(cells[gradeIndex].textContent);
        } else {
          for (let c = cells.length - 1; c >= Math.max(0, cells.length - 4); c -= 1) {
            const value = normalizeText(cells[c].textContent).toUpperCase();
            if (validGrades.includes(value)) {
              grade = normalizeText(cells[c].textContent);
              break;
            }
          }
        }
        if (grade) {
          const key = grade.toUpperCase();
          courses.push({
            code,
            title,
            grade,
            points: Object.prototype.hasOwnProperty.call(gradeMap, key) ? gradeMap[key] : null,
          });
        }
      }
      if (courses.length > 0) break;
    }
    return courses;
  }

  function buildPayload(doc) {
    return JSON.stringify({
      student: parseStudentInfo(doc),
      courses: parseCourses(doc),
    });
  }

  function sendCurrentResult() {
    try {
      ensureMobileViewport();
      const payload = buildPayload(document);
      const decoded = JSON.parse(payload);
      if (!decoded.courses || decoded.courses.length === 0) return;
      NUBridge.postMessage(payload);
    } catch (_) {}
  }

  window.__nuSendCurrentResult = sendCurrentResult;

  try {
    window.open = function (url) {
      if (url) {
        window.location.href = new URL(url, window.location.href).href;
      }
      return window;
    };
  } catch (_) {}

  document.querySelectorAll('a[target],form[target]').forEach((element) => element.removeAttribute('target'));
  ensureMobileViewport();

  // Zoom helpers exposed for Flutter controls (zoom in / zoom out)
  try {
    (function () {
      // Initialize zoom to normal (1.0), not viewport zoom (0.43)
      window.__nuZoom = 1.0;
      document.body.style.zoom = 1.0;
      console.log('__nuZoom initialized to 1.0');

      window.__nuSetZoom = function (z) {
        try {
          var v = parseFloat(z) || 1;
          window.__nuZoom = v;
          document.body.style.zoom = v;
          console.log('Zoom set to ' + v + ', body.scrollWidth=' + document.body.scrollWidth + ', body.clientWidth=' + document.body.clientWidth);
        } catch (e) {}
      };

      window.__nuChangeZoomBy = function (factor) {
        try {
          var cur = window.__nuZoom || 1.0;
          var next = cur * factor;
          if (next < 0.4) next = 0.4;
          if (next > 4) next = 4;
          window.__nuZoom = next;
          document.body.style.zoom = next;
          console.log('Zoom changed to ' + next + ' (factor=' + factor + '), body.scrollWidth=' + document.body.scrollWidth + ', body.clientWidth=' + document.body.clientWidth + ', doc.scrollWidth=' + document.documentElement.scrollWidth);
          return next;
        } catch (e) {
          return null;
        }
      };

      window.__nuGetZoom = function () {
        return window.__nuZoom || 1.0;
      };

      var panStartX = 0;
      var panStartY = 0;
      var panStartLeft = 0;
      var isHorizontalPanning = false;

      function getScroller() {
        // For zoomed content, we need to scroll the document element
        if (document.documentElement.scrollWidth > document.documentElement.clientWidth) {
          return document.documentElement;
        }
        if (document.body.scrollWidth > document.body.clientWidth) {
          return document.body;
        }
        return document.scrollingElement || document.documentElement || document.body;
      }

      document.addEventListener('touchstart', function (event) {
        if (!event.touches || event.touches.length !== 1) return;
        // Enable panning when zoomed in beyond 1.1x
        var zoom = window.__nuZoom || 1.0;
        console.log('touchstart: zoom=' + zoom + ', check=' + (zoom > 1.1));
        if (zoom <= 1.1) {
          isHorizontalPanning = false;
          console.log('touchstart: zoom too low, panning disabled');
          return;
        }
        var scroller = getScroller();
        if (!scroller) {
          console.log('touchstart: no scroller');
          return;
        }
        console.log('touchstart: scroller found, scrollWidth=' + scroller.scrollWidth + ', clientWidth=' + scroller.clientWidth + ', scrollLeft=' + scroller.scrollLeft);
        panStartX = event.touches[0].clientX;
        panStartY = event.touches[0].clientY;
        panStartLeft = scroller.scrollLeft || 0;
        isHorizontalPanning = true;
        console.log('touchstart: panning enabled, x=' + panStartX + ', scrollLeft=' + panStartLeft);
      }, {passive: true});

      document.addEventListener('touchmove', function (event) {
        if (!isHorizontalPanning || !event.touches || event.touches.length !== 1) {
          if (!isHorizontalPanning) console.log('touchmove: panning not enabled');
          return;
        }
        // Check if still zoomed in
        var zoom = window.__nuZoom || 1.0;
        if (zoom <= 1.1) {
          console.log('touchmove: zoom too low (' + zoom + '), ignored');
          return;
        }
        var dx = event.touches[0].clientX - panStartX;
        var dy = event.touches[0].clientY - panStartY;
        console.log('touchmove: dx=' + dx + ', dy=' + dy + ', abs(dx)=' + Math.abs(dx) + ', abs(dy)=' + Math.abs(dy));
        if (Math.abs(dx) <= Math.abs(dy)) {
          console.log('touchmove: vertical movement, ignored');
          return;
        }
        var scroller = getScroller();
        if (!scroller) {
          console.log('touchmove: no scroller');
          return;
        }
        var newScrollLeft = panStartLeft - dx;
        console.log('touchmove: scrolling to ' + newScrollLeft + ' (from ' + panStartLeft + ', dx=' + dx + ')');
        scroller.scrollLeft = newScrollLeft;
        event.preventDefault();
        console.log('touchmove: prevented default');
      }, {passive: false});

      document.addEventListener('touchend', function () {
        isHorizontalPanning = false;
      }, {passive: true});

      document.addEventListener('touchcancel', function () {
        isHorizontalPanning = false;
      }, {passive: true});
    })();
  } catch (_) {}

  window.addEventListener('resize', ensureMobileViewport);
  window.addEventListener('load', sendCurrentResult);
  sendCurrentResult();
})();
''';
