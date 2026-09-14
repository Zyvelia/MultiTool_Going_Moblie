import 'package:flutter/material.dart';
import '../models/ai_approval.dart';
import '../services/ai_approval_service.dart';
import '../services/settings_service.dart';
import '../services/user_facing_error.dart';
import '../theme/app_colors.dart';

class AiApprovalsScreen extends StatefulWidget {
  final String? requestedId;
  const AiApprovalsScreen({super.key, this.requestedId});

  @override
  State<AiApprovalsScreen> createState() => _AiApprovalsScreenState();
}

class _AiApprovalsScreenState extends State<AiApprovalsScreen> {
  final _settings = SettingsService();
  AiApprovalService? _service;
  AiApproval? _approval;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = await _settings.baseUrl('chat');
      final code = await _settings.getAccessCode('chat');
      if (base == null) throw StateError('Set your PC hostname in Settings first.');
      final service = AiApprovalService(base, accessCode: code);
      final approval = widget.requestedId != null && widget.requestedId!.isNotEmpty
          ? await service.get(widget.requestedId!)
          : await service.pending();
      if (!mounted) return;
      setState(() {
        _service = service;
        _approval = approval;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = explainError(e);
      });
    }
  }

  Future<void> _decide(bool accepted) async {
    final approval = _approval;
    final service = _service;
    if (approval == null || service == null || _busy) return;
    setState(() => _busy = true);
    try {
      await service.decide(approval.id, accepted);
      if (!mounted) return;
      setState(() {
        _approval = null;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accepted ? 'AI operation approved.' : 'AI operation denied.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = explainError(e);
      });
    }
  }

  Widget _row(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 14)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _approval;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Approvals'),
        actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : a == null
                  ? const Center(child: Text('No pending AI approvals.', style: TextStyle(color: AppColors.muted)))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                const Icon(Icons.security_outlined),
                                const SizedBox(width: 10),
                                const Expanded(child: Text('Approval required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                                Chip(label: Text(a.risk.toUpperCase())),
                              ]),
                              const SizedBox(height: 18),
                              _row('Project', a.project),
                              _row('Agent', a.agent),
                              _row('Operation', a.operation),
                              _row('Reason', a.reason),
                              if (a.files.isNotEmpty) ...[
                                const Text('Files', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                                const SizedBox(height: 4),
                                ...a.files.map((f) => Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text('• $f', style: const TextStyle(fontSize: 13)),
                                    )),
                                const SizedBox(height: 10),
                              ],
                              if (a.expiresAt != null)
                                _row('Expires', a.expiresAt!.toLocal().toString()),
                              if (a.diff.isNotEmpty) ...[
                                const Text('Proposed diff', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: SelectableText(a.diff, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                                ),
                              ],
                            ]),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _decide(false),
                              icon: const Icon(Icons.close),
                              label: const Text('Deny'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy ? null : () => _decide(true),
                              icon: const Icon(Icons.check),
                              label: Text(_busy ? 'Sending…' : 'Accept'),
                            ),
                          ),
                        ]),
                      ],
                    ),
    );
  }
}
