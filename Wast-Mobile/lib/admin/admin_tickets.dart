import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBg = Color(0xFFF1F8F1);
const Color _kCard = Colors.white;
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

Color _categoryColor(String category) {
  switch (category) {
    case 'complaint':
      return const Color(0xFFC62828);
    case 'feedback':
      return const Color(0xFF6A1B9A);
    default:
      return _kPrimary;
  }
}

String _categoryLabel(String category) {
  switch (category) {
    case 'complaint':
      return 'Complaint';
    case 'feedback':
      return 'Feedback';
    default:
      return 'Support';
  }
}

/// Admin — Feedback / Complaint / Support ticket inbox for both customers
/// and collectors.
class AdminTicketsPage extends StatefulWidget {
  const AdminTicketsPage({super.key});

  @override
  State<AdminTicketsPage> createState() => _AdminTicketsPageState();
}

class _AdminTicketsPageState extends State<AdminTicketsPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  int _total = 0, _page = 1;
  String? _categoryFilter;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> res;
      if (SupabaseService.isLoggedIn) {
        res = await SupabaseService.fetchAllTickets(
          category: _categoryFilter,
          status: _statusFilter,
          page: _page,
        );
      } else {
        final params = <String, String>{'page': '$_page', 'page_size': '20'};
        if (_categoryFilter != null) params['category'] = _categoryFilter!;
        if (_statusFilter != null) params['status'] = _statusFilter!;
        final query = '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
        res = await ApiService.get('${ApiConstants.adminTickets}$query');
      }
      setState(() {
        _items = (res['results'] as List? ?? []).cast<Map<String, dynamic>>();
        _total = (res['total'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {
      // Leave list as-is — pull-to-refresh is the retry affordance.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToPage(int p) { setState(() => _page = p); _load(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Feedback & Complaints',
            style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          _ChipFilterRow(
            value: _categoryFilter,
            options: const [
              MapEntry(null, 'All'),
              MapEntry('support', 'Support'),
              MapEntry('complaint', 'Complaints'),
              MapEntry('feedback', 'Feedback'),
            ],
            onChanged: (v) {
              setState(() { _categoryFilter = v; _page = 1; });
              _load();
            },
          ),
          _ChipFilterRow(
            value: _statusFilter,
            options: const [
              MapEntry(null, 'All'),
              MapEntry('open', 'Open'),
              MapEntry('assigned', 'In progress'),
              MapEntry('resolved', 'Resolved'),
            ],
            onChanged: (v) {
              setState(() { _statusFilter = v; _page = 1; });
              _load();
            },
          ),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator(color: _kPrimary))
                : _items.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: const [
                          SizedBox(height: 80),
                          Icon(Icons.forum_outlined, size: 48, color: _kTextGray),
                          SizedBox(height: 12),
                          Center(child: Text('No tickets', style: TextStyle(color: _kTextGray))),
                        ],
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final t = _items[i];
                            final category = (t['category'] as String?) ?? 'support';
                            final status = (t['status'] as String?) ?? 'open';
                            final role = (t['user_role'] as String?) ?? '';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => AdminTicketDetailPage(ticketId: t['id'] as int)),
                                  );
                                  _load();
                                },
                                leading: CircleAvatar(
                                  backgroundColor: _categoryColor(category).withValues(alpha: 0.12),
                                  child: Icon(
                                    category == 'complaint'
                                        ? Icons.report_gmailerrorred
                                        : category == 'feedback'
                                            ? Icons.star_outline
                                            : Icons.help_outline,
                                    color: _categoryColor(category),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  '${t['user_name'] ?? ''} ${role.isNotEmpty ? '($role)' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                subtitle: Text(
                                  (t['last_message'] as String?) ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: _kTextGray),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _categoryColor(category).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _categoryLabel(category),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _categoryColor(category)),
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
          ),
          _TicketsPaginationBar(page: _page, total: _total, onPageChange: _goToPage),
        ],
      ),
    );
  }
}

