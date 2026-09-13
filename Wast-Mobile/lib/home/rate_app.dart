import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _kBg       = Color(0xFFF0F7F0);
const Color _kPrimary  = Color(0xFF2E7D32);
const Color _kCard     = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class RateAppPage extends StatefulWidget {
  const RateAppPage({super.key});

  @override
  State<RateAppPage> createState() => _RateAppPageState();
}

class _RateAppPageState extends State<RateAppPage> {
  int _stars = 0;
  bool _submitted = false;
  final _feedbackCtrl = TextEditingController();

  static const _appStoreUrl =
      'https://apps.apple.com/app/wastepick/id0000000000';
  static const _shareText =
      'I use WastePick for on-demand waste collection in Sekondi-Takoradi — fast, easy and eco-friendly! Download it here: https://wastepick.com/download';

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _openStore() async {
    final uri = Uri.parse(_appStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _shareApp() {
    Clipboard.setData(const ClipboardData(text: _shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share link copied to clipboard!'),
        backgroundColor: _kPrimary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _submitRating() {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a star rating first'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _submitted = true);

    // If high rating, prompt to rate on the app store
    if (_stars >= 4) {
      Future.delayed(const Duration(milliseconds: 800), _openStore);
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
        title: const Text('Rate the App',
            style: TextStyle(
                color: _kTextDark, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 12),

            // App icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: _kPrimary,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: _kPrimary.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child:
                  const Icon(Icons.delete_outline, color: Colors.white, size: 48),
            ),

            const SizedBox(height: 20),
            const Text('WastePick',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _kTextDark)),
            const SizedBox(height: 4),
            const Text('On-demand waste collection',
                style: TextStyle(color: _kTextGray, fontSize: 14)),

            const SizedBox(height: 32),

            if (!_submitted) ...[
              // Star rating
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text('How would you rate\nyour experience?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _kTextDark,
                            height: 1.4)),
                    const SizedBox(height: 6),
                    const Text(
                        'Your feedback helps us improve the app for everyone.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: _kTextGray, fontSize: 13)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final star = i + 1;
                        return GestureDetector(
                          onTap: () => setState(() => _stars = star),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              star <= _stars
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: star <= _stars
                                  ? const Color(0xFFFFC107)
                                  : Colors.grey.shade300,
                              size: 44,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    if (_stars > 0)
                      Text(
                        _ratingLabel(_stars),
                        style: const TextStyle(
                            color: _kPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _feedbackCtrl,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Leave a comment (optional)...',
                        hintStyle: const TextStyle(color: _kTextGray),
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: _kPrimary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _submitRating,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text('Submit Rating',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Thank you card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                          color: _kLightGreen, shape: BoxShape.circle),
                      child: const Icon(Icons.check, color: _kPrimary, size: 34),
                    ),
                    const SizedBox(height: 16),
                    const Text('Thank you!',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _kTextDark)),
                    const SizedBox(height: 6),
                    Text(
                        _stars >= 4
                            ? 'We\'re glad you love WastePick! Your review on the App Store helps others find us.'
                            : 'We appreciate your feedback. We\'re always working to improve your experience.',
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: _kTextGray, fontSize: 13, height: 1.5)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        5,
                        (i) => Icon(
                          Icons.star_rounded,
                          color: i < _stars
                              ? const Color(0xFFFFC107)
                              : Colors.grey.shade300,
                          size: 28,
                        ),
                      ),
                    ),
                    if (_stars >= 4) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _openStore,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.storefront_outlined,
                              color: Colors.white, size: 20),
                          label: const Text('Rate on App Store',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Share card — always visible
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                            color: _kLightGreen, shape: BoxShape.circle),
                        child:
                            const Icon(Icons.share, color: _kPrimary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Share WastePick',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: _kTextDark)),
                            SizedBox(height: 2),
                            Text(
                                'Invite friends to join clean waste collection',
                                style: TextStyle(
                                    color: _kTextGray, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _shareApp,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _kPrimary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.link, color: _kPrimary, size: 20),
                      label: const Text('Copy Share Link',
                          style: TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ratingLabel(int stars) {
    switch (stars) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }
}
