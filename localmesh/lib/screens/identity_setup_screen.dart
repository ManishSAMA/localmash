import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

class IdentitySetupScreen extends ConsumerStatefulWidget {
  const IdentitySetupScreen({super.key});

  @override
  ConsumerState<IdentitySetupScreen> createState() =>
      _IdentitySetupScreenState();
}

class _IdentitySetupScreenState extends ConsumerState<IdentitySetupScreen> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: Icon(Icons.router_outlined, color: scheme.primary),
        title: const Text('LOCAL_MESH'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'ONBOARDING',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'IDENTITY SETUP',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a display name. A new Ed25519 / X25519 keypair is '
                'generated locally — keys never leave your device.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: LocalMeshColors.textSecondary,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 28),
              const Text(
                'DISPLAY NAME',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  letterSpacing: 1,
                  color: LocalMeshColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                style: const TextStyle(fontSize: 16),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. Manish',
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy ? null : _createIdentity,
                child: _busy
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0D1117),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('GENERATING KEYPAIR…'),
                        ],
                      )
                    : const Text('GENERATE IDENTITY'),
              ),
              if (_busy) ...[
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: LocalMeshColors.borderMuted,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Deriving keys • sealing identity vault',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 11,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createIdentity() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final useCase = ref.read(createIdentityProvider);
      await useCase(_controller.text.trim());
      ref.invalidate(currentIdentityProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _busy = false);
      }
    }
  }
}
