import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/profile_avatar.dart';
import 'dart:io';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';
import '../widgets/file_image.dart';
import 'investor_fleet_tab.dart';

String _fmt(dynamic value) {
  final n = double.tryParse(value?.toString() ?? '') ?? 0.0;
  final parts = n.toStringAsFixed(2).split('.');
  final intPart = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return 'GHS $intPart.${parts[1]}';
}

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);
const Color _kGold = Color(0xFFFFB300);

class InvestorHomePage extends StatefulWidget {
  const InvestorHomePage({super.key});

  @override
  State<InvestorHomePage> createState() => _InvestorHomePageState();
}

class _InvestorHomePageState extends State<InvestorHomePage> {
  Map<String, dynamic>? _dashData;
  List<dynamic> _earnings = [];
  bool _loading = true;
  String? _error;
  int _tab = 0; // 0 Dashboard, 1 Earnings, 2 Fleet, 3 Profile
  Map<String, dynamic>? _companyStats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final Map<String, dynamic> dash;
      final List<dynamic> earn;
      if (SupabaseService.isLoggedIn) {
        dash = await SupabaseService.fetchInvestorDashboard();
        earn = await SupabaseService.fetchInvestorEarningsList();
      } else {
        dash = await ApiService.get(ApiConstants.investorDashboard);
        final earnData = await ApiService.get(ApiConstants.investorEarnings);
        earn = (earnData['earnings'] as List?) ?? [];
      }
      if (!mounted) return;
      setState(() {
        _dashData = dash;
        _companyStats = dash['company_stats'] as Map<String, dynamic>?;
        _earnings = earn;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final investor = _dashData?['investor'] as Map<String, dynamic>? ?? {};
    final summary = _dashData?['earnings_summary'] as Map<String, dynamic>? ?? {};
    final fullName = investor['full_name'] as String? ?? '';

    return SafeArea(
      child: Column(
        children: [
          _Header(name: fullName, onLogout: _logout),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _DashboardTab(
                  investor: investor,
                  summary: summary,
                  earnings: _earnings,
                  companyStats: _companyStats ?? {},
                ),
                _EarningsTab(earnings: _earnings),
                const InvestorFleetTab(),
                _ProfileTab(investor: investor, onSaved: _load),
              ],
            ),
          ),
          _BottomNav(current: _tab, onTap: (i) => setState(() => _tab = i)),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    await provider.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String name;
  final VoidCallback onLogout;

  const _Header({required this.name, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B5E20), _kPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.trending_up, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Welcome back,',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

// ── Dashboard Tab ─────────────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  final Map<String, dynamic> investor;
  final Map<String, dynamic> summary;
  final List<dynamic> earnings;
  final Map<String, dynamic> companyStats;

  const _DashboardTab({
    required this.investor,
    required this.summary,
    required this.earnings,
    required this.companyStats,
  });

  @override
  Widget build(BuildContext context) {
    final investAmt = investor['investment_amount'] as String? ?? '0';
    final roiPct = investor['roi_percentage'] as String? ?? '0';
    final roiActual = summary['roi_actual'] as String? ?? '0';
    final yearShare = summary['estimated_year_share'] as String? ?? '0';
    final companyRev = companyStats['year_revenue'] as String? ?? '0';
    final totalCompanyRev = companyStats['total_company_revenue'] as String? ?? '0';
    final branchBreakdown = companyStats['branch_breakdown'] as List<dynamic>? ?? [];
    final company = investor['company_name'] as String? ?? '';
    final memberSince = investor['member_since'] as String? ?? '';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Investment card ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), _kPrimary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: _kPrimary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Investment', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('ROI $roiPct%', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_fmt(investAmt),
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.show_chart, color: Colors.white70, size: 16),
                  const SizedBox(width: 4),
                  Text('Actual ROI: $roiActual%', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  if (company.isNotEmpty)
                    Text(company, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
              if (memberSince.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Member since $memberSince', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Company revenue (what the company has actually earned) ─────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.account_balance, color: _kPrimary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('Company Revenue',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kTextDark)),
                ],
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Text('Total company earnings (all time)',
                    style: TextStyle(fontSize: 11, color: _kTextGray)),
              ),
              const SizedBox(height: 14),
              Text(_fmt(totalCompanyRev),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _kPrimary)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _InfoTile(
                      label: 'This Year (YTD)',
                      value: _fmt(companyRev),
                      icon: Icons.calendar_today_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InfoTile(
                      label: 'This Month',
                      value: _fmt(companyStats['month_revenue'] as String? ?? '0'),
                      icon: Icons.date_range_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _InfoTile(
                label: 'Total Sales (all-time transaction volume)',
                value: _fmt(companyStats['total_sales'] as String? ?? '0'),
                icon: Icons.point_of_sale_outlined,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Investor return ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: const Color(0xFF1565C0).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.savings_outlined, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  const Text('Your Return', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$roiPct% ROI', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(_fmt(yearShare),
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Estimated share from company YTD revenue',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Earned (All Time)', style: TextStyle(color: Colors.white60, fontSize: 11)),
                        Text(_fmt(summary['total'] as String? ?? '0'),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text('Earnings Breakdown',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextDark)),
        const SizedBox(height: 12),

        // ── Earnings grid ─────────────────────────────────────────────────
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _EarningCard(label: 'Today', amount: summary['today'] as String? ?? '0',
                icon: Icons.today, color: const Color(0xFF388E3C)),
            _EarningCard(label: 'This Week', amount: summary['this_week'] as String? ?? '0',
                icon: Icons.date_range, color: const Color(0xFF1976D2)),
            _EarningCard(label: 'This Month', amount: summary['this_month'] as String? ?? '0',
                icon: Icons.calendar_month, color: const Color(0xFF7B1FA2)),
            _EarningCard(label: 'Total Earned', amount: summary['total'] as String? ?? '0',
                icon: Icons.account_balance_wallet, color: _kGold),
          ],
        ),

        // Regional breakdown (kept for branch visibility)
        if (branchBreakdown.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Regional Performance',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextDark)),
          const SizedBox(height: 12),
          ...branchBreakdown.map((b) {
            final br = b as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_city, color: _kPrimary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(br['branch_name'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(br['region'] as String? ?? '',
                            style: const TextStyle(color: _kTextGray, fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_fmt(br['total_revenue'] ?? '0'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _kPrimary)),
                      Text('${br['collections'] ?? 0} collections',
                          style: const TextStyle(color: _kTextGray, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],

        const SizedBox(height: 20),

        // Earnings chart (last 8 entries)
        if (earnings.isNotEmpty) ...[
          const Text('Earnings Trend',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextDark)),
          const SizedBox(height: 12),
          _EarningsChart(earnings: earnings),
          const SizedBox(height: 20),
        ],

        _InfoRow(label: 'Contract Ref', value: investor['contract_reference'] as String? ?? '—'),
        _InfoRow(label: 'Agreement Date', value: investor['agreement_date'] as String? ?? '—'),
        _InfoRow(label: 'Location', value: investor['location'] as String? ?? '—'),
        _InfoRow(label: 'Email', value: investor['email'] as String? ?? '—'),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCCE5CC)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _kPrimary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: _kTextGray, fontSize: 10)),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13, color: _kPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningCard extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final Color color;

  const _EarningCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_fmt(amount),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: color)),
              Text(label,
                  style: const TextStyle(color: _kTextGray, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(color: _kTextGray, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: _kTextDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ── Earnings Chart ────────────────────────────────────────────────────────────

class _EarningsChart extends StatelessWidget {
  final List<dynamic> earnings;
  const _EarningsChart({required this.earnings});

  @override
  Widget build(BuildContext context) {
    // Take up to 8 most recent entries
    final recent = earnings.length > 8
        ? earnings.sublist(earnings.length - 8)
        : earnings;

    final spots = <FlSpot>[];
    double maxY = 0;
    for (int i = 0; i < recent.length; i++) {
      final e = recent[i] as Map<String, dynamic>;
      final amt = double.tryParse(e['amount']?.toString() ?? '0') ?? 0;
      if (amt > maxY) maxY = amt;
      spots.add(FlSpot(i.toDouble(), amt));
    }
    if (maxY == 0) maxY = 100;

    final labels = recent.map<String>((e) {
      final d = e['date'] as String? ?? '';
      if (d.length >= 7) return d.substring(5, 7); // MM
      return '';
    }).toList();

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.grey.shade100,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (idx < 0 || idx >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    labels[idx],
                    style: const TextStyle(fontSize: 10, color: _kTextGray),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) => Text(
                  value >= 1000
                      ? '${(value / 1000).toStringAsFixed(1)}k'
                      : value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9, color: _kTextGray),
                ),
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _kPrimary,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: _kPrimary,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    _kPrimary.withValues(alpha: 0.25),
                    _kPrimary.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          minX: 0,
          maxX: (spots.length - 1).toDouble().clamp(0, double.infinity),
          minY: 0,
          maxY: maxY * 1.2,
        ),
      ),
    );
  }
}

// ── Earnings Tab ──────────────────────────────────────────────────────────────

class _EarningsTab extends StatelessWidget {
  final List<dynamic> earnings;

  const _EarningsTab({required this.earnings});

  @override
  Widget build(BuildContext context) {
    if (earnings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: _kTextGray),
            SizedBox(height: 12),
            Text('No earnings recorded yet',
                style: TextStyle(color: _kTextGray, fontSize: 15)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: earnings.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final e = earnings[earnings.length - 1 - i] as Map<String, dynamic>;
        final type = e['earning_type'] as String? ?? '';
        final color = _earningColor(type);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8E8E8)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_earningIcon(type), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e['description'] as String? ?? type,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _kTextDark)),
                    const SizedBox(height: 2),
                    Text(e['date'] as String? ?? '',
                        style: const TextStyle(
                            color: _kTextGray, fontSize: 11)),
                  ],
                ),
              ),
              Text(_fmt(e['amount']),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: color)),
            ],
          ),
        );
      },
    );
  }

  Color _earningColor(String type) {
    switch (type) {
      case 'daily': return const Color(0xFF388E3C);
      case 'monthly': return const Color(0xFF1976D2);
      case 'dividend': return _kGold;
      default: return _kPrimary;
    }
  }

  IconData _earningIcon(String type) {
    switch (type) {
      case 'daily': return Icons.today;
      case 'monthly': return Icons.calendar_month;
      case 'dividend': return Icons.star;
      default: return Icons.payment;
    }
  }
}

