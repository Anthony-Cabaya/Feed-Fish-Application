import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const FishFeedingApp());
}

class FishFeedingApp extends StatelessWidget {
  const FishFeedingApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final double capacityKg = 0.5;
  final double emptyThreshold = 9.5;
  final double fullThreshold = 3.2;
  final double lowThreshold = 5.0;

  int countdownRemaining = 0;
  int dropsToday = 0;
  double stockRemaining = 0.0;
  Duration dropInterval = const Duration(hours: 2, minutes: 30);
  String? notificationText;
  Color? notificationColor;
  late AnimationController _fadeController;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref('fish_feeder');
  bool _isInitializing = true;
  Timer? _notificationTimer;
  Timer? _dropTimer;
  DateTime? _lastResetDate;
  Timer? _stockCheckTimer;
  bool _showingEmptyNotification = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _initializeData();
    _setupDailyResetChecker();
    _startStockMonitoring();
    _startCountdownListener();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _notificationTimer?.cancel();
    _dropTimer?.cancel();
    _stockCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      final snapshot = await _dbRef.once();
      if (snapshot.snapshot.value != null) {
        final data = snapshot.snapshot.value as Map<dynamic, dynamic>;

        setState(() {
          countdownRemaining = data['data']['countdown_remaining'] ?? 0;
          dropsToday = data['status']['drops_today'] ?? 0;
          stockRemaining =
              (data['status']['stock_remaining'] ?? 0.0).toDouble();
          _isInitializing = false;
        });
      }

      _dbRef.child('data/countdown_remaining').onValue.listen((event) {
        if (mounted && event.snapshot.value != null) {
          setState(() {
            countdownRemaining = event.snapshot.value as int;
          });
        }
      });

      _dbRef.child('status/drops_today').onValue.listen((event) {
        if (mounted && event.snapshot.value != null) {
          setState(() {
            dropsToday = event.snapshot.value as int;
          });
        }
      });

