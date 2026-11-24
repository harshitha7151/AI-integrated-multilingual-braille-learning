import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'live_demo_client.dart';

class LiveDemoConnectPage extends StatefulWidget {
  const LiveDemoConnectPage({super.key, required this.client});
  final LiveDemoClient client;

  @override
  State<LiveDemoConnectPage> createState() => _LiveDemoConnectPageState();
}

class _LiveDemoConnectPageState extends State<LiveDemoConnectPage> {
  final _session = TextEditingController();
  final _pairing = TextEditingController();
  final _server = TextEditingController();
  bool _consent = false;
  bool _shareTranscript = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.client.onSessionExpired = () {
      if (mounted) {
        setState(
          () => _message =
              'The live demo session expired. Pair again to reconnect.',
        );
      }
    };
    _server.text = widget.client.baseUri.toString();
    if (widget.client.isConnected) {
      _session.text = widget.client.sessionId ?? '';
      _message = 'Connected to the live demonstration.';
      _consent = true;
      _shareTranscript = widget.client.includeTranscripts;
    }
  }

  @override
  void dispose() {
    widget.client.onSessionExpired = null;
    _session.dispose();
    _pairing.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_consent) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      widget.client.configureBaseUri(Uri.parse(_server.text.trim()));
      await widget.client.connect(_session.text.trim(), _pairing.text.trim());
      widget.client.includeTranscripts = _shareTranscript;
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() => _message = 'Connected. Activity sharing is active.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not connect: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disconnect() async {
    await widget.client.disconnect();
    HapticFeedback.selectionClick();
    if (mounted) {
      setState(
        () => _message = 'Disconnected. Activity events are no longer sent.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Live AIML demonstration')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Connect to the laptop dashboard',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'On the same trusted Wi-Fi, open the dashboard on the laptop, start a session, then enter its session ID and pairing code here. Session tokens stay on this phone and events expire with the session.',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _server,
                decoration: const InputDecoration(
                  labelText: 'Laptop backend address',
                  hintText: 'http://192.168.x.x:8000',
                  helperText:
                      'Use the laptop’s current Wi-Fi IP and backend port. This app build’s configured address is prefilled and can be changed here.',
                  border: OutlineInputBorder(),
                ),
                autocorrect: false,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _session,
                decoration: const InputDecoration(
                  labelText: 'Session ID',
                  border: OutlineInputBorder(),
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pairing,
                decoration: const InputDecoration(
                  labelText: 'Pairing code',
                  border: OutlineInputBorder(),
                ),
                autocorrect: false,
              ),
              SwitchListTile(
                value: _consent,
                onChanged: (value) => setState(() => _consent = value),
                title: const Text(
                  'Share anonymized live activity with this session',
                ),
                subtitle: const Text(
                  'Screen, language, lesson, and action events. No account ID or credentials.',
                ),
              ),
              SwitchListTile(
                value: _shareTranscript,
                onChanged: _consent
                    ? (value) => setState(() => _shareTranscript = value)
                    : null,
                title: const Text('Include typed or recognized text in events'),
                subtitle: const Text(
                  'Optional. Off by default. Raw audio is never sent.',
                ),
              ),
              if (_message != null)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_message!),
                  ),
                ),
              if (widget.client.isConnected)
                FilledButton.tonal(
                  onPressed: _busy ? null : _disconnect,
                  child: const Text('Disconnect live session'),
                )
              else
                FilledButton(
                  onPressed: _busy || !_consent ? null : _connect,
                  child: Text(_busy ? 'Connecting…' : 'Connect to dashboard'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
