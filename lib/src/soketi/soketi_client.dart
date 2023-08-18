import 'dart:async';
import 'dart:convert';

import 'package:soketi_client/soketi_client.dart';
import 'package:soketi_client/src/models/event_stream_result.dart';
import 'package:soketi_client/src/models/connection_error.dart';
import 'package:soketi_client/src/models/connection_state_change.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;

class SoketiClient {
  static SoketiClient? _singleton;
  void Function(ConnectionStateChange?)? _onConnectionStateChange;
  void Function(ConnectionError?)? _onConnectionError;
  Set<String> channelToSubscribe = {};
  Set<String> channelSubscribed = {};

  /// The host to which connections will be made.
  final Uri host;

  /// The number of milliseconds of inactivity at which a "ping" will be
  /// triggered to check the connection.
  ///
  /// The default value is 120,000.
  final int activityTimeout;

  /// The number of milliseconds after a "ping" is sent that the client will
  /// wait to receive a "pong" response from the server before considering the
  /// connection broken and triggering a transition to the disconnected state.
  ///
  /// The default value is 30,000.
  final int pongTimeout;
  String? _socketId;
  StreamController<SoketiEvent> eventData =
      StreamController<SoketiEvent>.broadcast();
  late Stream<SoketiEvent> eventStream = eventData.stream.asBroadcastStream();
  String? get socketId => _socketId;

  bool _isConnected = false;
  bool _hasConnect = false;
  Timer? _pingTimer;
  Timer? _subscriptionTimer;

  /// The soketi appKey
  String appKey;
  IOWebSocketChannel? _channel;
  SoketiClient._(
    this.appKey, {
    required this.host,
    this.activityTimeout = 120000,
    this.pongTimeout = 30000,
    bool autoConnect = true,
  });

  /// Creates a [SoketiClient] -- returns the instance if it's already be called.
  factory SoketiClient(
    String appKey, {
    required Uri host,
    int activityTimeout = 120000,
    int pongTimeout = 30000,
    bool autoConnect = true,
  }) {
    assert(!host.isScheme('HTTP'), "Unsupported URL scheme 'http'");
    assert(!host.isScheme('HTTPS'), "Unsupported URL scheme 'https'");

    _singleton ??= SoketiClient._(
      appKey,
      host: host,
      activityTimeout: activityTimeout,
      pongTimeout: pongTimeout,
      autoConnect: autoConnect,
    );

    if (autoConnect) _singleton!.connect();

    return _singleton!;
  }

