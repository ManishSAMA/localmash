/// Set once from [main] before [runApp] for diagnostics uptime display.
DateTime? localMeshAppStartedAt;

void recordLocalMeshAppStart() {
  localMeshAppStartedAt ??= DateTime.now();
}
