import '../entities/peer.dart';

abstract class PeerRepository {
  Future<void> savePeer(Peer peer);
  Future<Peer?> getPeerById(String id);
  Future<List<Peer>> getAllPeers();
  Future<void> removePeer(String id);
}
