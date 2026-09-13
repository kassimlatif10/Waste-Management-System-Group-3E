import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/supabase_service.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

const List<(String value, String label)> kTicketCategories = [
  ('support', 'General Support'),
  ('complaint', 'Complaint'),
  ('feedback', 'Feedback'),
];

Color categoryColor(String category) {
  switch (category) {
    case 'complaint':
      return const Color(0xFFC62828);
    case 'feedback':
      return const Color(0xFF6A1B9A);
    default:
      return _kPrimary;
  }
}

String categoryLabel(String category) {
  for (final c in kTicketCategories) {
    if (c.$1 == category) return c.$2;
  }
  return category;
}

/// Lists a user's own feedback/complaint/support tickets and lets them file
/// a new one. Shared between the customer and collector "Help & Support"
/// screens — pass each side's own list/create + detail endpoints.
class SupportTicketsView extends StatefulWidget {
  final String listCreateUrl;
  final String Function(int id) detailUrl;

  const SupportTicketsView({
    super.key,
    required this.listCreateUrl,
    required this.detailUrl,
  });

  @override
  State<SupportTicketsView> createState() => _SupportTicketsViewState();
}

class _SupportTicketsViewState extends State<SupportTicketsView> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<dynamic> raw;
      if (SupabaseService.isLoggedIn) {
        raw = await SupabaseService.fetchMyTickets();
      } else {
        final data = await ApiService.get(widget.listCreateUrl);
        raw = (data['tickets'] as List?) ?? [];
      }
      setState(() {
        _tickets = raw.cast<Map<String, dynamic>>();
      });
    } catch (_) {
      // Leave list empty — the retry affordance is the pull-to-refresh.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewTicketSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewTicketSheet(listCreateUrl: widget.listCreateUrl),
    );
    if (result == null) return;
    final ticketId = result['ticket_id'] as int?;
    await _load();
    if (ticketId != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SupportTicketDetailScreen(
            ticketId: ticketId,
            detailUrl: widget.detailUrl,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTicketSheet,
        backgroundColor: _kPrimary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New', style: TextStyle(color: Colors.white)),
      ),
      body: _loading && _tickets.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : RefreshIndicator(
              color: _kPrimary,
              onRefresh: _load,
              child: _tickets.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: const [
                        SizedBox(height: 80),
                        Icon(Icons.forum_outlined, size: 48, color: _kTextGray),
                        SizedBox(height: 12),
                        Center(
                          child: Text(
                            'No feedback or complaints yet.\nTap "New" to get in touch.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _kTextGray),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: _tickets.length,
                      itemBuilder: (_, i) {
                        final t = _tickets[i];
                        final category = (t['category'] as String?) ?? 'support';
                        final status = (t['status'] as String?) ?? 'open';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: ListTile(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SupportTicketDetailScreen(
                                  ticketId: t['id'] as int,
                                  detailUrl: widget.detailUrl,
                                ),
                              ),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: categoryColor(category).withValues(alpha: 0.12),
                              child: Icon(
                                category == 'complaint'
                                    ? Icons.report_gmailerrorred
                                    : category == 'feedback'
                                        ? Icons.star_outline
                                        : Icons.help_outline,
                                color: categoryColor(category),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              (t['subject'] as String?)?.isNotEmpty == true
                                  ? t['subject'] as String
                                  : categoryLabel(category),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, color: _kTextDark),
                            ),
                            subtitle: Text(
                              (t['last_message'] as String?) ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _kTextGray, fontSize: 12),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: categoryColor(category).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    categoryLabel(category),
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: categoryColor(category)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  status == 'resolved' ? 'Resolved' : status == 'assigned' ? 'In progress' : 'Open',
                                  style: const TextStyle(fontSize: 10, color: _kTextGray),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _NewTicketSheet extends StatefulWidget {
  final String listCreateUrl;
  const _NewTicketSheet({required this.listCreateUrl});

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  String _category = 'complaint';
  final _msgCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final data = SupabaseService.isLoggedIn
          ? await SupabaseService.createTicket(category: _category, message: text)
          : await ApiService.post(widget.listCreateUrl, {
              'category': _category,
              'message': text,
            });
      if (mounted) Navigator.pop(context, data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextDark)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: kTicketCategories.map((c) {
                final selected = c.$1 == _category;
                return ChoiceChip(
                  label: Text(c.$2),
                  selected: selected,
                  selectedColor: categoryColor(c.$1).withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: selected ? categoryColor(c.$1) : _kTextGray,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) => setState(() => _category = c.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _msgCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: _category == 'complaint'
                    ? 'Describe your complaint…'
                    : _category == 'feedback'
                        ? 'Share your feedback…'
                        : 'How can we help?',
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _sending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _sending
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Send', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full message thread for a single ticket — supports replying.
class SupportTicketDetailScreen extends StatefulWidget {
  final int ticketId;
  final String Function(int id) detailUrl;

  const SupportTicketDetailScreen({
    super.key,
    required this.ticketId,
    required this.detailUrl,
  });

  @override
  State<SupportTicketDetailScreen> createState() => _SupportTicketDetailScreenState();
}

class _SupportTicketDetailScreenState extends State<SupportTicketDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String _status = 'open';
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> data;
      if (SupabaseService.isLoggedIn) {
        data = await SupabaseService.fetchTicketThread(widget.ticketId);
      } else {
        data = await ApiService.get(widget.detailUrl(widget.ticketId));
      }
      final raw = (data['messages'] as List?) ?? [];
      setState(() {
        _status = (data['status'] as String?) ?? 'open';
        _messages = raw.cast<Map<String, dynamic>>();
      });
      _scroll();
    } catch (_) {
      // Fall through — the screen just shows an empty thread on failure.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      final Map<String, dynamic> data;
      if (SupabaseService.isLoggedIn) {
        data = await SupabaseService.sendTicketMessage(widget.ticketId, text);
      } else {
        data = await ApiService.post(widget.detailUrl(widget.ticketId), {'message': text});
      }
      final raw = (data['messages'] as List?) ?? [];
      setState(() => _messages = raw.cast<Map<String, dynamic>>());
      _scroll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F0),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kTextDark,
        elevation: 0,
        title: Text(_status == 'resolved' ? 'Resolved' : 'Support Thread'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isMine = (m['is_mine'] as bool?) ?? false;
                      return Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: isMine ? _kPrimary : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isMine ? 18 : 4),
                              bottomRight: Radius.circular(isMine ? 4 : 18),
                            ),
                          ),
                          child: Text(
                            (m['body'] as String?) ?? '',
                            style: TextStyle(color: isMine ? Colors.white : _kTextDark, fontSize: 14, height: 1.4),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_status != 'resolved')
                  Container(
                    color: Colors.white,
                    padding: EdgeInsets.only(
                      left: 16, right: 12, top: 10,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgCtrl,
                            minLines: 1,
                            maxLines: 3,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: 'Type a message…',
                              filled: true,
                              fillColor: const Color(0xFFF5F5F5),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _send,
                          child: Container(
                            width: 44, height: 44,
                            decoration: const BoxDecoration(color: _kPrimary, shape: BoxShape.circle),
                            child: const Icon(Icons.send, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('This ticket is resolved.', style: TextStyle(color: _kTextGray)),
                  ),
              ],
            ),
    );
  }
}
