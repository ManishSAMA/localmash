import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';

import 'ble/ble_transport.dart';
import 'transport.dart';

class TransportManager {
  TransportManager([List<Transport>? transports]) {
    if (transports != null) _transports.addAll(transports);
  }

  final List<Transport> _transports = [];

  Stream<PeerEvent> get peerEvents {
    final streams = _transports.map((t) => t.peerEvents).toList();
    return StreamGroup.merge(streams);
  }

  Stream<TransportPayload> get incomingData {
    final streams = _transports.map((t) => t.incomingData).toList();
    return StreamGroup.merge(streams);
  }

  Stream<TransportStatus> get status {
    final streams = _transports.map((t) => t.status).toList();
    return StreamGroup.merge(streams);
  }

  Future<void> start() async {
    final failures = <String>[];
    await Future.wait(_transports.map((transport) async {
      try {
        await transport.start();
      } catch (e) {
        failures.add('${transport.name}: $e');
        debugPrint(
          '[TRANSPORT][MANAGER] ${transport.name} failed to start: $e',
        );
      }
    }));

    if (_transports.any((t) => t.state == TransportState.running)) return;
    if (failures.isEmpty) {
      throw TransportException(
          'manager', 'No transports reached running state');
    }
    throw TransportException(
      'manager',
      'No transports reached running state: ${failures.join('; ')}',
    );
  }

  Future<void> stop() async {
    for (final transport in _transports) {
      await transport.stop();
    }
  }

  Future<void> updateBatterySaver(bool enabled) async {
    await Future.wait(_transports.map((t) => t.updateBatterySaver(enabled)));
  }

  Future<void> sendTo(String peerId, Uint8List data) async {
    var attempted = false;
    var succeeded = false;
    Object? lastError;

    for (final transport in _transports) {
      if (!transport.hasPeer(peerId)) continue;
      attempted = true;
      try {
        await transport.sendTo(peerId, data);
        succeeded = true;
      } catch (e) {
        lastError = e;
        debugPrint(
          '[TRANSPORT][MANAGER] sendTo failed via ${transport.name} for $peerId: $e',
        );
      }
    }

    if (succeeded) return;
    if (attempted && lastError != null) {
      throw TransportException(
          'manager', 'All transports failed for $peerId: $lastError');
    }
    throw TransportException(
        'manager', 'No connected transport for peer $peerId');
  }

  Future<void> broadcast(Uint8List data) async {
    var attempted = false;
    var succeeded = false;
    Object? lastError;

    for (final transport in _transports) {
      if (transport.state != TransportState.running ||
          transport.connectedPeers.isEmpty) {
        continue;
      }
      attempted = true;
      try {
        await transport.broadcast(data);
        succeeded = true;
      } catch (e) {
        lastError = e;
        debugPrint(
          '[TRANSPORT][MANAGER] broadcast failed via ${transport.name}: $e',
        );
      }
    }

    if (succeeded) return;
    if (attempted && lastError != null) {
      throw TransportException(
          'manager', 'All connected transports failed: $lastError');
    }
    throw TransportException('manager', 'No connected transport peers');
  }

  List<Transport> get transports => List.unmodifiable(_transports);

  List<String> get connectedPeers {
    final seen = <String>{};
    final result = <String>[];
    for (final t in _transports) {
      for (final p in t.connectedPeers) {
        if (seen.add(p)) result.add(p);
      }
    }
    return result;
  }

  Stream<String> get transportErrors {
    final ble = _transports.whereType<BleTransport>().firstOrNull;
    return ble?.transportErrors ?? const Stream.empty();
  }

  void addTransport(Transport transport) {
    _transports.add(transport);
  }
}
