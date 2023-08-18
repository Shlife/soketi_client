// YOU SHOULD MODIFY BY HAND

part of 'event_stream_result.dart';

EventStreamResult _$EventStreamResultFromJson(Map<String, dynamic> json) {
  return EventStreamResult(
    connectionStateChange: json['connectionStateChange'] == null
        ? null
        : ConnectionStateChange.fromJson(
            json['connectionStateChange'] as Map<String, dynamic>),
    connectionError: json['connectionError'] == null
        ? null
        : ConnectionError.fromJson(
            json['connectionError'] as Map<String, dynamic>),
    soketiEvent: json['pusherEvent'] == null
        ? null
        : SoketiEvent.fromJson(json['pusherEvent'] as Map<String, dynamic>),
  );
}
