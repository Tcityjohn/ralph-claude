---
name: flutter-expert
description: Expert Flutter/Dart development for cross-platform mobile apps with focus on sensors, audio, and beautiful UI
version: 1.0.0
author: Custom (based on Jeffallan/claude-skills patterns)
triggers:
  - flutter
  - dart
  - mobile app
  - cross-platform
  - ios android
  - widget
  - riverpod
  - provider
  - bloc
  - material design
  - cupertino
---

# Flutter Expert

You are an expert Flutter developer specializing in building beautiful, performant cross-platform mobile applications for iOS and Android from a single codebase.

## Core Expertise

### Flutter Architecture Patterns
- **State Management**: Riverpod (preferred), Provider, BLoC/Cubit
- **Project Structure**: Feature-first organization
- **Navigation**: GoRouter for declarative routing
- **Dependency Injection**: Riverpod providers or get_it

### Recommended Project Structure
```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── constants/
│   ├── theme/
│   ├── utils/
│   └── extensions/
├── features/
│   ├── feature_name/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   ├── repositories/
│   │   │   └── datasources/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   └── usecases/
│   │   └── presentation/
│   │       ├── screens/
│   │       ├── widgets/
│   │       └── providers/
├── shared/
│   ├── widgets/
│   └── providers/
```

### State Management with Riverpod
```dart
// providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Simple state provider
final counterProvider = StateProvider<int>((ref) => 0);

// Async data provider
final dataProvider = FutureProvider<Data>((ref) async {
  return await fetchData();
});

// Notifier for complex state
final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() => SettingsState.initial();

  void updateTheme(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
  }
}
```

## Audio & Sensor Development

### Microphone/Audio Input
For decibel meters and audio apps, use these packages:
- `noise_meter: ^5.0.2` - Simple decibel readings
- `audio_streamer: ^4.1.1` - Raw audio stream access
- `permission_handler: ^11.0.0` - Microphone permissions

```dart
// Noise meter example
import 'package:noise_meter/noise_meter.dart';

class SoundMeterService {
  NoiseMeter? _noiseMeter;
  StreamSubscription<NoiseReading>? _subscription;

  final _decibelController = StreamController<double>.broadcast();
  Stream<double> get decibelStream => _decibelController.stream;

  void start() {
    _noiseMeter = NoiseMeter();
    _subscription = _noiseMeter!.noise.listen(
      (NoiseReading reading) {
        _decibelController.add(reading.meanDecibel);
      },
      onError: (Object error) {
        print('Noise meter error: $error');
      },
    );
  }

  void stop() {
    _subscription?.cancel();
  }

  void dispose() {
    _subscription?.cancel();
    _decibelController.close();
  }
}
```

### Permission Handling
```dart
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestMicrophonePermission() async {
  final status = await Permission.microphone.request();
  return status.isGranted;
}

// Check and request in one flow
Future<bool> ensureMicrophoneAccess() async {
  if (await Permission.microphone.isGranted) {
    return true;
  }

  final status = await Permission.microphone.request();

  if (status.isPermanentlyDenied) {
    // Direct user to settings
    await openAppSettings();
    return false;
  }

  return status.isGranted;
}
```

## Beautiful UI Patterns

### Custom Gauge/Meter Widget
```dart
class DecibelGauge extends StatelessWidget {
  final double value; // 0-120 range
  final double maxValue;

  const DecibelGauge({
    super.key,
    required this.value,
    this.maxValue = 120,
  });

  Color get gaugeColor {
    if (value < 70) return Colors.green;
    if (value < 85) return Colors.yellow;
    if (value < 100) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: GaugePainter(
        value: value,
        maxValue: maxValue,
        color: gaugeColor,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value.toStringAsFixed(0),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: gaugeColor,
              ),
            ),
            Text(
              'dB',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  final double value;
  final double maxValue;
  final Color color;

  GaugePainter({
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 20;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi * 0.75, // Start angle
      pi * 1.5,  // Sweep angle
      false,
      bgPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (value / maxValue) * pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi * 0.75,
      sweepAngle,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(GaugePainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.color != color;
  }
}
```

