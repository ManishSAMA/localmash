/// Logical clock for causal ordering of messages across nodes.
/// See Lamport 1978, "Time, Clocks, and the Ordering of Events in a
/// Distributed System." Used by the gossip router and sync protocol to
/// establish a total order on events without requiring wall-clock sync.
class LamportClock {
  LamportClock({int initialValue = 0}) : _value = initialValue;

  int _value;

  /// Current value of the clock. Read-only snapshot.
  int get value => _value;

  /// Increments the clock by 1 and returns the new value.
  /// Call this when creating a new local event (e.g., sending a message).
  int tick() {
    _value += 1;
    return _value;
  }

  /// Merges a received timestamp into the local clock.
  /// Sets the clock to max(local, received) + 1, per Lamport's rules.
  /// Call this when receiving a message from another node.
  int merge(int receivedTs) {
    _value = (_value > receivedTs ? _value : receivedTs) + 1;
    return _value;
  }

  /// Resets the clock. Primarily for testing.
  void reset() {
    _value = 0;
  }
}
