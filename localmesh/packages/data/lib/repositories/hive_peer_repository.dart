import 'package:domain/domain.dart';
import '../datasources/hive_local_datasource.dart';

class HivePeerRepository implements PeerRepository {
  final Set<String> _connectedIds = {};

  @override
  Future<void> savePeer(Peer peer) async {
    await HiveLocalDataSource.peersBox.put(peer.id, peer);
  }

  @override
  Future<Peer?> getPeerById(String id) async {
    final peer = HiveLocalDataSource.peersBox.get(id);
    if (peer == null) return null;
    return peer.copyWith(isConnected: _connectedIds.contains(id));
  }

  @override
  Future<List<Peer>> getAllPeers() async {
    return HiveLocalDataSource.peersBox.values
        .map((p) => p.copyWith(isConnected: _connectedIds.contains(p.id)))
        .toList();
  }

  @override
  Future<List<Peer>> getConnectedPeers() async {
    final all = await getAllPeers();
    return all.where((p) => p.isConnected).toList();
  }

  @override
  Future<List<Peer>> getTrustedPeers() async {
    final all = await getAllPeers();
    return all.where((p) => p.isTrusted).toList();
  }

  @override
  Future<void> updatePeerConnectionStatus(String id, bool isConnected) async {
    if (isConnected) {
      _connectedIds.add(id);
    } else {
      _connectedIds.remove(id);
    }
  }

  @override
  Future<void> trustPeer(String id) async {
    final peer = HiveLocalDataSource.peersBox.get(id);
    if (peer == null) return;
    await HiveLocalDataSource.peersBox.put(id, peer.copyWith(isTrusted: true));
  }

  @override
  Future<void> removePeer(String id) async {
    await HiveLocalDataSource.peersBox.delete(id);
    _connectedIds.remove(id);
  }
}