// ── Profile Tab ───────────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  final Map<String, dynamic> investor;
  final VoidCallback onSaved;

  const _ProfileTab({required this.investor, required this.onSaved});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _company;
  late final TextEditingController _location;
  bool _saving = false;
  File? _imageFile;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    final inv = widget.investor;
    final fullName = (inv['full_name'] as String? ?? '').split(' ');
    _firstName = TextEditingController(text: fullName.isNotEmpty ? fullName.first : '');
    _lastName = TextEditingController(
        text: fullName.length > 1 ? fullName.sublist(1).join(' ') : '');
    _email = TextEditingController(text: inv['email'] as String? ?? '');
    _company = TextEditingController(text: inv['company_name'] as String? ?? '');
    _location = TextEditingController(text: inv['location'] as String? ?? '');
    _photoUrl = inv['profile_image'] as String?;
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _imageFile = File(picked.path));
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _company.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final provider = context.read<AppProvider>();
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.updateOwnProfile({
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'email': _email.text.trim(),
        });
        await SupabaseService.updateInvestorProfile({
          'company_name': _company.text.trim(),
          'location': _location.text.trim(),
        });
        if (_imageFile != null) {
          final url = await SupabaseService.uploadProfileImage(await readFileBytes(_imageFile!));
          provider.mergeProfileImage(url);
        }
        setState(() {
          _photoUrl = provider.profileImageUrl;
          _imageFile = null;
        });
      } else if (_imageFile != null) {
        await ApiService.putMultipart(ApiConstants.investorProfile, {
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'email': _email.text.trim(),
          'company_name': _company.text.trim(),
          'location': _location.text.trim(),
        }, imageFile: _imageFile);
        await provider.refreshProfileImageFromServer();
        setState(() {
          _photoUrl = provider.profileImageUrl;
          _imageFile = null;
        });
      } else {
        await ApiService.put(ApiConstants.investorProfile, {
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'email': _email.text.trim(),
          'company_name': _company.text.trim(),
          'location': _location.text.trim(),
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Edit Profile',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _kTextDark)),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _pickImage,
          child: _imageFile != null
              ? FileCircleAvatar(file: _imageFile, radius: 44, backgroundColor: _kPrimary.withValues(alpha: 0.1))
              : CircleAvatar(
                  radius: 44,
                  backgroundColor: _kPrimary.withValues(alpha: 0.1),
                  backgroundImage: _photoUrl != null ? profileImageProvider(_photoUrl) : null,
                  child: _photoUrl == null ? const Icon(Icons.person, size: 44, color: _kPrimary) : null,
                ),
        ),
        const SizedBox(height: 20),
        _field('First Name', _firstName),
        _field('Last Name', _lastName),
        _field('Email', _email, keyboardType: TextInputType.emailAddress),
        _field('Company Name', _company),
        _field('Location', _location),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save Changes',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: _kTextGray,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          TextFormField(
            controller: ctrl,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              filled: true,
              fillColor: _kCard,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom Nav ────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          _NavItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard,
              label: 'Dashboard', active: current == 0, onTap: () => onTap(0)),
          _NavItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long,
              label: 'Earnings', active: current == 1, onTap: () => onTap(1)),
          _NavItem(icon: Icons.local_shipping_outlined, activeIcon: Icons.local_shipping,
              label: 'Fleet', active: current == 2, onTap: () => onTap(2)),
          _NavItem(icon: Icons.person_outline, activeIcon: Icons.person,
              label: 'Profile', active: current == 3, onTap: () => onTap(3)),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? activeIcon : icon,
                  color: active ? _kPrimary : _kTextGray, size: 24),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: active ? _kPrimary : _kTextGray,
                      fontSize: 11,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error View ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: _kTextGray),
            const SizedBox(height: 16),
            const Text('Failed to load dashboard',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _kTextDark)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kTextGray, fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Retry',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