  void _sendPing() {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(json.encode({'event': 'pusher:ping', 'data': {}}));
      print('Ping message sent');
    }
  }

  void _handlePong(dynamic data) {
    print('Pong answer reveived');
  }

  /// Subscribes the client to a new channel
  ///
  /// Note that subscriptions should be registered only once with a Soketi
  /// instance. Subscriptions are persisted over disconnection and
  /// re-registered with the server automatically on reconnection. This means
  /// that subscriptions may also be registered before `connect()` is called,
  /// they will be initiated on connection.
  Set<String> subscribe(String channelName) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(json.encode({
        "event": "pusher:subscribe",
        "data": {"channel": channelName}
      }));
      _subscriptionTimer = Timer(const Duration(microseconds: 500), () {
        subscribe(channelName);
      });
      channelSubscribed.add(channelName);
    } else {
      channelToSubscribe.add(channelName);
    }
    return channelSubscribed;
  }

  /// Unsubscribes from a channel using the name of the channel.
  void unsubscribe(String channelName) {
    _channel?.sink.add(json.encode({
      "event": "pusher:unsubscribe",
      "data": {"channel": channelName}
    }));
    channelSubscribed.remove(channelName);
    channelToSubscribe.remove(channelName);
  }

  /// Initiates a connection attempt using the client's
  /// existing connection details
  void connect() {
    if (_isConnected) return;
    print(_singleton!.host.toString());
    _channel = _channel ??
        IOWebSocketChannel.connect(
          '${_singleton!.host.toString()}app/${_singleton!.appKey}?client=js&version=7.0.3&protocol=5',
          protocols: ['wss'],
          connectTimeout: Duration(milliseconds: _singleton!.activityTimeout),
          pingInterval: Duration(milliseconds: _singleton!.pongTimeout),
        );
    _channel!.stream.listen(
      (event) {
        _eventHandler(event);
      },
      onDone: () {
        // Connection is closed
        _isConnected = false;
        _channel = null;
        _pingTimer?.cancel(); // Cancel the ping timer upon disconnection
        // Auto-reconnect after a delay
        Timer(const Duration(milliseconds: 30), () {
          _singleton!.connect();
        });
      },
      onError: (_) {
        _isConnected = false;
        Timer(const Duration(milliseconds: 30), () {
          _singleton!.connect();
        });
      },
    );
    _hasConnect = true;
    _isConnected = true;
    _startPingTimer();
  }

  void _startPingTimer() {
    _cancelPingTimer();
    _pingTimer = Timer.periodic(
        Duration(milliseconds: _singleton!.activityTimeout), (timer) {
      _sendPing();
    });
  }

  void _cancelPingTimer() {
    _pingTimer?.cancel();
  }

  /// Disconnects the client's connection
  Future disconnect() async {
    if (_isConnected) {
      await _channel?.sink.close(status.goingAway);
      _isConnected = false;
      _channel = null;

      _cancelPingTimer();
    }
  }

  bool get isConnected => _isConnected;

  /// Callback that is fired whenever the connection state of the
  /// connection changes. The state typically changes during connection
  /// to Soketi and during disconnection and reconnection.
  void onConnectionStateChange(
      void Function(ConnectionStateChange? state) callback) {
    _onConnectionStateChange = callback;
  }

  /// Callback that indicates either:
  /// - An error message has been received from Soketi, or
  /// - An error has occurred in the client library.
  void onConnectionError(void Function(ConnectionError? error) callback) {
    _onConnectionError = callback;
  }

  void _eventHandler(event) {
    var result = EventStreamResult.fromJson(jsonDecode(event.toString()));

    if (result.isConnectionStateChange) {
      // _socketId = await _channel.invokeMethod('getSocketId');

      if (_onConnectionStateChange != null) {
        _onConnectionStateChange!(result.connectionStateChange);
      }
    }

    if (result.isConnectionError) {
      if (_onConnectionError != null) {
        _onConnectionError!(result.connectionError);
      }
    }

    final data = jsonDecode(event.toString());

    if (data is Map<String, dynamic>) {
      final soketiEvent = SoketiEvent.fromJson(data);
      print(soketiEvent.eventName);
      if (soketiEvent.eventName == 'pusher:error') {
        _onConnectionError?.call(ConnectionError(
          code: soketiEvent.data?['code'],
          message: soketiEvent.data?['message'],
        ));
      } else if (soketiEvent.eventName == 'pusher:connection_state_change') {
        _onConnectionStateChange?.call(ConnectionStateChange(
          currentState: soketiEvent.data?['current'],
          previousState: soketiEvent.data?['previous'],
        ));
      } else if (soketiEvent.eventName == 'pusher:ping') {
        print('Received ping event: ${soketiEvent.data}');
        _channel?.sink.add(json.encode({'event': 'pusher:pong', 'data': {}}));
      } else if (soketiEvent.eventName == 'pusher:pong') {
        _handlePong(soketiEvent);
      } else if (soketiEvent.eventName == 'pusher:connection_established') {
        while (channelToSubscribe.isNotEmpty) {
          subscribe(channelToSubscribe.elementAt(0));

          channelToSubscribe.remove(channelToSubscribe.elementAt(0));
        }
        if (_hasConnect) {
          for (var channel in channelSubscribed) {
            subscribe(channel);
          }
        }
        print('${soketiEvent.eventName} - ${soketiEvent.data}');
        if (soketiEvent.data is Map<String, dynamic>) {
          if (data['socket_id'] != null) {
            _socketId = data['socket_id'];
          }
        }
      } else if ((soketiEvent.eventName ==
          'pusher_internal:subscription_succeeded')) {
        print(soketiEvent.eventName);
        _subscriptionTimer?.cancel();
      } else {
        eventData.add(soketiEvent);
      }
    }
  }
}
