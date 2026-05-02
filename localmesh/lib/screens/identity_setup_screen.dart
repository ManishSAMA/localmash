import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to LocalMesh')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Choose a display name', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. Manish',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _busy ? null : _createIdentity,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Generate Identity'),
            ),
          ],
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
      // Invalidating the provider causes AppRouter to re-evaluate and
      // automatically advance to the permissions screen.
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