      _dbRef.child('status/stock_remaining').onValue.listen((event) {
        if (mounted && event.snapshot.value != null) {
          setState(() {
            stockRemaining = (event.snapshot.value as num).toDouble();
          });
        }
      });
    } catch (e) {
      _showNotification('Error initializing: $e', Colors.red);
      setState(() => _isInitializing = false);
    }
  }

  void _startCountdownListener() {
    _dbRef.child('data/countdown_remaining').onValue.listen((event) {
      if (mounted && event.snapshot.value != null) {
        setState(() {
          countdownRemaining = event.snapshot.value as int;
        });
      }
    });
  }

  Future<void> _incrementDropsToday() async {
    try {
      await _dbRef.child('status/drops_today').set(ServerValue.increment(1));
      _showNotification('Fed fish', Colors.green);
    } catch (e) {
      _showNotification('Failed to feed: $e', Colors.red);
    }
  }

  void _startStockMonitoring() {
    _stockCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkStockStatus(stockRemaining);
    });
  }

  void _setupDailyResetChecker() {
    Timer.periodic(const Duration(minutes: 1), (timer) {
      final now = DateTime.now();
      if (_lastResetDate == null || now.day != _lastResetDate!.day) {
        _resetDailyCount();
        _lastResetDate = now;
      }
    });
  }

  Future<void> _resetDailyCount() async {
    try {
      await _dbRef.child('status/drops_today').set(0);
      if (mounted) {
        setState(() {
          dropsToday = 0;
        });
      }
    } catch (e) {
      _showNotification('Failed to reset daily count: $e', Colors.red);
    }
  }

  void _checkStockStatus(double stock) {
    if (stock >= emptyThreshold) {
      if (!_showingEmptyNotification) {
        _showPersistentNotification(
          'Container is empty! Please refill fish food.',
          Colors.orange,
        );
        _showingEmptyNotification = true;
      }
    } else if (stock <= fullThreshold) {
      if (_showingEmptyNotification) {
        _hideNotification();
        _showingEmptyNotification = false;
      }
      _showNotification('Container is full', Colors.green);
    } else if (stock <= lowThreshold) {
      if (!_showingEmptyNotification) {
        _showNotification('Fish food is getting low', Colors.orange);
      }
    } else {
      if (_showingEmptyNotification) {
        _hideNotification();
        _showingEmptyNotification = false;
      }
    }
  }

  void _showNotification(String text, Color color) {
    setState(() {
      notificationText = text;
      notificationColor = color;
    });
    _fadeController.forward(from: 0);
    _notificationTimer?.cancel();
    _notificationTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _fadeController.reverse();
      }
    });
  }

  void _showPersistentNotification(String text, Color color) {
    setState(() {
      notificationText = text;
      notificationColor = color;
    });
    _fadeController.forward(from: 0);
    _notificationTimer?.cancel();
  }

  void _hideNotification() {
    if (mounted) {
      _fadeController.reverse();
    }
  }

  Future<void> _sendCommand(int mode) async {
    try {
      await _dbRef.child('commands/mode').set(mode);
      _showNotification(
        mode == 1 ? 'Manual feed activated' : 'Flush activated',
        Colors.green,
      );

      if (mode == 1) {
        await _incrementDropsToday();
      }
    } catch (e) {
      _showNotification('Failed to send command: $e', Colors.red);
    }
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final secs = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$secs";
  }

  Future<void> _showManualFeedConfirmation() async {
    if (stockRemaining >= emptyThreshold || stockRemaining <= 0.5) {
      _showNotification(
        stockRemaining >= emptyThreshold
            ? 'Cannot feed: Container is empty!'
            : 'Cannot feed: Stock is too low!',
        Colors.red,
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Manual Feed'),
          content: const Text(
            'Are you sure you want to manually feed the fish?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Feed'),
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      _sendCommand(1);
    }
  }

  Future<void> _showFlushConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Flush'),
          content: const Text(
            'Are you sure you want to flush the fish feeder?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Flush'),
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      _sendCommand(2);
    }
  }

  Future<void> _setFeedingInterval() async {
    Duration initialDuration = Duration(seconds: countdownRemaining);
    Duration temp = initialDuration;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (_) => Container(
            height: 300,
            decoration: const BoxDecoration(
              color: Color(0xFF15141E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    SizedBox(
                      height: 200,
                      child: CupertinoTimerPicker(
                        mode: CupertinoTimerPickerMode.hms,
                        initialTimerDuration: initialDuration,
                        onTimerDurationChanged: (duration) {
                          setState(() => temp = duration);
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              final seconds = temp.inSeconds;
                              await _dbRef
                                  .child('commands/countdown')
                                  .set(seconds);
                              await _dbRef
                                  .child('data/countdown_remaining')
                                  .set(seconds);
                              setState(() {
                                dropInterval = temp;
                                countdownRemaining = seconds;
                              });
                              Navigator.pop(context);
                              _showNotification(
                                'Interval set successfully',
                                Colors.green,
                              );
                            } catch (e) {
                              Navigator.pop(context);
                              _showNotification(
                                'Failed to set interval: $e',
                                Colors.red,
                              );
                            }
                          },
                          child: const Text(
                            'Set Feeding Interval',
                            style: TextStyle(
                              color: Colors.blueAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double pct;
    if (stockRemaining >= emptyThreshold) {
      pct = 1.0;
    } else if (stockRemaining <= fullThreshold) {
      pct = 0.0;
    } else {
      pct = (stockRemaining - fullThreshold) / (emptyThreshold - fullThreshold);
    }
    final int displayPercent = ((1 - pct) * 100).clamp(0, 100).round();
    final bool feedButtonDisabled =
        stockRemaining >= emptyThreshold || stockRemaining <= 0.5;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Fish Feeder'),
        centerTitle: true,
      ),
      body:
          _isInitializing
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C5CE7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Fish Food Remaining',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Container Capacity: 1/2 kg',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CustomPaint(
                                        size: const Size(40, 40),
                                        painter: _CirclePainter(
                                          percentage: pct,
                                          backgroundColor: Colors.white24,
                                          progressColor:
                                              stockRemaining >= emptyThreshold
                                                  ? Colors.red
                                                  : Colors.white,
                                        ),
                                      ),
                                      Text(
                                        '$displayPercent%',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              stockRemaining >= emptyThreshold
                                                  ? Colors.red[100]
                                                  : Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(bottom: 32),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C5CE7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Feeding Schedule',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.grain,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Today's Fish Food Drop: $dropsToday",
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.timer,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Next Feeding: ${_formatDuration(countdownRemaining)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed:
                                feedButtonDisabled
                                    ? null
                                    : _showManualFeedConfirmation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  feedButtonDisabled
                                      ? Colors.grey
                                      : Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Manual Feed',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _showFlushConfirmation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Flush System',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _setFeedingInterval,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Set Feeding Interval',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (notificationText != null)
                    FadeTransition(
                      opacity: _fadeController,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        color: notificationColor ?? Colors.black87,
                        child: Text(
                          notificationText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double percentage;
  final Color backgroundColor;
  final Color progressColor;

  _CirclePainter({
    required this.percentage,
    required this.backgroundColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint backgroundPaint =
        Paint()
          ..color = backgroundColor
          ..strokeWidth = 6
          ..style = PaintingStyle.stroke;

    final Paint progressPaint =
        Paint()
          ..color = progressColor
          ..strokeWidth = 6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);

    canvas.drawCircle(center, radius, backgroundPaint);

    double sweepAngle = 2 * math.pi * percentage;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
