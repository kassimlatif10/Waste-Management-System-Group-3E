import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/api_constants.dart';
import '../widgets/support_tickets_view.dart';

const Color _kPrimary = Color(0xFF2E7D32);
const Color _kBg = Color(0xFFF0F7F0);
const Color _kCard = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class CollectorHelpSupportPage extends StatefulWidget {
  const CollectorHelpSupportPage({super.key});

  @override
  State<CollectorHelpSupportPage> createState() =>
      _CollectorHelpSupportPageState();
}

class _CollectorHelpSupportPageState extends State<CollectorHelpSupportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (e) {
      debugPrint('Could not launch $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kTextDark,
        elevation: 0,
        title: const Text(
          'Help & Support',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _kPrimary,
          unselectedLabelColor: _kTextGray,
          indicatorColor: _kPrimary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [Tab(text: 'FAQ'), Tab(text: 'Feedback & Complaints')],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _FaqTab(onLaunch: _launch),
          SupportTicketsView(
            listCreateUrl: ApiConstants.collectorSupport,
            detailUrl: ApiConstants.collectorSupportTicket,
          ),
        ],
      ),
    );
  }
}

// ── FAQ tab ────────────────────────────────────────────────────────────────────
class _FaqTab extends StatelessWidget {
  final Future<void> Function(String) onLaunch;
  const _FaqTab({required this.onLaunch});

  static const _faqs = [
    (
      q: 'How do I get more pickup requests?',
      a: 'Stay online and keep a high rating. An admin assigns pickup requests to the nearest available collector. Make sure your GPS is enabled.',
    ),
    (
      q: 'How does payment work?',
      a: 'Customers pay you directly in cash when you complete the pickup. There is no in-app payment or withdrawal — the money is yours on the spot.',
    ),
    (
      q: 'My account is pending approval. What do I do?',
      a: 'After registering, your account is reviewed by the Bɔla Aba team. Approval usually takes 1–2 business days.',
    ),
    (
      q: 'How is my rating calculated?',
      a: 'Your rating is the average of all customer ratings (1–5 stars) you have received. Arrive on time and handle waste professionally to maintain a high score.',
    ),
    (
      q: 'What happens if I miss a scheduled pickup?',
      a: 'You will receive a countdown notification before the scheduled time. If you miss the pickup, the customer is notified and your rating may be affected.',
    ),
    (
      q: 'How do I update my vehicle information?',
      a: 'Go to Profile → Vehicle Details. You can update your vehicle type and plate number at any time.',
    ),
    (
      q: 'Can I decline a pickup request?',
      a: 'Yes. If you receive a request you cannot fulfil, tap Decline. The request will be re-matched to another available collector.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Contact quick links
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kLightGreen,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFA5D6A7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick Contact',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _kTextDark,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ContactBtn(
                      icon: Icons.chat,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: () => onLaunch('https://wa.me/233556461500'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ContactBtn(
                      icon: Icons.phone,
                      label: 'Call',
                      color: const Color(0xFF1565C0),
                      onTap: () => onLaunch('tel:+233556461500'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ContactBtn(
                      icon: Icons.email,
                      label: 'Email',
                      color: _kPrimary,
                      onTap:
                          () => onLaunch(
                            'mailto:collector-support@wastepick.com',
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Frequently Asked Questions',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: _kTextDark,
          ),
        ),
        const SizedBox(height: 10),
        ..._faqs.map((f) => _FaqTile(question: f.q, answer: f.a)),
      ],
    );
  }
}

class _ContactBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ContactBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question, answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        iconColor: _kPrimary,
        collapsedIconColor: _kTextGray,
        title: Text(
          question,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: _kTextDark,
          ),
        ),
        children: [
          Text(
            answer,
            style: const TextStyle(
              color: _kTextGray,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
