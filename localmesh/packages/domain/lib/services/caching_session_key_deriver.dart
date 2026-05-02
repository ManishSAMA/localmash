import 'session_key_deriver.dart';

class CachingSessionKeyDeriver implements SessionKeyDeriver {
  CachingSessionKeyDeriver(this._inner);

  final SessionKeyDeriver _inner;
  // Stores the Future so concurrent derives for the same pair share one ECDH op.
  final Map<String, Future<List<int>>> _cache = {};

  @override
  Future<List<int>> deriveSessionKey({
    required List<int> myPrivateKey,
    required List<int> theirPublicKey,
    required String myFingerprint,
    required String theirFingerprint,
  }) {
    // ECDH is symmetric — canonical key order avoids duplicate cache entries
    final cacheKey = myFingerprint.compareTo(theirFingerprint) < 0
        ? '$myFingerprint:$theirFingerprint'
        : '$theirFingerprint:$myFingerprint';
    return _cache.putIfAbsent(
      cacheKey,
      () => _inner.deriveSessionKey(
        myPrivateKey: myPrivateKey,
        theirPublicKey: theirPublicKey,
        myFingerprint: myFingerprint,
        theirFingerprint: theirFingerprint,
      ),
    );
  }
}
