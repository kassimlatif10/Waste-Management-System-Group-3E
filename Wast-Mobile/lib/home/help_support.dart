import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_constants.dart';
import '../widgets/support_tickets_view.dart';

const Color _kBg       = Color(0xFFF0F7F0);
const Color _kPrimary  = Color(0xFF2E7D32);
const Color _kCard     = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

const _kFaqs = [
  (
    q: 'How do I request a waste pickup?',
    a: 'Tap the green "Request Pickup" button on the home screen, choose your waste type and bin size, confirm your location, and tap "Place Request". An admin will review your request and assign the nearest available collector.',
  ),
  (
    q: 'How long does it take for a collector to arrive?',
    a: 'Typical arrival times are 10–30 minutes depending on collector availability and your location. You can track the collector\'s real-time location on the map.',
  ),
  (
    q: 'How do I pay for a pickup?',
    a: 'Payment is made in cash directly to the collector once your pickup is complete. There is no in-app payment.',
  ),
  (
    q: 'Can I cancel a pickup request?',
    a: 'Yes, you can cancel a request at any time before the collector arrives by tapping "Cancel" on the tracking screen. Frequent cancellations may affect your account standing.',
  ),
  (
    q: 'What types of waste do you collect?',
    a: 'WastePick handles General Waste, Recyclable Materials, Organic/Compost, and Hazardous Waste. Pricing varies by waste type — check the request screen for details.',
  ),
  (
    q: 'Is Bɔla Aba available in my area?',
    a: 'Bɔla Aba currently serves select service areas. If your location is not covered, you will see a message when requesting a pickup. We are expanding to more areas soon.',
  ),
  (
    q: 'How do I report illegal dumping?',
    a: 'Go to Account > Dumping Reports and submit a report with a photo and location. Our team reviews all reports within 24 hours.',
  ),
  (
    q: 'How is the pickup price calculated?',
    a: 'Prices start from a base rate per waste type and include a small distance surcharge. The final price is shown before you confirm and pay.',
  ),
];

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Help & Support',
            style: TextStyle(
                color: _kTextDark, fontWeight: FontWeight.bold, fontSize: 18)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _kPrimary,
          labelColor: _kPrimary,
          unselectedLabelColor: _kTextGray,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'FAQ'),
            Tab(text: 'Feedback & Complaints'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildFaq(),
          SupportTicketsView(
            listCreateUrl: ApiConstants.customerSupport,
            detailUrl: ApiConstants.customerSupportTicket,
          ),
        ],
      ),
    );
  }

  Widget _buildFaq() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Contact strip
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Need quick help?',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      SizedBox(height: 3),
                      Text('Chat with us or call 055 646 1500',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _launchUrl('https://wa.me/233556461500'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _kPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text('WhatsApp',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),

          const Text('Frequently Asked Questions',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _kTextDark)),
          const SizedBox(height: 12),
          ..._kFaqs.map((faq) => _FaqTile(question: faq.q, answer: faq.a)),
          const SizedBox(height: 20),

          // Contact cards
          Row(
            children: [
              Expanded(
                child: _contactCard(
                  icon: Icons.phone_outlined,
                  label: 'Call Us',
                  sub: '055 646 1500',
                  onTap: () => _launchUrl('tel:+233556461500'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _contactCard(
                  icon: Icons.email_outlined,
                  label: 'Email Us',
                  sub: 'support@wastepick.com',
                  onTap: () => _launchUrl('mailto:support@wastepick.com'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactCard({
    required IconData icon,
    required String label,
    required String sub,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                  color: _kLightGreen, shape: BoxShape.circle),
              child: Icon(icon, color: _kPrimary, size: 20),
            ),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _kTextDark)),
            const SizedBox(height: 2),
            Text(sub,
                style: const TextStyle(color: _kTextGray, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
                color: _kLightGreen, shape: BoxShape.circle),
            child:
                const Icon(Icons.help_outline, color: _kPrimary, size: 17),
          ),
          title: Text(
            widget.question,
            style: TextStyle(
                fontWeight:
                    _expanded ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
                color: _kTextDark),
          ),
          trailing: Icon(
            _expanded ? Icons.remove : Icons.add,
            color: _kPrimary,
            size: 20,
          ),
          onExpansionChanged: (v) => setState(() => _expanded = v),
          children: [
            Text(widget.answer,
                style: const TextStyle(
                    color: _kTextGray, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
