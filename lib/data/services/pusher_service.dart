import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:ovowpp/data/services/shared_pref_service.dart';
import '../../core/utils/url_container.dart';
import '../../core/utils/util.dart';
import 'api_service.dart';

class PusherManager with WidgetsBindingObserver {
  static final PusherManager _instance = PusherManager._internal();
  factory PusherManager() => _instance;
  PusherManager._internal();

  final PusherChannelsFlutter pusher = PusherChannelsFlutter.getInstance();
  final List<void Function(PusherEvent)> _listeners = [];

  String? _currentChannelName;
  bool _initialized = false;
  bool _isReconnecting = false;
  Timer? _healthCheckTimer;

  Future<void> init(
    String channelName, {
    required String apiKey,
    required String cluster,
    required Future<dynamic> Function(String channelName, String socketId, dynamic options) onAuthorizer,
    Function(String message, int? code, dynamic e)? onError,
    Function(String message, dynamic e)? onSubscriptionError,
    Function(String channelName, dynamic data)? onSubscriptionSucceeded,
  }) async {
    _currentChannelName = channelName;

    await pusher.init(
      apiKey: apiKey,
      cluster: cluster,
      onConnectionStateChange: _onConnectionStateChange,
      onEvent: _dispatchEvent,
      onError: onError,
      onSubscriptionError: onSubscriptionError,
      onSubscriptionSucceeded: onSubscriptionSucceeded,
      onAuthorizer: onAuthorizer,
      onDecryptionFailure: (_, _) {},
      onMemberAdded: (_, _) {},
      onMemberRemoved: (_, _) {},
    );

    await pusher.subscribe(channelName: channelName);
    await pusher.connect();

    _initialized = true;

    // Start monitoring
    _startHealthCheck();
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  /// Called by the native Pusher SDK whenever the connection state changes.
  void _onConnectionStateChange(dynamic currentState, dynamic previousState) {
    final cur = currentState?.toString().toLowerCase() ?? '';
    final prev = previousState?.toString().toLowerCase() ?? '';
    printX("🔌 Pusher: $prev → $cur");

    if (cur == 'disconnected' && _initialized && !_isReconnecting) {
      printX("⚠️ Pusher disconnected unexpectedly — scheduling reconnect");
      _scheduleReconnect();
    }
  }

  /// Attempts to reconnect with exponential backoff (up to 5 attempts).
  Future<void> _scheduleReconnect() async {
    if (_isReconnecting || _currentChannelName == null) return;
    _isReconnecting = true;

    for (int attempt = 1; attempt <= 5; attempt++) {
      final delaySec = attempt * 2; // 2s, 4s, 6s, 8s, 10s
      printX("🔄 Reconnect attempt $attempt in ${delaySec}s...");
      await Future.delayed(Duration(seconds: delaySec));

      try {
        final state = pusher.connectionState.toLowerCase();
        if (state == 'connected') {
          printX("✅ Already reconnected during wait");
          await _ensureChannelSubscribed();
          _isReconnecting = false;
          return;
        }

        await pusher.connect();
        // Give it a moment to establish the connection
        await Future.delayed(const Duration(seconds: 2));

        final newState = pusher.connectionState.toLowerCase();
        if (newState == 'connected') {
          printX("✅ Reconnected on attempt $attempt");
          await _ensureChannelSubscribed();
          _isReconnecting = false;
          return;
        }
      } catch (e) {
        printE("❌ Reconnect attempt $attempt failed: $e");
      }
    }

    // All 5 attempts failed — fall back to full reinitialisation
    printX("🔄 All reconnect attempts failed — full reinit");
    _isReconnecting = false;
    await _fullReinit();
  }

  /// Re-subscribes to the current channel if it was lost.
  Future<void> _ensureChannelSubscribed() async {
    if (_currentChannelName == null) return;
    try {
      final ch = pusher.getChannel(_currentChannelName!);
      if (ch == null) {
        printX("📡 Re-subscribing to: $_currentChannelName");
        await pusher.subscribe(channelName: _currentChannelName!);
      }
    } catch (e) {
      printE("Channel re-subscribe error: $e");
      // Force subscribe even on error
      try {
        await pusher.subscribe(channelName: _currentChannelName!);
      } catch (_) {}
    }
  }

  /// Tears everything down and re-initialises from scratch.
  Future<void> _fullReinit() async {
    if (_currentChannelName == null) return;
    try {
      await pusher.disconnect();
    } catch (_) {}

    final apiKey =
        SharedPreferenceService.getGeneralSettingData().data?.generalSetting?.pusherConfig?.pusherAppKey ?? "";
    final cluster =
        SharedPreferenceService.getGeneralSettingData().data?.generalSetting?.pusherConfig?.pusherAppCluster ?? "";

    if (apiKey.isEmpty || cluster.isEmpty) return;

    _initialized = false;
    await init(
      _currentChannelName!,
      apiKey: apiKey,
      cluster: cluster,
      onAuthorizer: (channelName, socketId, options) async {
        var authUrl = "${UrlContainer.baseUrl}${UrlContainer.pusherAuthApiURl}/$socketId/$channelName";
        var result = await ApiService.postRequest(authUrl, {});
        return result.responseJson;
      },
      onError: (msg, code, e) => printX("Pusher Error: ${e.toString()}"),
      onSubscriptionError: (msg, e) => printX("Sub Error: $msg"),
      onSubscriptionSucceeded: (channel, data) => printX("✅ Subscribed: $channel"),
    );
  }

  /// Periodic timer that checks connection health every 20 seconds.
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!_initialized || _isReconnecting) return;
      final state = pusher.connectionState.toLowerCase();
      if (state != 'connected') {
        printX("💓 Health check: state=$state — triggering reconnect");
        _scheduleReconnect();
      }
    });
  }

  /// Called when the app comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _initialized) {
      printX("📱 App resumed — verifying Pusher connection");
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    // Small delay to let the OS restore networking
    await Future.delayed(const Duration(milliseconds: 800));
    final connState = pusher.connectionState.toLowerCase();
    printX("📱 Pusher state on resume: $connState");

    if (connState != 'connected') {
      await _fullReinit();
    } else {
      await _ensureChannelSubscribed();
    }
  }

  void _dispatchEvent(PusherEvent event) {
    for (var listener in List.of(_listeners)) {
      try {
        listener(event);
      } catch (e) {
        printE("Listener dispatch error: $e");
      }
    }
  }

  void addListener(void Function(PusherEvent) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
      printX("👂 Listener added. Total: ${_listeners.length}");
    }
  }

  void removeListener(void Function(PusherEvent) listener) {
    _listeners.remove(listener);
  }

  bool isConnected() => pusher.connectionState.toLowerCase() == 'connected';

  /// Public API: force a reconnect from outside (e.g. on screen resume).
  Future<void> forceReconnect(String channelName) async {
    _currentChannelName = channelName;
    final state = pusher.connectionState.toLowerCase();
    printX("🔧 forceReconnect called — state: $state");
    if (state != 'connected') {
      await _fullReinit();
    } else {
      await _ensureChannelSubscribed();
    }
  }

  Future<void> checkAndInitIfNeeded(String channelName) async {
    _currentChannelName = channelName;
    printE(channelName);
    final state = pusher.connectionState.toLowerCase();
    printE(state);
    if (!_initialized || state == 'disconnected' || state == 'disconnecting') {
      printX("🔄 Pusher state: $state. Reinitializing...");

      final apiKey =
          SharedPreferenceService.getGeneralSettingData().data?.generalSetting?.pusherConfig?.pusherAppKey ?? "";
      final cluster =
          SharedPreferenceService.getGeneralSettingData().data?.generalSetting?.pusherConfig?.pusherAppCluster ?? "";
      printE(apiKey);
      printE(cluster);

      _initialized = false;
      await init(
        channelName,
        apiKey: apiKey,
        cluster: cluster,
        onAuthorizer: (channelName, socketId, options) async {
          var authUrl = "${UrlContainer.baseUrl}${UrlContainer.pusherAuthApiURl}/$socketId/$channelName";
          var result = await ApiService.postRequest(authUrl, {});
          return result.responseJson;
        },
        onError: (msg, code, e) => printX("Pusher Error: ${e.toString()}"),
        onSubscriptionError: (msg, e) => printX("Sub Error: $msg"),
        onSubscriptionSucceeded: (channel, data) => printX("✅ Subscribed: $channel"),
      );
    } else if (state == 'connecting') {
      // Already in the middle of connecting — just wait and subscribe
      printX("⏳ Pusher is connecting, waiting...");
      await Future.delayed(const Duration(seconds: 3));
      await _ensureChannelSubscribed();
    } else {
      printX("✅ Pusher already connected: $state");
      await _ensureChannelSubscribed();
    }
  }
}