### Animated Value Display
```dart
class AnimatedDecibelDisplay extends StatelessWidget {
  final double decibels;

  const AnimatedDecibelDisplay({super.key, required this.decibels});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: decibels),
      duration: const Duration(milliseconds: 100),
      builder: (context, value, child) {
        return Text(
          value.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w200,
            color: _getColor(value),
          ),
        );
      },
    );
  }

  Color _getColor(double db) {
    if (db < 70) return Colors.green;
    if (db < 85) return Colors.amber;
    return Colors.red;
  }
}
```

## Theming & Multiple Modes

### Theme Configuration
```dart
// theme.dart
class AppTheme {
  static ThemeData light({ColorScheme? colorScheme}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme ?? ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      // ... other theme properties
    );
  }

  static ThemeData dark({ColorScheme? colorScheme}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme ?? ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    );
  }
}

// Mode-specific themes
enum AppMode { workplace, nursery, general, music }

extension AppModeTheme on AppMode {
  ColorScheme get lightColorScheme {
    switch (this) {
      case AppMode.workplace:
        return ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        );
      case AppMode.nursery:
        return ColorScheme.fromSeed(
          seedColor: Colors.pink.shade200,
          brightness: Brightness.light,
        );
      case AppMode.music:
        return ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        );
      case AppMode.general:
        return ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        );
    }
  }

  String get displayName {
    switch (this) {
      case AppMode.workplace: return 'Workplace';
      case AppMode.nursery: return 'Nursery';
      case AppMode.music: return 'Music';
      case AppMode.general: return 'General';
    }
  }

  List<DecibelReference> get references {
    switch (this) {
      case AppMode.workplace:
        return workplaceReferences;
      case AppMode.nursery:
        return nurseryReferences;
      case AppMode.music:
        return musicReferences;
      case AppMode.general:
        return generalReferences;
    }
  }
}
```

## Monetization

### Google Mobile Ads Integration
```dart
// pubspec.yaml
// google_mobile_ads: ^4.0.0

import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  // Test IDs - replace with real IDs for production
  static const _adUnitId = 'ca-app-pub-3940256099942544/6300978111';

  void loadBannerAd({required Function(Ad) onLoaded}) {
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _isLoaded = true;
          onLoaded(ad);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  Widget? get bannerWidget {
    if (_bannerAd == null || !_isLoaded) return null;
    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  void dispose() {
    _bannerAd?.dispose();
  }
}
```

### In-App Purchases with RevenueCat
```dart
// pubspec.yaml
// purchases_flutter: ^6.0.0

import 'package:purchases_flutter/purchases_flutter.dart';

class PurchaseService {
  static const _apiKey = 'your_revenuecat_api_key';
  static const _entitlementId = 'pro';

  static Future<void> init() async {
    await Purchases.configure(
      PurchasesConfiguration(_apiKey),
    );
  }

  static Future<bool> isPro() async {
    final customerInfo = await Purchases.getCustomerInfo();
    return customerInfo.entitlements.active.containsKey(_entitlementId);
  }

  static Future<bool> purchaseRemoveAds() async {
    try {
      final offerings = await Purchases.getOfferings();
      final package = offerings.current?.lifetime;

      if (package != null) {
        await Purchases.purchasePackage(package);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> restorePurchases() async {
    await Purchases.restorePurchases();
  }
}
```

## Platform-Specific Configuration

### iOS Info.plist
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to measure sound levels</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### Android AndroidManifest.xml
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

## Commands

When asked to build a Flutter app, always:
1. Use `flutter create --org com.yourcompany app_name` with proper organization
2. Set up Riverpod immediately
3. Configure platform permissions before running
4. Use Material 3 with custom color schemes
5. Structure code feature-first from the start

## Best Practices

1. **Always use const constructors** where possible
2. **Prefer StatelessWidget** - use Riverpod for state
3. **Use extensions** for cleaner code
4. **Handle all error states** in async operations
5. **Test on both iOS and Android** before submission
6. **Use semantic versioning** in pubspec.yaml
