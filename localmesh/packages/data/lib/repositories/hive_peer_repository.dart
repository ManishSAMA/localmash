import 'package:domain/domain.dart';

class HivePeerRepository implements PeerRepository {
  @override
  Future<void> savePeer(Peer peer) {
    throw UnimplementedError();
  }

  @override
  Future<Peer?> getPeerById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<Peer>> getAllPeers() {
    throw UnimplementedError();
  }

  @override
  Future<void> removePeer(String id) {
    throw UnimplementedError();
  }
}
