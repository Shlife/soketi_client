// YOU SHOULD MODIFY BY HAND

part of 'soketi_event.dart';

SoketiEvent _$SoketiEventFromJson(Map<String, dynamic> json) {
  return SoketiEvent(
    channelName: json['channel']?.toString(),
    eventName: json['event']?.toString(),
    data: jsonDecode(json['data'].toString()),
    userId: json['userId']?.toString(),
  );
}

