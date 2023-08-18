import 'dart:convert';

part 'soketi_event.g.dart';

class SoketiEvent {
  /// The name of the channel that the event was triggered on. Not present
  /// in events without an associated channel, For example "pusher:error" events
  /// relating to the connection.
  final String? channelName;

  /// The name of the event.
  final String? eventName;

  /// The data that was passed when the event was triggered.
  final Map<String, dynamic>? data;

  /// The ID of the user who triggered the event. Only present in
  /// client event on presence channels.
  final String? userId;

  SoketiEvent({
    this.channelName,
    this.eventName,
    this.data,
    this.userId,
  });

  factory SoketiEvent.fromJson(Map<String, dynamic> json) =>
      _$SoketiEventFromJson(json);
}
