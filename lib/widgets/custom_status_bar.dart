// File: lib/widgets/custom_status_bar.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import '../services/flight_tracking_service.dart';
import '../services/gps_sensor_service.dart';

/// Custom system status bar widget that replaces the native Android status bar
/// 
/// Displays:
/// - Current time
/// - Battery level with icon
/// - GPS status (enabled/disabled) - now reactive via Provider
/// - Flight tracking status (in flight indicator)
/// - Connectivity status (WiFi/mobile)
/// 
/// The GPS status now reacts immediately to GpsSensorService changes,
/// no longer uses polling with 3-second delay
class CustomStatusBar extends StatefulWidget {
  final double height;
  final Color backgroundColor;
  final Color textColor;
  final bool showFlightStatus;

  const CustomStatusBar({
    super.key,
    this.height = 30.0,
    this.backgroundColor = const Color(0xFF1F1F1F),
    this.textColor = Colors.white,
    this.showFlightStatus = true,
  });

  @override
  State<CustomStatusBar> createState() => _CustomStatusBarState();
}

class _CustomStatusBarState extends State<CustomStatusBar> with TickerProviderStateMixin {
  late Timer _timeTimer;
  late Timer _batteryTimer;
  late AnimationController _gpsPulseController;
  
  String _currentTime = '00:00';
  int _batteryLevel = 100;
  final bool _isCharging = false;
  bool _isInFlight = false;
  List<ConnectivityResult> _connectivity = [ConnectivityResult.none];

  final Battery _battery = Battery();
  final Connectivity _connectivity_service = Connectivity();

  @override
  void initState() {
    super.initState();
    
    // Animation for GPS pulsing (searching) state
    _gpsPulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
    
    _initializeStatusUpdates();
  }

