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

  /// The host to which connections will be made.
  final Uri host;

  /// The number of seconds of inactivity at which a "ping" will be
  /// triggered to check the connection.
  final int activityTimeout;

  /// The number of seconds after a "ping" is sent that the client will
  /// wait to receive a "pong" response from the server before considering the
  /// connection broken and triggering a transition to the disconnected state.
  ///
  /// The default value is 30.
  final int pongTimeout;
  String? _socketId;
  StreamController<SoketiEvent> eventData =
      StreamController<SoketiEvent>.broadcast();
  late Stream<SoketiEvent> eventStream = eventData.stream.asBroadcastStream();
  String? get socketId => _socketId;

  bool _isConnected = false;
  Timer? _pingTimer;

  /// The soketi appKey
  String appKey;
  IOWebSocketChannel? _channel;
  SoketiClient._(
    this.appKey, {
    required this.host,
    this.activityTimeout = 120,
    this.pongTimeout = 30,
    bool autoConnect = true,
  });

  /// Creates a [SoketiClient] -- returns the instance if it's already be called.
  factory SoketiClient(
    String appKey, {
    required Uri host,
    int activityTimeout = 120,
    int pongTimeout = 30,
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
    _channel?.sink.add(json.encode({'event': 'pusher:ping', 'data': {}}));
    print('ping message send');
    _pingTimer = Timer(Duration(microseconds: pongTimeout), _sendPing);
  }

  void _handlePong(dynamic data) {
      print('pong answer reveived');
  }

  /// Subscribes the client to a new channel
  ///
  /// Note that subscriptions should be registered only once with a Soketi
  /// instance. Subscriptions are persisted over disconnection and
  /// re-registered with the server automatically on reconnection. This means
  /// that subscriptions may also be registered before `connect()` is called,
  /// they will be initiated on connection.
  void subscribe(String channelName) {
    if (_channel != null) {
      _channel!.sink.add(json.encode({
        "event": "pusher:subscribe",
        "data": {"channel": channelName}
      }));
    } else {
      channelToSubscribe.add(channelName);
    }
  }

  /// Unsubscribes from a channel using the name of the channel.
  void unsubscribe(String channelName) {
    _channel?.sink.add(json.encode({
      "event": "pusher:unsubscribe",
      "data": {"channel": channelName}
    }));
    channelToSubscribe.remove(channelName);
  }

  /// Initiates a connection attempt using the client's
  /// existing connection details
  void connect() {
    if (_channel == null) {
      print(_singleton!.host.toString());
      _channel = _channel ??
          IOWebSocketChannel.connect(
            '${_singleton!.host.toString()}app/${_singleton!.appKey}?client=js&version=7.0.3&protocol=5',
            protocols: ['wss'],
            connectTimeout: Duration(seconds: _singleton!.activityTimeout),
            pingInterval: Duration(seconds: _singleton!.pongTimeout),
          );
      while (channelToSubscribe.isNotEmpty) {
        subscribe(channelToSubscribe.elementAt(0));
        channelToSubscribe
            .remove(channelToSubscribe.remove(channelToSubscribe.elementAt(0)));
      }
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
          Timer(const Duration(seconds: 30), () {
            _singleton!.connect();
          });
        },
        onError: (_) {
          Timer(const Duration(seconds: 30), () {
            _singleton!.connect();
          });
        },
      );

      _isConnected = true;
      _sendPing(); // Start sending ping events
    }
  }

  /// Disconnects the client's connection
  Future disconnect() async {
    if (_isConnected) {
      await _channel?.sink.close(status.goingAway);
      _isConnected = false;
      _channel = null;
      _pingTimer?.cancel(); // Cancel the ping timer upon disconnection
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
      final soketiEvent = SoketiEvent.fromJson(jsonDecode(event.toString()));
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
        print('${soketiEvent.eventName} - ${soketiEvent.data}');
        if (soketiEvent.data is Map<String, dynamic>) {
          if (data['socket_id'] != null) {
            _socketId = data['socket_id'];
          }
        }
      } else if (soketiEvent.eventName?.contains('pusher') ?? false) {
        print('${soketiEvent.eventName} - ${soketiEvent.data}');
      } else {
        eventData.sink.add(soketiEvent);
      }
    }
  }
}
