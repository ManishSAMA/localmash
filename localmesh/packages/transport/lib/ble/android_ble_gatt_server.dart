import 'dart:async';
import 'package:flutter/services.dart';

class AndroidBleGattServer {
  static const MethodChannel _methodChannel =
      MethodChannel('localmesh/ble_gatt_server/methods');
  static const EventChannel _eventChannel =
      EventChannel('localmesh/ble_gatt_server/events');

  Stream<BleGattServerEvent> get events => _eventChannel
      .receiveBroadcastStream()
      .map((dynamic event) => BleGattServerEvent.fromMap(
            Map<Object?, Object?>.from(event as Map),
          ));

  Future<bool> start({required String localName}) async {
    return await _methodChannel.invokeMethod<bool>(
          'start',
          <String, Object?>{'localName': localName},
        ) ??
        false;
  }

  Future<void> stop() async {
    await _methodChannel.invokeMethod<void>('stop');
  }

  Future<bool> notifyPeer(String peerId, Uint8List data) async {
    return await _methodChannel.invokeMethod<bool>(
          'notifyPeer',
          <String, Object?>{'peerId': peerId, 'data': data},
        ) ??
        false;
  }
}

class BleGattServerEvent {
  factory BleGattServerEvent.fromMap(Map<Object?, Object?> map) {
    final rawData = map['data'];
    return BleGattServerEvent(
      type: (map['type'] as String?) ?? 'unknown',
      peerId: (map['peerId'] as String?) ?? '',
      displayName: map['displayName'] as String?,
      data: rawData is Uint8List
          ? rawData
          : rawData is List<int>
              ? Uint8List.fromList(rawData)
              : null,
      message: map['message'] as String?,
    );
  }

  const BleGattServerEvent({
    required this.type,
    required this.peerId,
    this.displayName,
    this.data,
    this.message,
  });

  final String type;
  final String peerId;
  final String? displayName;
  final Uint8List? data;
  final String? message;

  bool get isPeerConnected => type == 'peerConnected';
  bool get isPeerDisconnected => type == 'peerDisconnected';
  bool get isDataReceived => type == 'dataReceived';
  bool get isLog => type == 'log';
}
