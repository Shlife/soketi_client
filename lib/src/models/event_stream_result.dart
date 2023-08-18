import 'package:soketi_client/src/models/connection_error.dart';
import 'package:soketi_client/src/models/connection_state_change.dart';
import 'package:soketi_client/src/soketi/soketi_event.dart';

part 'event_stream_result.g.dart';

class EventStreamResult {
  final ConnectionStateChange? connectionStateChange;
  final ConnectionError? connectionError;
  final SoketiEvent? soketiEvent;

  EventStreamResult({
    this.connectionStateChange,
    this.connectionError,
    this.soketiEvent,
  });

  bool get isConnectionStateChange => connectionStateChange != null;
  bool get isConnectionError => connectionError != null;
  bool get isPusherEvent => soketiEvent != null;

  factory EventStreamResult.fromJson(Map<String, dynamic> json) =>
      _$EventStreamResultFromJson(json);
}