class _TicketsPaginationBar extends StatelessWidget {
  final int page;
  final int total;
  final ValueChanged<int> onPageChange;
  static const int _pageSize = 20;
  const _TicketsPaginationBar({required this.page, required this.total, required this.onPageChange});

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final totalPages = ((total + _pageSize - 1) ~/ _pageSize).clamp(1, 999999);
    final startItem = (page - 1) * _pageSize + 1;
    final endItem = (page * _pageSize).clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('Showing $startItem–$endItem of $total',
                style: const TextStyle(fontSize: 12, color: _kTextGray, fontWeight: FontWeight.w500)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            color: page > 1 ? _kTextDark : const Color(0xFFCCCCCC),
            onPressed: page > 1 ? () => onPageChange(page - 1) : null,
            splashRadius: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Text('$page / $totalPages',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kPrimary)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            color: page < totalPages ? _kTextDark : const Color(0xFFCCCCCC),
            onPressed: page < totalPages ? () => onPageChange(page + 1) : null,
            splashRadius: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Horizontal pill-filter row — same visual language used for status/KYC
/// filters across the admin Collections/Collectors/Reports/Schedules pages.
class _ChipFilterRow extends StatelessWidget {
  final String? value;
  final List<MapEntry<String?, String>> options;
  final ValueChanged<String?> onChanged;
  const _ChipFilterRow({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: options.length,
      itemBuilder: (_, i) {
        final entry = options[i];
        final selected = value == entry.key;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? _kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? _kPrimary : const Color(0xFFE0E0E0)),
              ),
              child: Text(entry.value,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : _kTextGray)),
            ),
          ),
        );
      },
    ),
  );
}

/// Admin — full ticket thread with reply + resolve.
class AdminTicketDetailPage extends StatefulWidget {
  final int ticketId;
  const AdminTicketDetailPage({super.key, required this.ticketId});

  @override
  State<AdminTicketDetailPage> createState() => _AdminTicketDetailPageState();
}

class _AdminTicketDetailPageState extends State<AdminTicketDetailPage> {
  final _msgCtrl = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  List<Map<String, dynamic>> _messages = [];
  String _status = 'open';
  String _category = 'support';
  String _userName = '';
  String _userRole = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = SupabaseService.isLoggedIn
          ? await SupabaseService.fetchAdminTicketThread(widget.ticketId)
          : await ApiService.get(ApiConstants.adminTicket(widget.ticketId));
      setState(() {
        _messages = (data['messages'] as List? ?? []).cast<Map<String, dynamic>>();
        _status = (data['status'] as String?) ?? 'open';
        _category = (data['category'] as String?) ?? 'support';
        _userName = (data['user_name'] as String?) ?? '';
        _userRole = (data['user_role'] as String?) ?? '';
      });
    } catch (_) {
      // Empty thread stays empty on failure.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.sendAdminTicketReply(widget.ticketId, text);
      } else {
        await ApiService.post(ApiConstants.adminTicket(widget.ticketId), {'message': text});
      }
      // Only clear once we know it actually sent — otherwise a failure
      // meant the admin had to retype their whole reply.
      _msgCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resolve() async {
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.resolveTicket(widget.ticketId);
      } else {
        await ApiService.post(ApiConstants.adminTicketResolve(widget.ticketId), {});
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('$_userName${_userRole.isNotEmpty ? ' ($_userRole)' : ''}',
            style: const TextStyle(color: _kTextDark, fontWeight: FontWeight.w800, fontSize: 15)),
        actions: [
          if (_status != 'resolved')
            TextButton(
              onPressed: _resolve,
              child: const Text('Resolve', style: TextStyle(color: _kPrimary, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: _categoryColor(_category).withValues(alpha: 0.08),
                  child: Text(
                    '${_categoryLabel(_category)} · ${_status == 'resolved' ? 'Resolved' : _status == 'assigned' ? 'In progress' : 'Open'}',
                    style: TextStyle(color: _categoryColor(_category), fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isAdmin = (m['is_admin'] as bool?) ?? false;
                      return Align(
                        alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: isAdmin ? _kPrimary : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isAdmin ? 18 : 4),
                              bottomRight: Radius.circular(isAdmin ? 4 : 18),
                            ),
                          ),
                          child: Text(
                            (m['body'] as String?) ?? '',
                            style: TextStyle(color: isAdmin ? Colors.white : _kTextDark, fontSize: 14, height: 1.4),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_status != 'resolved')
                  Container(
                    color: Colors.white,
                    padding: EdgeInsets.only(left: 16, right: 12, top: 10, bottom: MediaQuery.of(context).viewInsets.bottom + 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgCtrl,
                            minLines: 1,
                            maxLines: 3,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: 'Reply…',
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
                  ),
              ],
            ),
    );
  }
}
