import '../entities/peer.dart';

abstract class PeerRepository {
  Future<void> savePeer(Peer peer);
  Future<Peer?> getPeerById(String id);
  Future<List<Peer>> getAllPeers();
  Future<List<Peer>> getConnectedPeers();
  Future<List<Peer>> getTrustedPeers();
  Future<void> updatePeerConnectionStatus(String id, bool isConnected);
  Future<void> trustPeer(String id);
  Future<void> removePeer(String id);
}