  void _initializeStatusUpdates() {
    // Update time every second
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTime();
    });

    // Update battery every 5 seconds
    _batteryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateBattery();
    });

    // Initial updates
    _updateTime();
    _updateBattery();
    _updateConnectivity();
    
    // Listen to connectivity changes
    _connectivity_service.onConnectivityChanged.listen((result) {
      if (mounted) {
        setState(() {
          _connectivity = result;
        });
      }
    });
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    final hour = '${now.hour}'.padLeft(2, '0');
    final minute = '${now.minute}'.padLeft(2, '0');
    
    setState(() {
      _currentTime = '$hour:$minute';
    });
  }

  void _updateBattery() async {
    if (!mounted) return;
    try {
      final level = await _battery.batteryLevel;
      setState(() {
        _batteryLevel = level;
      });
    } catch (e) {
      debugPrint('Error reading battery: $e');
    }
  }

  void _updateConnectivity() async {
    if (!mounted) return;
    try {
      final result = await _connectivity_service.checkConnectivity();
      setState(() {
        _connectivity = result;
      });
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Monitor flight status from provider
    try {
      final flightService = context.watch<FlightTrackingService>();
      if (_isInFlight != flightService.isInFlight) {
        _isInFlight = flightService.isInFlight;
      }
    } catch (_) {
      // FlightTrackingService might not be available in all contexts
    }
  }

  IconData _getBatteryIcon() {
    if (_isCharging) {
      return Icons.battery_charging_full;
    }
    
    if (_batteryLevel > 80) {
      return Icons.battery_full;
    } else if (_batteryLevel > 50) {
      return Icons.battery_6_bar;
    } else if (_batteryLevel > 20) {
      return Icons.battery_3_bar;
    } else {
      return Icons.battery_alert;
    }
  }

  Color _getBatteryColor() {
    if (_isCharging) {
      return Colors.green;
    }
    
    if (_batteryLevel > 50) {
      return Colors.green;
    } else if (_batteryLevel > 20) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  /// Build GPS indicator widget with intelligent state display
  /// Shows red (off), orange pulsing (searching), or green (signal OK)
  Widget _buildGpsIndicator(bool isTracking, bool hasGpsSignal) {
    final status = _getGpsStatus(isTracking, hasGpsSignal);
    final isSearching = status['isSearching'] as bool;
    final color = status['color'] as Color;
    final icon = status['icon'] as IconData;
    final tooltip = status['tooltip'] as String;
    
    if (isSearching) {
      // Pulsing animation for searching state
      return Tooltip(
        message: tooltip,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(_gpsPulseController),
          child: Icon(
            icon,
            size: 14.0,
            color: color,
          ),
        ),
      );
    } else {
      // Static icon for off or signal OK
      return Tooltip(
        message: tooltip,
        child: Icon(
          icon,
          size: 14.0,
          color: color,
        ),
      );
    }
  }

  /// Determine GPS status based on tracking state and signal
  /// Returns: {color, icon, isSearching (pulsing), tooltip}
  Map<String, dynamic> _getGpsStatus(bool isTracking, bool hasGpsSignal) {
    if (!isTracking) {
      // GPS is not tracking
      return {
        'color': Colors.red,
        'icon': Icons.gps_off,
        'isSearching': false,
        'tooltip': 'GPS Disabled',
      };
    }
    
    if (!hasGpsSignal) {
      // GPS tracking enabled but searching for signal
      return {
        'color': Colors.orange,
        'icon': Icons.gps_fixed,
        'isSearching': true,
        'tooltip': 'Searching for GPS signal...',
      };
    }
    
    // GPS tracking enabled and has signal
    return {
      'color': Colors.green,
      'icon': Icons.gps_fixed,
      'isSearching': false,
      'tooltip': 'GPS Signal OK',
    };
  }

  IconData _getConnectivityIcon() {
    if (_connectivity.isEmpty) {
      return Icons.wifi_off;
    }
    final result = _connectivity.first;
    switch (result) {
      case ConnectivityResult.wifi:
        return Icons.wifi;
      case ConnectivityResult.mobile:
        return Icons.signal_cellular_alt;
      case ConnectivityResult.none:
        return Icons.wifi_off;
      default:
        return Icons.signal_cellular_alt;
    }
  }

  @override
  void dispose() {
    _timeTimer.cancel();
    _batteryTimer.cancel();
    _gpsPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch GpsSensorService for real-time GPS status updates
    // This widget rebuilds whenever isTracking or lastPosition change
    final gpsSensorService = context.watch<GpsSensorService>();
    final isTracking = gpsSensorService.isTracking;
    final hasGpsSignal = gpsSensorService.lastPosition != null;

    return Container(
      height: widget.height,
      color: widget.backgroundColor,
      padding: EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side: Time
          Text(
            _currentTime,
            style: TextStyle(
              color: widget.textColor,
              fontSize: 12.0,
              fontWeight: FontWeight.w600,
            ),
          ),

          // Center: Flight status indicator (if in flight)
          if (widget.showFlightStatus && _isInFlight)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.flight_takeoff,
                    size: 12.0,
                    color: Colors.red,
                  ),
                  SizedBox(width: 4.0),
                  Text(
                    'IN FLIGHT',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Right side: GPS, Battery, Connectivity
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // GPS indicator with intelligent state display
              _buildGpsIndicator(isTracking, hasGpsSignal),
              
              SizedBox(width: 8.0),

              // Connectivity icon
              Tooltip(
                message: _connectivity.isNotEmpty && _connectivity.first == ConnectivityResult.wifi
                    ? 'WiFi Connected'
                    : _connectivity.isNotEmpty && _connectivity.first == ConnectivityResult.mobile
                        ? 'Mobile Data'
                        : 'No Connection',
                child: Icon(
                  _getConnectivityIcon(),
                  size: 14.0,
                  color: _connectivity.isEmpty || _connectivity.first == ConnectivityResult.none
                      ? Colors.grey
                      : widget.textColor,
                ),
              ),

              SizedBox(width: 8.0),

              // Battery level
              Tooltip(
                message: 'Battery: $_batteryLevel%',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getBatteryIcon(),
                      size: 14.0,
                      color: _getBatteryColor(),
                    ),
                    SizedBox(width: 2.0),
                    Text(
                      '$_batteryLevel%',
                      style: TextStyle(
                        color: _getBatteryColor(),
                        fontSize: 10.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

