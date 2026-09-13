import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/file_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../constants/api_constants.dart';
import '../utils/parse_utils.dart';
import '../providers/user_provider.dart';
import '../home/location_picker.dart';
import '../home/notification.dart';
import 'admin_collection_map.dart';
import 'admin_tickets.dart';
import '../auth/change_password_screen.dart';

// ── Theme constants ───────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF2E7D32);
const _kDark = Color(0xFF1B5E20);
const _kBg = Color(0xFFF1F8F1);
const _kCard = Colors.white;
const _kAccent = Color(0xFF00C853);
const _kTextDark = Color(0xFF1A1A1A);
const _kTextGray = Color(0xFF757575);
const _kRed = Color(0xFFE53935);
const _kOrange = Color(0xFFFF6D00);
const _kBlue = Color(0xFF1565C0);
const _kLightGreen = Color(0xFFE8F5E9);

// ── Root Admin Page ───────────────────────────────────────────────────────────
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int _tab = 0;
  bool _redirecting = false;

  // Sidebar collapse: null follows the automatic width-based rule below;
  // once the admin manually toggles it, that choice is remembered and wins.
  static const _sidebarPrefKey = 'admin_sidebar_collapsed';
  bool? _collapsedOverride;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_sidebarPrefKey);
      if (saved != null && mounted) setState(() => _collapsedOverride = saved);
    });
  }

  void _setSidebarCollapsed(bool collapsed) {
    setState(() => _collapsedOverride = collapsed);
    SharedPreferences.getInstance().then((p) => p.setBool(_sidebarPrefKey, collapsed));
  }

  static const _baseTabs = [
    BottomNavigationBarItem(
        icon: Icon(Icons.dashboard_outlined),
        activeIcon: Icon(Icons.dashboard),
        label: 'Dashboard'),
    BottomNavigationBarItem(
        icon: Icon(Icons.delete_sweep_outlined),
        activeIcon: Icon(Icons.delete_sweep),
        label: 'Collections'),
    BottomNavigationBarItem(
        icon: Icon(Icons.people_outline),
        activeIcon: Icon(Icons.people),
        label: 'Collectors'),
    BottomNavigationBarItem(
        icon: Icon(Icons.more_horiz_outlined),
        activeIcon: Icon(Icons.more_horiz),
        label: 'More'),
  ];

  static const _superAdminTab = BottomNavigationBarItem(
    icon: Icon(Icons.location_city_outlined),
    activeIcon: Icon(Icons.location_city),
    label: 'Branches',
  );

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isAuthenticated || !provider.isAdmin) {
      if (!_redirecting) {
        _redirecting = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        });
      }
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
    }

    final isSuperAdmin = provider.isSuperAdmin;
    final tabs = isSuperAdmin ? [..._baseTabs, _superAdminTab] : _baseTabs;
    final children = [
      const _DashboardTab(),
      const _CollectionsTab(),
      _CollectorsTab(onGoToDashboard: () => setState(() => _tab = 0)),
      const _MoreTab(),
      if (isSuperAdmin) const _BranchManagementTab(),
    ];

    // Clamp _tab index if switching between super/regular admin
    final safeTab = _tab.clamp(0, tabs.length - 1);

    // Adaptive layout — Material 3 guidance: a persistent side rail/sidebar
    // for medium+ window sizes (tablet, desktop, this app's Windows build),
    // bottom navigation on compact phone widths. Same tab widgets either way.
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 800;
    // "Intelligent" collapse: on a narrower wide window there's less room for
    // both the rail and content, so default to the icon-only rail there;
    // a spacious desktop window defaults to the fully labeled sidebar. The
    // admin can always override via the toggle — that choice then sticks.
    final autoCollapsed = width < 1100;
    final collapsed = _collapsedOverride ?? autoCollapsed;

    if (isWide) {
      return Scaffold(
        backgroundColor: _kBg,
        body: Row(
          children: [
            _AdminSidebar(
              tabs: tabs,
              selectedIndex: safeTab,
              onSelect: (i) => setState(() => _tab = i),
              collapsed: collapsed,
              onToggleCollapsed: () => _setSidebarCollapsed(!collapsed),
            ),
            const VerticalDivider(width: 1, color: Color(0xFFE5E5E5)),
            Expanded(
              child: IndexedStack(index: safeTab, children: children),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: IndexedStack(
        index: safeTab,
        children: children,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x12000000), blurRadius: 12)],
        ),
        child: BottomNavigationBar(
          currentIndex: safeTab,
          onTap: (i) => setState(() => _tab = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: _kPrimary,
          unselectedItemColor: _kTextGray,
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          elevation: 0,
          items: tabs,
        ),
      ),
    );
  }
}

// ── Sidebar navigation — shown on tablet/desktop-width windows ────────────────
// Collapses to an icon-only rail (64px) or expands to a full labeled sidebar
// (240px); width transition is animated, matching the standard admin-panel
// pattern (VS Code / Gmail-style collapsible rail).
const double _kSidebarExpandedWidth = 240;
const double _kSidebarCollapsedWidth = 64;

class _AdminSidebar extends StatelessWidget {
  final List<BottomNavigationBarItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  const _AdminSidebar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  Future<void> _logout(BuildContext context) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _kTextGray)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: _kRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await provider.logout();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final name = provider.displayName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: collapsed ? _kSidebarCollapsedWidth : _kSidebarExpandedWidth,
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Brand header + collapse toggle ─────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 12 : 20, 24, collapsed ? 12 : 20, 20),
              child: collapsed
                  ? Column(
                      children: [
                        _BrandMark(),
                        const SizedBox(height: 16),
                        _SidebarToggleButton(collapsed: true, onTap: onToggleCollapsed),
                      ],
                    )
                  : Row(
                      children: [
                        _BrandMark(),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Bɔla Aba Admin',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kTextDark),
                              overflow: TextOverflow.ellipsis),
                        ),
                        _SidebarToggleButton(collapsed: false, onTap: onToggleCollapsed),
                      ],
                    ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 8),
            // ── Nav items ─────────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 12),
                itemCount: tabs.length,
                itemBuilder: (context, i) {
                  final selected = i == selectedIndex;
                  final item = tabs[i];
                  final navItem = Material(
                    color: selected ? _kPrimary.withValues(alpha: 0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onSelect(i),
                      child: Padding(
                        padding: collapsed
                            ? const EdgeInsets.symmetric(vertical: 14)
                            : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: collapsed
                            ? Center(
                                child: IconTheme(
                                  data: IconThemeData(color: selected ? _kPrimary : _kTextGray, size: 22),
                                  child: selected ? item.activeIcon : item.icon,
                                ),
                              )
                            : Row(
                                children: [
                                  IconTheme(
                                    data: IconThemeData(color: selected ? _kPrimary : _kTextGray, size: 20),
                                    child: selected ? item.activeIcon : item.icon,
                                  ),
                                  const SizedBox(width: 14),
                                  Text(
                                    item.label ?? '',
                                    style: TextStyle(
                                      color: selected ? _kPrimary : _kTextDark,
                                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: collapsed
                        ? Tooltip(message: item.label ?? '', child: navItem)
                        : navItem,
                  );
                },
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            // ── Account footer ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: collapsed
                  ? Column(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: _kPrimary.withValues(alpha: 0.12),
                          backgroundImage: provider.profileImageUrl != null
                              ? SslNetworkImageProvider(provider.profileImageUrl!)
                              : null,
                          child: provider.profileImageUrl == null
                              ? Text(initial, style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13))
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Tooltip(
                          message: 'Logout',
                          child: IconButton(
                            icon: const Icon(Icons.logout, color: _kRed, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: () => _logout(context),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: _kPrimary.withValues(alpha: 0.12),
                          backgroundImage: provider.profileImageUrl != null
                              ? SslNetworkImageProvider(provider.profileImageUrl!)
                              : null,
                          child: provider.profileImageUrl == null
                              ? Text(initial, style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.bold, fontSize: 13))
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name.isNotEmpty ? name : 'Admin',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: _kTextDark),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, color: _kRed, size: 18),
                          tooltip: 'Logout',
                          onPressed: () => _logout(context),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/bolaaba_logo.png',
    height: 32,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kPrimary, _kDark]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 18),
    ),
  );
}

class _SidebarToggleButton extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onTap;
  const _SidebarToggleButton({required this.collapsed, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
    child: Material(
      color: const Color(0xFFF5F5F5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            collapsed ? Icons.chevron_right : Icons.chevron_left,
            size: 18,
            color: _kTextGray,
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Tab
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardTab extends StatefulWidget {
  const _DashboardTab();
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  String _period = 'all';
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  final _periods = ['today', 'yesterday', 'week', 'month', 'all'];
  final _periodLabels = ['Today', 'Yesterday', 'Week', 'Month', 'All Time'];

  final _commRateCtrl = TextEditingController();
  bool _savingRate = false;
  bool _editingRate = false;

  // Keeps the overview cards (including the Pending count) live without a
  // manual refresh — the same interval used elsewhere in the app for
  // near-real-time status. Silent: _load() only shows a full spinner on the
  // very first load (_data == null), so this never flashes/interrupts the UI.
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    context.read<AppProvider>().fetchNotifications();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _commRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final Map<String, dynamic> res;
      if (SupabaseService.isLoggedIn) {
        res = await SupabaseService.fetchAdminDashboard(period: _period);
      } else {
        res = await ApiService.get('${ApiConstants.adminDashboard}?period=$_period');
      }
      setState(() {
        _data = res;
        final rate = (res['overview'] as Map?)?['commission_rate'] as String? ?? '';
        if (_commRateCtrl.text.isEmpty) _commRateCtrl.text = rate;
      });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _saveCommissionRate() async {
    final val = _commRateCtrl.text.trim();
    if (val.isEmpty) return;
    setState(() => _savingRate = true);
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.updateCommissionRate(val);
      } else {
        await ApiService.patch(ApiConstants.adminSystemConfig, {'commission_rate': val});
      }
      if (mounted) {
        setState(() => _editingRate = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Commission rate updated'), backgroundColor: _kPrimary));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _savingRate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: _kPrimary,
        child: _loading && _data == null
            ? const Center(child: CircularProgressIndicator(color: _kPrimary))
            : _error != null && _data == null
                ? (_error!.contains('no_branch') || _error!.contains('not been assigned'))
                    ? const _NoBranchView()
                    : _ErrorView(error: _error!, onRetry: _load)
                : CustomScrollView(
                    slivers: [
                      _buildHeader(),
                      _buildPeriodFilter(),
                      if (_data != null) ...[
                        _buildOverviewCards(),
                        _buildCommissionSettings(),
                        _buildCollectionStats(),
                        _buildStatusBreakdownChart(),
                        _buildRevenueChart(),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeader() => SliverToBoxAdapter(
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Image.asset(
            'assets/bolaaba_logo.png',
            height: 42,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kPrimary, _kDark]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Admin Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kTextDark)),
                Text(
                  () {
                    final branch = _data?['branch'] as Map<String, dynamic>?;
                    if (branch == null) return 'All Branches';
                    return branch['name'] as String? ?? 'WastePick Control Panel';
                  }(),
                  style: TextStyle(fontSize: 12, color: _kTextGray),
                ),
              ],
            ),
          ),
          // Notification bell
          Builder(builder: (context) {
            final provider = Provider.of<AppProvider>(context);
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const NotificationPage())),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.notifications_outlined, color: _kTextDark, size: 20),
                    ),
                    if (provider.unreadNotifications > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            '${provider.unreadNotifications}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          // Profile avatar – far right
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const _AdminProfilePage())),
            child: () {
              final provider =
                  Provider.of<AppProvider>(context, listen: false);
              final name = provider.displayName;
              final initial =
                  name.isNotEmpty ? name[0].toUpperCase() : 'A';
              return ClipOval(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: provider.profileImageUrl != null
                      ? Image(
                          image: SslNetworkImageProvider(
                              provider.profileImageUrl!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: _kPrimary,
                            child: Center(
                              child: Text(initial,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ),
                          ),
                          frameBuilder: (_, child, frame, _) =>
                              frame == null
                                  ? Container(
                                      color: _kPrimary,
                                      child: Center(
                                        child: Text(initial,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                      ),
                                    )
                                  : child,
                        )
                      : Container(
                          color: _kPrimary,
                          child: Center(
                            child: Text(initial,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ),
                        ),
                ),
              );
            }(),
          ),
        ],
      ),
    ),
  );

  Widget _buildPeriodFilter() => SliverToBoxAdapter(
    child: SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _periods.length,
        itemBuilder: (_, i) {
          final selected = _period == _periods[i];
          return GestureDetector(
            onTap: () { setState(() => _period = _periods[i]); _load(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? _kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? _kPrimary : const Color(0xFFDDDDDD), width: 1),
              ),
              child: Text(_periodLabels[i],
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : _kTextGray)),
            ),
          );
        },
      ),
    ),
  );

  Widget _buildOverviewCards() {
    final ov = _data?['overview'] as Map<String, dynamic>? ?? {};
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'Overview'),
            const SizedBox(height: 10),
            // Row 1 — sales vs company revenue
            Row(children: [
              Expanded(child: _StatCard(
                title: 'Total Sales',
                subtitle: 'All collectors combined',
                value: money(ov['total_sales'], prefix: 'GH₵', fallback: 'GH₵ 0.00'),
                icon: Icons.shopping_cart_outlined,
                gradient: const [Color(0xFF1565C0), Color(0xFF1976D2)],
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                title: 'Company Revenue',
                subtitle: 'Commission + own collectors',
                value: money(ov['total_revenue'], prefix: 'GH₵', fallback: 'GH₵ 0.00'),
                icon: Icons.account_balance_outlined,
                gradient: const [Color(0xFF2E7D32), Color(0xFF43A047)],
              )),
            ]),
            const SizedBox(height: 12),
            // Row 2 — revenue breakdown
            Row(children: [
              Expanded(child: _StatCard(
                title: 'Own Collector Sales',
                subtitle: 'Company-owned collectors',
                value: money(ov['company_collectors_revenue'], prefix: 'GH₵', fallback: 'GH₵ 0.00'),
                icon: Icons.local_shipping_outlined,
                gradient: const [Color(0xFF00695C), Color(0xFF00897B)],
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                title: 'Commission Earned',
                subtitle: 'From independent collectors',
                value: money(ov['commission_from_independent'], prefix: 'GH₵', fallback: 'GH₵ 0.00'),
                icon: Icons.percent,
                gradient: const [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
              )),
            ]),
            const SizedBox(height: 12),
            // Row 3 — commission tracking
            Row(children: [
              Expanded(child: _StatCard(
                title: 'Commission Collected',
                subtitle: 'Paid commissions',
                value: money(ov['total_commission_collected'], prefix: 'GH₵', fallback: 'GH₵ 0.00'),
                icon: Icons.check_circle_outline,
                gradient: const [Color(0xFF558B2F), Color(0xFF7CB342)],
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                title: 'Commission Owed',
                subtitle: 'Unpaid cash commissions',
                value: money(ov['total_commission_owed'], prefix: 'GH₵', fallback: 'GH₵ 0.00'),
                icon: Icons.warning_amber_outlined,
                gradient: const [Color(0xFFE53935), Color(0xFFEF5350)],
              )),
            ]),
            const SizedBox(height: 12),
            // Row 4 — payouts + collectors
            Row(children: [
              Expanded(child: _StatCard(
                title: 'Total Paid Out',
                subtitle: 'Collector earnings paid',
                value: money(ov['total_paid_out'], prefix: 'GH₵', fallback: 'GH₵ 0.00'),
                icon: Icons.payments_outlined,
                gradient: const [Color(0xFF0277BD), Color(0xFF0288D1)],
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                title: 'Active Collectors',
                subtitle: 'Online right now',
                value: '${ov['active_collectors'] ?? 0} / ${ov['total_collectors'] ?? 0}',
                icon: Icons.people_outline,
                gradient: const [Color(0xFF00838F), Color(0xFF00ACC1)],
              )),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildCommissionSettings() {
    final ov = _data?['overview'] as Map<String, dynamic>? ?? {};
    final currentRate = ov['commission_rate'] as String? ?? _commRateCtrl.text;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.percent, color: Color(0xFF1565C0), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Commission Rate',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _kTextDark)),
                        Text('Percentage charged on each collection from independent collectors',
                            style: TextStyle(fontSize: 11, color: _kTextGray)),
                      ],
                    ),
                  ),
                  if (!_editingRate)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _editingRate = true;
                        _commRateCtrl.text = currentRate;
                      }),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF1565C0)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!_editingRate)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$currentRate%',
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Applied to every collection by non-company collectors.',
                        style: TextStyle(fontSize: 12, color: _kTextGray),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commRateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'New rate (%)',
                          suffixText: '%',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF1565C0)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _savingRate ? null : _saveCommissionRate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _savingRate
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Save', style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => setState(() => _editingRate = false),
                      child: const Text('Cancel', style: TextStyle(color: _kTextGray)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollectionStats() {
    final col = _data?['collections'] as Map<String, dynamic>? ?? {};
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'Collections'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _MiniStat('Total', '${col['total'] ?? 0}', _kPrimary)),
              const SizedBox(width: 8),
              Expanded(child: _MiniStat('Completed', '${col['completed'] ?? 0}', _kAccent)),
              const SizedBox(width: 8),
              Expanded(child: _MiniStat('Pending', '${col['pending'] ?? 0}', _kOrange)),
              const SizedBox(width: 8),
              Expanded(child: _MiniStat('Cancelled', '${col['cancelled'] ?? 0}', _kRed)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBreakdownChart() {
    final col = _data?['collections'] as Map<String, dynamic>? ?? {};
    final total = (col['total'] as num?)?.toInt() ?? 0;
    if (total == 0) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final completed = (col['completed'] as num?)?.toInt() ?? 0;
    final cancelled = (col['cancelled'] as num?)?.toInt() ?? 0;
    final pending = (col['pending'] as num?)?.toInt() ?? 0;
    final inProgress = (total - completed - cancelled - pending).clamp(0, total);

    final slices = <_StatusSlice>[
      if (completed > 0) _StatusSlice('Completed', completed, _kAccent),
      if (pending > 0) _StatusSlice('Pending', pending, _kOrange),
      if (inProgress > 0) _StatusSlice('In progress', inProgress, _kBlue),
      if (cancelled > 0) _StatusSlice('Cancelled', cancelled, _kRed),
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Collection Status Breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 34,
                            sections: slices.map((s) => PieChartSectionData(
                              value: s.count.toDouble(),
                              color: s.color,
                              radius: 22,
                              showTitle: false,
                            )).toList(),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$total', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _kTextDark)),
                            const Text('Total', style: TextStyle(fontSize: 10, color: _kTextGray)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: slices.map((s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(s.label, style: const TextStyle(fontSize: 12, color: _kTextDark))),
                            Text('${s.count}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.color)),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRevenueChart() {
    final trend = (_data?['daily_trend'] as List? ?? []);
    if (trend.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final spots = <FlSpot>[];
    for (int i = 0; i < trend.length && i < 14; i++) {
      final rev = parseDouble(trend[i]['revenue']);
      spots.add(FlSpot(i.toDouble(), rev));
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Revenue Trend (14 days)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 16),
              SizedBox(
                height: 140,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(color: const Color(0xFFEEEEEE), strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, _) => Text('₵${v.toInt()}', style: const TextStyle(fontSize: 9, color: _kTextGray)),
                        ),
                      ),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: _kPrimary,
                        barWidth: 2.5,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [_kPrimary.withValues(alpha: 0.25), _kPrimary.withValues(alpha: 0)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Collections Tab
// ─────────────────────────────────────────────────────────────────────────────
class _CollectionsTab extends StatefulWidget {
  const _CollectionsTab();
  @override
  State<_CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends State<_CollectionsTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  int _total = 0, _page = 1;
  String _status = '';

  static const _statusTabs = [
    ('', 'All'),
    ('finding', 'Pending'),
    ('proposed', 'Awaiting Collector'),
    ('assigned', 'Assigned'),
    ('on_way', 'On the Way'),
    ('arrived', 'Arrived'),
    ('completed', 'Done'),
    ('cancelled', 'Cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      _status = _statusTabs[_tabController.index].$1;
      _page = 1;
      _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final search = _searchController.text.trim();
      final Map<String, dynamic> res;
      if (SupabaseService.isLoggedIn) {
        res = await SupabaseService.fetchAdminCollections(
          status: _status.isEmpty ? null : _status,
          search: search,
          page: _page,
          pageSize: 20,
        );
      } else {
        var url = '${ApiConstants.adminCollections}?page=$_page&page_size=20';
        if (_status.isNotEmpty) url += '&status=$_status';
        if (search.isNotEmpty) url += '&search=$search';
        res = await ApiService.get(url);
      }
      final list = (res['results'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _items = list;
        _total = (res['total'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {} finally {
      setState(() => _loading = false);
    }
  }

  void _goToPage(int p) { setState(() => _page = p); _load(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: const Text('Collections', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            labelColor: Colors.white,
            unselectedLabelColor: _kTextGray,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(20),
            ),
            splashBorderRadius: BorderRadius.circular(20),
            tabs: _statusTabs.map((t) => Tab(
              height: 34,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(t.$2)),
            )).toList(),
          ),
        ),
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _searchController,
            onSubmitted: (_) { _page = 1; _load(); },
            decoration: InputDecoration(
              hintText: 'Search customer, collector, address…',
              prefixIcon: const Icon(Icons.search, color: _kTextGray, size: 20),
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEFEFEF))),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.receipt_long_outlined, size: 14, color: _kTextGray),
            const SizedBox(width: 6),
            Text('$_total ${_total == 1 ? 'result' : 'results'}',
                style: const TextStyle(fontSize: 12, color: _kTextGray, fontWeight: FontWeight.w600)),
          ]),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : _items.isEmpty
                  ? const _EmptyState(icon: Icons.delete_sweep_outlined, message: 'No collections found')
                  : RefreshIndicator(
                      onRefresh: () { _page = 1; return _load(); },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _CollectionCard(item: _items[i], onAssign: _load),
                      ),
                    ),
        ),
        _PaginationBar(page: _page, total: _total, onPageChange: _goToPage),
      ],
    ),
  );
}

class _CollectionCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onAssign;
  const _CollectionCard({required this.item, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String? ?? '';
    final needsAssignment = status == 'finding' || status == 'proposed';
    final accent = _StatusBadge(status: status)._color;
    final collectorName = item['collector_name'] as String?;
    final destination = item['destination_address'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFEFEF)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status-colored accent bar — instant visual scan cue, common
            // in modern admin list/kanban rows.
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.delete_sweep_outlined, color: accent, size: 19),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _StatusBadge(status: status, compact: true),
                              const SizedBox(height: 4),
                              Text('${item['waste_type'] ?? ''} · ${item['bin_type'] ?? ''}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kTextDark),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(money(item['price'], prefix: 'GH₵'),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: _kPrimary, fontSize: 15)),
                            if (item['commission_amount'] != null)
                              Text('Comm GH₵${money(item['commission_amount'])}',
                                  style: const TextStyle(fontSize: 10, color: _kTextGray)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Customer / Collector — two-column grid.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _MiniField(Icons.person_outline, 'Customer', item['customer_name'] as String? ?? '')),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniField(
                            Icons.local_shipping_outlined,
                            'Collector',
                            collectorName ?? 'Not assigned',
                            valueColor: collectorName == null ? _kTextGray : null,
                            italic: collectorName == null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _MiniField(Icons.location_on_outlined, 'Pickup', item['pickup_address'] as String? ?? ''),
                    if (destination.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _MiniField(Icons.flag_outlined, 'Destination', destination),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _TagChip(Icons.straighten, '${item['distance_km']?.toStringAsFixed(1) ?? '0'} km'),
                        const _TagChip(Icons.payments_outlined, 'Cash on collection'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.map_outlined, size: 16),
                            label: const Text('Track'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kBlue,
                              side: const BorderSide(color: Color(0xFFDCE7F5)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => AdminCollectionMapPage(collection: item)),
                            ),
                          ),
                        ),
                        if (needsAssignment) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.person_add_outlined, size: 16),
                              label: const Text('Assign'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kPrimary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _showAssign(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAssign(BuildContext context) async {
    final collectors = await _fetchCollectors();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AssignSheet(
        requestId: item['id'] as int,
        collectors: collectors,
        onDone: onAssign,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchCollectors() async {
    try {
      // Admin assignment targets a specific collector directly — unlike
      // auto-matching, it must not require them to already be online (an
      // admin can assign to any approved collector; they'll see it whenever
      // they next open the app, same as any other admin-assigned task).
      // page_size=100 to avoid truncating the assignable pool.
      final List<Map<String, dynamic>> all;
      if (SupabaseService.isLoggedIn) {
        all = await SupabaseService.fetchAdminCollectors();
      } else {
        final res = await ApiService.get('${ApiConstants.adminCollectors}?page_size=100');
        all = (res['results'] as List? ?? []).cast<Map<String, dynamic>>();
      }
      final approved = all.where((c) => c['is_approved'] == true).toList();
      approved.sort((a, b) {
        final aOnline = a['is_online'] == true;
        final bOnline = b['is_online'] == true;
        if (aOnline == bOnline) return 0;
        return aOnline ? -1 : 1;
      });
      return approved;
    } catch (_) { return []; }
  }
}

class _AssignSheet extends StatefulWidget {
  final int requestId;
  final List<Map<String, dynamic>> collectors;
  final VoidCallback onDone;
  const _AssignSheet({required this.requestId, required this.collectors, required this.onDone});
  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  bool _loading = false;

  Future<void> _assign(dynamic collectorUserId) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    String? errorMessage;
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.adminAssignCollector(widget.requestId, collectorUserId as String);
      } else {
        await ApiService.post(ApiConstants.assignCollection(widget.requestId), {'collector_id': collectorUserId});
      }
      widget.onDone();
      navigator.pop();
    } catch (e) {
      errorMessage = 'Error: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // Feedback is best-effort — see _CollectorDetailPageState._doAction for why.
    try {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage ?? 'Assigned!')));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Assign Collector', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 16),
        if (_loading) const CircularProgressIndicator(color: _kPrimary)
        else if (widget.collectors.isEmpty)
          const Text('No approved collectors available', style: TextStyle(color: _kTextGray))
        else
          ...widget.collectors.map((c) {
            final online = c['is_online'] == true;
            return ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: _kPrimary.withValues(alpha: 0.1),
                    child: const Icon(Icons.person, color: _kPrimary),
                  ),
                  Positioned(
                    right: -1, bottom: -1,
                    child: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: online ? _kAccent : _kTextGray,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              title: Text(c['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${c['phone'] ?? ''} · ${online ? 'Online' : 'Offline'}',
                style: TextStyle(color: online ? _kAccent : _kTextGray),
              ),
              trailing: Text('⭐ ${c['rating'] ?? 0}'),
              onTap: () => _assign(c['user_id']),
            );
          }),
        const SizedBox(height: 16),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Collectors Tab
// ─────────────────────────────────────────────────────────────────────────────
class _CollectorsTab extends StatefulWidget {
  final VoidCallback onGoToDashboard;
  const _CollectorsTab({required this.onGoToDashboard});
  @override
  State<_CollectorsTab> createState() => _CollectorsTabState();
}

class _CollectorsTabState extends State<_CollectorsTab> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  int _total = 0, _page = 1;
  final _search = TextEditingController();
  String _kycFilter = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> res;
      if (SupabaseService.isLoggedIn) {
        res = await SupabaseService.fetchAdminCollectorsPaged(
          search: _search.text.trim(), kycStatus: _kycFilter, page: _page, pageSize: 20);
      } else {
        var url = '${ApiConstants.adminCollectors}?page=$_page&page_size=20';
        if (_search.text.isNotEmpty) url += '&search=${_search.text}';
        if (_kycFilter.isNotEmpty) url += '&kyc_status=$_kycFilter';
        res = await ApiService.get(url);
      }
      final list = (res['results'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _items = list;
        _total = (res['total'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {} finally { setState(() => _loading = false); }
  }

  void _goToPage(int p) { setState(() => _page = p); _load(); }

  static const _kycFilters = [
    ('', 'All'),
    ('pending', 'Pending KYC'),
    ('under_review', 'Under Review'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
    ('suspended', 'Suspended'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Collectors', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            onSubmitted: (_) { _page = 1; _load(); },
            decoration: InputDecoration(
              hintText: 'Search by name or phone…',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEFEFEF))),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: _kycFilters.length,
            itemBuilder: (_, i) {
              final (value, label) = _kycFilters[i];
              final selected = _kycFilter == value;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () { setState(() => _kycFilter = value); _page = 1; _load(); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? _kPrimary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: selected ? _kPrimary : const Color(0xFFE0E0E0)),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : _kTextGray)),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.groups_outlined, size: 14, color: _kTextGray),
            const SizedBox(width: 6),
            Text('$_total ${_total == 1 ? 'collector' : 'collectors'}',
                style: const TextStyle(fontSize: 12, color: _kTextGray, fontWeight: FontWeight.w600)),
          ]),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : _items.isEmpty
                  ? const _EmptyState(icon: Icons.local_shipping_outlined, message: 'No collectors found')
                  : RefreshIndicator(
                      onRefresh: () { _page = 1; return _load(); },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final collector = _items[i];
                          final isSuperAdmin = Provider.of<AppProvider>(context, listen: false).isSuperAdmin;
                          return _CollectorCard(
                            item: collector,
                            onAction: () { _page = 1; _load(); },
                            onGoToDashboard: widget.onGoToDashboard,
                            isSuperAdmin: isSuperAdmin,
                            onDelete: isSuperAdmin ? () async {
                              // The list item's 'id' is the CollectorProfile
                              // pk; the delete endpoint looks up a CustomUser
                              // by pk, which is 'user_id' here — sending the
                              // wrong one always 404s ("No CustomUser
                              // matches the given query"), so every delete
                              // attempt silently failed.
                              final id = collector['user_id'];
                              if (id == null) return;
                              final messenger = ScaffoldMessenger.of(context);
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Delete Collector?'),
                                  content: Text('Delete "${collector['name']}"? This cannot be undone.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: _kRed))),
                                  ],
                                ),
                              );
                              if (confirm != true) return;
                              try {
                                if (SupabaseService.isLoggedIn) {
                                  await SupabaseService.adminDeleteUser(id as String, expectedRole: 'collector');
                                } else {
                                  await ApiService.delete(ApiConstants.superAdminDeleteCollector(id as int));
                                }
                                if (mounted) setState(() => _items.removeWhere((c) => c['id'] == collector['id']));
                              } catch (e) {
                                messenger.showSnackBar(SnackBar(content: Text('Failed to delete collector: $e'), backgroundColor: _kRed));
                              }
                            } : null,
                          );
                        },
                      ),
                    ),
        ),
        _PaginationBar(page: _page, total: _total, onPageChange: _goToPage),
      ],
    ),
  );
}

class _CollectorCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onAction;
  final VoidCallback onGoToDashboard;
  final bool isSuperAdmin;
  final VoidCallback? onDelete;
  const _CollectorCard({required this.item, required this.onAction, required this.onGoToDashboard, this.isSuperAdmin = false, this.onDelete});

  Color _kycColor(String? s) {
    switch (s) {
      case 'approved': return _kAccent;
      case 'rejected': return _kRed;
      case 'suspended': return _kOrange;
      case 'under_review': return _kBlue;
      default: return _kTextGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kycStatus = item['kyc_status'] as String? ?? 'pending';
    final isApproved = item['is_approved'] == true;
    final isOnline = (item['is_online'] as bool?) == true;
    final score = (item['credit_score'] as num?)?.toInt() ?? 100;
    final scoreColor = score >= 80 ? _kAccent : score >= 50 ? _kOrange : _kRed;
    final accent = isApproved ? _kAccent : _kycColor(kycStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFEFEF)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _CollectorDetailPage(collector: item, onAction: onAction, onGoToDashboard: onGoToDashboard)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: accent.withValues(alpha: 0.1),
                            backgroundImage: item['profile_image'] != null
                                ? profileImageProvider(item['profile_image'] as String)
                                : null,
                            child: item['profile_image'] == null
                                ? Icon(Icons.person, color: accent, size: 28)
                                : null,
                          ),
                          Positioned(
                            right: 0, bottom: 0,
                            child: Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                color: isOnline ? _kAccent : const Color(0xFFBDBDBD),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(item['name'] as String? ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: _kTextDark),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: scoreColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star, size: 11, color: scoreColor),
                                      const SizedBox(width: 3),
                                      Text('$score', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: scoreColor)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(item['phone'] as String? ?? '', style: const TextStyle(fontSize: 12, color: _kTextGray)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                isApproved
                                    ? const _TagChip(Icons.verified, 'APPROVED')
                                    : _TagChip(Icons.hourglass_top, kycStatus.replaceAll('_', ' ').toUpperCase()),
                                const SizedBox(width: 6),
                                Text(isOnline ? 'Online' : 'Offline',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: isOnline ? _kAccent : _kTextGray)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.local_shipping_outlined, size: 12, color: _kTextGray),
                                const SizedBox(width: 4),
                                Text('${item['total_collections'] ?? 0} trips',
                                    style: const TextStyle(fontSize: 11.5, color: _kTextGray, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 12),
                                Icon(Icons.payments_outlined, size: 12, color: _kTextGray),
                                const SizedBox(width: 4),
                                Text(money(item['total_earnings'], prefix: 'GH₵', fallback: 'GH₵ 0.00'),
                                    style: const TextStyle(fontSize: 11.5, color: _kTextGray, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          const Icon(Icons.chevron_right, color: _kTextGray, size: 20),
                          if (isSuperAdmin && onDelete != null) ...[
                            const SizedBox(height: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: _kRed, size: 20),
                              tooltip: 'Delete collector',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: onDelete,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectorDetailPage extends StatefulWidget {
  final Map<String, dynamic> collector;
  final VoidCallback onAction;
  final VoidCallback onGoToDashboard;
  const _CollectorDetailPage({required this.collector, required this.onAction, required this.onGoToDashboard});
  @override
  State<_CollectorDetailPage> createState() => _CollectorDetailPageState();
}

class _CollectorDetailPageState extends State<_CollectorDetailPage> {
  bool _loading = false;
  bool _loadingDetail = true;
  Map<String, dynamic>? _detail;
  Map<String, dynamic> get _c => (_detail?['collector'] as Map<String, dynamic>?) ?? widget.collector;

  @override
  void initState() { super.initState(); _loadDetail(); }

  Future<void> _loadDetail() async {
    setState(() => _loadingDetail = true);
    try {
      final data = SupabaseService.isLoggedIn
          ? await SupabaseService.fetchCollectorKycDetail(widget.collector['id'] as int)
          : await ApiService.get(ApiConstants.collectorKycDetail(widget.collector['id'] as int));
      if (mounted) setState(() => _detail = data);
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _doAction(String action) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    String? errorMessage;
    try {
      final id = widget.collector['id'] as int;
      if (SupabaseService.isLoggedIn) {
        if (action == 'approve') {
          await SupabaseService.approveCollector(id);
        } else if (action == 'decline') {
          await SupabaseService.declineCollector(id);
        } else if (action == 'suspend') {
          await SupabaseService.suspendCollector(id);
        }
      } else if (action == 'approve') {
        await ApiService.post(ApiConstants.approveCollector(id), {});
      } else if (action == 'decline') {
        await ApiService.post(ApiConstants.declineCollector(id), {});
      } else if (action == 'suspend') {
        await ApiService.post(ApiConstants.suspendCollector(id), {});
      }
      widget.onAction();
      widget.onGoToDashboard();
      navigator.pop();
    } catch (e) {
      errorMessage = 'Error: $e';
    } finally { if (mounted) setState(() => _loading = false); }
    // Feedback is best-effort: ScaffoldMessenger.showSnackBar walks every
    // Scaffold currently registered anywhere in the app, so a stray one left
    // in a bad state elsewhere can make this throw — that must never undo
    // the approve/decline or block navigating away above.
    try {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage ?? '$action success')));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDetail) {
      return Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(widget.collector['name'] as String? ?? 'Collector',
              style: const TextStyle(color: _kTextDark, fontWeight: FontWeight.w700)),
        ),
        body: const Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
    }

    final c = _c;
    final kyc = _detail?['kyc'] as Map<String, dynamic>?;
    final vehicles = (_detail?['vehicles'] as List? ?? []).cast<Map<String, dynamic>>();
    final scoreEvents = (_detail?['score_events'] as List? ?? []).cast<Map<String, dynamic>>();
    final kycStatus = c['kyc_status'] as String? ?? kyc?['kyc_status'] as String? ?? 'pending';
    final isApproved = c['is_approved'] == true;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(c['name'] as String? ?? '', style: const TextStyle(color: _kTextDark, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadDetail,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: _kPrimary.withValues(alpha: 0.1),
                    backgroundImage: c['profile_image'] != null
                        ? profileImageProvider(c['profile_image'] as String)
                        : null,
                    child: c['profile_image'] == null ? const Icon(Icons.person, size: 40, color: _kPrimary) : null,
                  ),
                  const SizedBox(height: 12),
                  Text(c['name'] as String? ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(c['phone'] as String? ?? '', style: const TextStyle(color: _kTextGray)),
                  if ((c['email'] as String? ?? '').isNotEmpty)
                    Text(c['email'] as String, style: const TextStyle(color: _kTextGray, fontSize: 12)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (isApproved)
                        _StatusBadge(status: 'approved')
                      else
                        _StatusBadge(status: kycStatus),
                      if (c['is_online'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _kAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('ONLINE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kAccent)),
                        ),
                      if (c['password_set'] == false)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _kOrange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('PASSWORD NOT SET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kOrange)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _InfoChip('${c['total_collections'] ?? 0}', 'Trips'),
                    _InfoChip('GH₵${money(c['total_earnings'], fallback: '0.00')}', 'Earnings'),
                    _InfoChip('${c['credit_score'] ?? 100}', 'Score'),
                    _InfoChip('${c['rating'] ?? 0}⭐', 'Rating'),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              _SectionTitle2('Profile Details'),
              const SizedBox(height: 8),
              _DetailTile('Vehicle Type', c['vehicle_type'] as String? ?? '—'),
              _DetailTile('Vehicle Number', c['vehicle_number'] as String? ?? '—'),
              _DetailTile('Applied', _formatDate(c['applied_at'] as String?)),
              _DetailTile('Unpaid Commission', money(c['unpaid_commission'], prefix: 'GH₵', fallback: 'GH₵ 0.00')),
              if (parseDouble(c['unpaid_commission']) > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kOrange.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber, color: _kOrange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Owes GH₵${money(c['unpaid_commission'])} in cash commissions',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: _kOrange)),
                    ),
                  ]),
                ),
              ],
              if (kyc != null) ...[
                const SizedBox(height: 16),
                _SectionTitle2('KYC Information'),
                const SizedBox(height: 8),
                _DetailTile('Ghana Card', kyc['ghana_card_number'] as String? ?? '—'),
                _DetailTile('License Number', kyc['license_number'] as String? ?? '—'),
                if ((kyc['email'] as String? ?? '').isNotEmpty)
                  _DetailTile('Email', kyc['email'] as String),
                if ((kyc['vehicle_number_plate'] as String? ?? '').isNotEmpty)
                  _DetailTile('Plate on KYC', kyc['vehicle_number_plate'] as String),
                if ((kyc['rejection_reason'] as String? ?? '').isNotEmpty)
                  _DetailTile('Rejection Reason', kyc['rejection_reason'] as String),
                const SizedBox(height: 8),
                ...(kyc['documents'] as List? ?? []).map((d) => _KycDocRow(doc: d as Map<String, dynamic>)),
              ],
              if (vehicles.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionTitle2('Registered Vehicles'),
                const SizedBox(height: 8),
                ...vehicles.map((v) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v['name'] as String? ?? v['vehicle_type'] as String? ?? 'Vehicle',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        [
                          if ((v['vehicle_type'] as String?)?.isNotEmpty == true) v['vehicle_type'] as String,
                          if ((v['vehicle_number'] as String?)?.isNotEmpty == true) v['vehicle_number'] as String,
                        ].join(' • '),
                        style: const TextStyle(fontSize: 12, color: _kTextGray)),
                    if (v['driver_name'] != null)
                      Text('Driver: ${v['driver_name']}', style: const TextStyle(fontSize: 12, color: _kTextGray)),
                    if (v['vehicle_photo'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: v['vehicle_photo'] as String,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                  ]),
                )),
              ],
              if (scoreEvents.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionTitle2('Score History'),
                const SizedBox(height: 8),
                ...scoreEvents.take(5).map((ev) {
                  final pts = (ev['points_change'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    dense: true,
                    tileColor: _kCard,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    leading: Icon(pts >= 0 ? Icons.trending_up : Icons.trending_down,
                        color: pts >= 0 ? _kAccent : _kRed),
                    title: Text(ev['event_type'].toString().replaceAll('_', ' '),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(ev['note'] as String? ?? ''),
                    trailing: Text('${pts >= 0 ? '+' : ''}$pts pts',
                        style: TextStyle(fontWeight: FontWeight.w700, color: pts >= 0 ? _kAccent : _kRed)),
                  );
                }),
              ],
              const SizedBox(height: 16),
              if (_loading) const Center(child: CircularProgressIndicator(color: _kPrimary))
              else ...[
                if (!isApproved)
                  _ActionBtn('Approve Collector', _kAccent, () => _doAction('approve')),
                if (!isApproved && kycStatus != 'rejected')
                  _ActionBtn('Decline Application', _kRed, () => _doAction('decline')),
                if (isApproved && kycStatus != 'suspended')
                  _ActionBtn('Suspend Collector', _kOrange, () => _doAction('suspend')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

class _DetailTile extends StatelessWidget {
  final String label;
  final String value;
  const _DetailTile(this.label, this.value);
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: _kTextGray, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _kTextDark)),
    ]),
  );
}

class _KycDocRow extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _KycDocRow({required this.doc});

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open document')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = doc['url'] as String?;
    return ListTile(
      dense: true,
      tileColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: const Icon(Icons.insert_drive_file_outlined, color: _kPrimary),
      title: Text(doc['document_type_display'] as String? ?? doc['document_type'] as String? ?? '',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(doc['status'] as String? ?? '', style: const TextStyle(fontSize: 11)),
      trailing: url != null
          ? TextButton(
              onPressed: () => _openUrl(context, url),
              child: const Text('View', style: TextStyle(color: _kPrimary)),
            )
          : const Text('Not uploaded', style: TextStyle(color: _kTextGray, fontSize: 11)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// More Tab (Schedules, Reports, Customers)
// ─────────────────────────────────────────────────────────────────────────────
class _MoreTab extends StatelessWidget {
  const _MoreTab();
  Future<void> _logout(BuildContext context) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await provider.logout();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('More', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
    ),
    // Grouped into functional sections — the standard pattern for admin
    // "settings/management" menus (Stripe, Shopify, etc. group by domain
    // rather than one long flat list), so related tools are scannable together.
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const _MoreSectionHeader('People'),
        _MoreTile(Icons.people_outline, 'Customers', 'View all customers', _kBlue,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _CustomersPage()))),
        _MoreTile(Icons.person_add_outlined, 'Create User', 'Customer, collector, or investor', _kBlue, () {
          final isSA = Provider.of<AppProvider>(context, listen: false).isSuperAdmin;
          Navigator.push(context, MaterialPageRoute(builder: (_) => _AdminCreateUserPage(isSuperAdmin: isSA)));
        }),
        const _MoreSectionHeader('Operations'),
        _MoreTile(Icons.calendar_today_outlined, 'Schedules', 'Recurring pickups', _kPrimary,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _SchedulesPage()))),
        _MoreTile(Icons.delete_outline, 'Company Waste Bins', 'Manage company-owned bins', _kPrimary,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _CompanyBinsPage()))),
        _MoreTile(Icons.report_outlined, 'Dumping Reports', 'View filed reports', _kOrange,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _ReportsPage()))),
        _MoreTile(Icons.forum_outlined, 'Feedback & Complaints', 'Customer & collector tickets', _kPurple,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminTicketsPage()))),
        const _MoreSectionHeader('Catalog & Pricing'),
        _MoreTile(Icons.category_outlined, 'Waste Types', 'Manage waste categories & prices', _kTeal,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WasteTypesPage()))),
        _MoreTile(Icons.inventory_2_outlined, 'Bin Types', 'Manage bin sizes & pricing', _kTeal,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _BinTypesPage()))),
        const _MoreSectionHeader('Finance'),
        _MoreTile(Icons.bar_chart_outlined, 'Investors', 'View all investor accounts & returns', _kAccent,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _InvestorsListPage()))),
        const _MoreSectionHeader('Account'),
        _MoreTile(Icons.settings_outlined, 'Admin Profile', 'Update your profile', _kTextGray,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _AdminProfilePage()))),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF0F0F0)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _kRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.logout, color: _kRed, size: 22),
            ),
            title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w700, color: _kRed)),
            subtitle: const Text('Sign out of the admin portal',
                style: TextStyle(color: _kTextGray, fontSize: 12)),
            onTap: () => _logout(context),
          ),
        ),
      ],
    ),
  );
}

class _MoreSectionHeader extends StatelessWidget {
  final String title;
  const _MoreSectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _kTextGray, letterSpacing: 0.6),
    ),
  );
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _MoreTile(this.icon, this.title, this.subtitle, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: _kCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFF0F0F0)),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _kTextDark)),
          subtitle: Text(subtitle, style: const TextStyle(color: _kTextGray, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: _kTextGray),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Customers Page
// ─────────────────────────────────────────────────────────────────────────────
class _CustomersPage extends StatefulWidget {
  const _CustomersPage();
  @override
  State<_CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<_CustomersPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  int _total = 0, _page = 1;
  final _search = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> res;
      if (SupabaseService.isLoggedIn) {
        res = await SupabaseService.fetchAdminCustomersPaged(search: _search.text.trim(), page: _page, pageSize: 20);
      } else {
        var url = '${ApiConstants.adminCustomers}?page=$_page&page_size=20';
        if (_search.text.isNotEmpty) url += '&search=${_search.text}';
        res = await ApiService.get(url);
      }
      final list = (res['results'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _items = list;
        _total = (res['total'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {} finally { setState(() => _loading = false); }
  }

  void _goToPage(int p) { setState(() => _page = p); _load(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Customers', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            onSubmitted: (_) { _page = 1; _load(); },
            decoration: InputDecoration(
              hintText: 'Search…',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : _items.isEmpty
                  ? const _EmptyState(icon: Icons.people_outline, message: 'No customers found')
                  : RefreshIndicator(
                      onRefresh: () { _page = 1; return _load(); },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final c = _items[i];
                          final isSuperAdmin = Provider.of<AppProvider>(context, listen: false).isSuperAdmin;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _kPrimary.withValues(alpha: 0.1),
                                backgroundImage: c['profile_image'] != null
                                    ? profileImageProvider(c['profile_image'] as String)
                                    : null,
                                child: c['profile_image'] == null ? const Icon(Icons.person, color: _kPrimary) : null,
                              ),
                              title: Text(c['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(c['phone'] as String? ?? '', style: const TextStyle(fontSize: 12)),
                              trailing: isSuperAdmin
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text('${c['completed_requests']} trips', style: const TextStyle(fontSize: 11, color: _kTextGray)),
                                            Text('GH₵${money(c['total_spent'])}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kPrimary)),
                                          ],
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: _kRed, size: 20),
                                          tooltip: 'Delete customer',
                                          onPressed: () async {
                                            final id = c['id'];
                                            if (id == null) return;
                                            final messenger = ScaffoldMessenger.of(context);
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title: const Text('Delete Customer?'),
                                                content: Text('Delete "${c['name']}"? This cannot be undone.'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: _kRed))),
                                                ],
                                              ),
                                            );
                                            if (confirm != true) return;
                                            try {
                                              if (SupabaseService.isLoggedIn) {
                                                await SupabaseService.adminDeleteUser(id as String, expectedRole: 'customer');
                                              } else {
                                                await ApiService.delete(ApiConstants.superAdminDeleteCustomer(id as int));
                                              }
                                              if (mounted) setState(() => _items.removeWhere((x) => x['id'] == id));
                                            } catch (_) {
                                              messenger.showSnackBar(const SnackBar(content: Text('Failed to delete customer'), backgroundColor: _kRed));
                                            }
                                          },
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('${c['completed_requests']} trips', style: const TextStyle(fontSize: 11, color: _kTextGray)),
                                        Text('GH₵${money(c['total_spent'])}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kPrimary)),
                                      ],
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
        _PaginationBar(page: _page, total: _total, onPageChange: _goToPage),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedules Page
// ─────────────────────────────────────────────────────────────────────────────
class _SchedulesPage extends StatefulWidget {
  const _SchedulesPage();
  @override
  State<_SchedulesPage> createState() => _SchedulesPageState();
}

class _SchedulesPageState extends State<_SchedulesPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _total = 0;
  String _period = 'all';
  String _statusFilter = 'active'; // 'active' | 'cancelled' | 'all'
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    // Re-render every minute so the "in Xm" countdown stays live.
    _countdownTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _page = 1;
    setState(() => _loading = true);
    try {
      final isActiveParam = _statusFilter == 'all' ? 'all' : (_statusFilter == 'active' ? 'true' : 'false');
      final Map<String, dynamic> res;
      if (SupabaseService.isLoggedIn) {
        res = await SupabaseService.fetchAdminSchedulesPaged(
          isActive: isActiveParam, period: _period, page: _page, pageSize: 20);
      } else {
        final url = '${ApiConstants.adminSchedules}?page=$_page&page_size=20&period=$_period&is_active=$isActiveParam';
        res = await ApiService.get(url);
      }
      if (!mounted) return;
      setState(() {
        _items = (res['results'] as List? ?? []).cast<Map<String, dynamic>>();
        _total = (res['total'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToPage(int p) { setState(() => _page = p); _load(); }

  void _setPeriod(String p) {
    _period = p;
    _load(reset: true);
  }

  void _setStatusFilter(String s) {
    setState(() => _statusFilter = s);
    _load(reset: true);
  }

  String _countdown(String? nextDt) {
    if (nextDt == null) return '';
    try {
      final dt = DateTime.parse(nextDt);
      final diff = dt.difference(DateTime.now());
      if (diff.isNegative) return 'Overdue';
      if (diff.inDays > 0) return 'in ${diff.inDays}d ${diff.inHours % 24}h';
      if (diff.inHours > 0) return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
      return 'in ${diff.inMinutes}m';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Schedules', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
    ),
    floatingActionButton: FloatingActionButton(
      backgroundColor: _kPrimary,
      onPressed: () async {
        final created = await Navigator.push<bool>(context,
            MaterialPageRoute(builder: (_) => const _AdminCreateSchedulePage()));
        if (created == true) _load(reset: true);
      },
      child: const Icon(Icons.add, color: Colors.white),
    ),
    body: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              _PeriodChip(label: 'Active', selected: _statusFilter == 'active', onTap: () => _setStatusFilter('active')),
              _PeriodChip(label: 'Cancelled', selected: _statusFilter == 'cancelled', onTap: () => _setStatusFilter('cancelled')),
              _PeriodChip(label: 'All', selected: _statusFilter == 'all', onTap: () => _setStatusFilter('all')),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _PeriodChip(label: 'All time', selected: _period == 'all', onTap: () => _setPeriod('all')),
              _PeriodChip(label: 'Today', selected: _period == 'today', onTap: () => _setPeriod('today')),
              _PeriodChip(label: 'Yesterday', selected: _period == 'yesterday', onTap: () => _setPeriod('yesterday')),
              _PeriodChip(label: 'This Week', selected: _period == 'week', onTap: () => _setPeriod('week')),
            ],
          ),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : _items.isEmpty
                  ? const _EmptyState(icon: Icons.calendar_today_outlined, message: 'No schedules yet.\nTap + to create one.')
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final s = _items[i];
                          final isActive = s['is_active'] == true;
                          final nextDt = s['next_pickup_datetime'] as String?;
                          final countdown = _countdown(nextDt);
                          final collectorName = s['assigned_collector_name'] as String?;
                          return GestureDetector(
                            onTap: () async {
                              final changed = await Navigator.push<bool>(context,
                                  MaterialPageRoute(builder: (_) => _AdminScheduleDetailPage(schedule: s)));
                              if (changed == true) _load(reset: true);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: _kCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isActive ? _kPrimary.withValues(alpha: 0.15) : const Color(0xFFE0E0E0)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(
                                        color: (isActive ? _kPrimary : _kTextGray).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.event_repeat,
                                          color: isActive ? _kPrimary : _kTextGray, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(s['customer_name'] as String? ?? 'Customer',
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${(s['frequency'] as String? ?? '').replaceFirst(s['frequency'][0], (s['frequency'] as String)[0].toUpperCase())} • ${s['day_of_week']} • ${s['pickup_time']}',
                                            style: const TextStyle(fontSize: 12, color: _kTextGray),
                                          ),
                                          if (collectorName != null)
                                            Text('Collector: $collectorName',
                                                style: const TextStyle(fontSize: 11, color: _kBlue)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        _StatusBadge(status: isActive ? 'active' : 'cancelled'),
                                        if (countdown.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(countdown,
                                              style: TextStyle(
                                                fontSize: 11, fontWeight: FontWeight.w600,
                                                color: countdown == 'Overdue' ? _kRed : _kPrimary,
                                              )),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
        _PaginationBar(page: _page, total: _total, onPageChange: _goToPage),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Schedule Detail Page
// ─────────────────────────────────────────────────────────────────────────────
class _AdminScheduleDetailPage extends StatefulWidget {
  final Map<String, dynamic> schedule;
  const _AdminScheduleDetailPage({required this.schedule});
  @override
  State<_AdminScheduleDetailPage> createState() => _AdminScheduleDetailPageState();
}

class _AdminScheduleDetailPageState extends State<_AdminScheduleDetailPage> {
  late Map<String, dynamic> _s;
  bool _loading = false;
  List<Map<String, dynamic>> _collectors = [];
  dynamic _selectedCollectorId;
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    _s = Map.from(widget.schedule);
    _selectedCollectorId = _s['assigned_collector_id'];
    _loadCollectors();
    // Re-render every minute so the "in Xm" countdown stays live.
    _countdownTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  Future<void> _loadCollectors() async {
    try {
      final List<dynamic> results;
      if (SupabaseService.isLoggedIn) {
        results = await SupabaseService.fetchAdminCollectors();
      } else {
        final res = await ApiService.get('${ApiConstants.adminCollectors}?page_size=200');
        results = (res['results'] as List?) ?? [];
      }
      if (mounted) setState(() => _collectors = results.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Future<void> _assignCollector(dynamic collectorId) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    String? errorMessage;
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.assignScheduleCollector(_s['id'] as int, collectorId as String);
      } else {
        await ApiService.put(ApiConstants.assignSchedule(_s['id'] as int), {'collector_id': collectorId});
      }
      if (mounted) {
        setState(() {
          _selectedCollectorId = collectorId;
          final col = _collectors.firstWhere((c) => c['user_id'] == collectorId, orElse: () => {});
          _s['assigned_collector_id'] = collectorId;
          _s['assigned_collector_name'] = col['name'];
        });
      }
      navigator.pop(true);
    } catch (e) {
      errorMessage = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // Feedback is best-effort — see _CollectorDetailPageState._doAction for why.
    try {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage ?? 'Collector assigned')));
    } catch (_) {}
  }

  String _countdown(String? nextDt) {
    if (nextDt == null) return '';
    try {
      final dt = DateTime.parse(nextDt);
      final diff = dt.difference(DateTime.now());
      if (diff.isNegative) return 'Overdue';
      if (diff.inDays > 0) return 'in ${diff.inDays}d ${diff.inHours % 24}h';
      if (diff.inHours > 0) return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
      return 'in ${diff.inMinutes}m';
    } catch (_) { return ''; }
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: _kTextGray, fontSize: 13))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final nextDt = _s['next_pickup_datetime'] as String?;
    final countdown = _countdown(nextDt);
    final isActive = _s['is_active'] == true;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Schedule Detail', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCard, borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const Spacer(),
                    _StatusBadge(status: isActive ? 'active' : 'cancelled'),
                  ],
                ),
                if (countdown.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (countdown == 'Overdue' ? _kRed : _kPrimary).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Next pickup: $countdown',
                        style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13,
                          color: countdown == 'Overdue' ? _kRed : _kPrimary,
                        )),
                  ),
                ],
                const SizedBox(height: 16),
                _row('Customer', _s['customer_name'] as String? ?? '—'),
                _row('Phone', _s['customer_phone'] as String? ?? '—'),
                _row('Waste Type', _s['waste_type'] as String? ?? '—'),
                _row('Address', _s['pickup_address'] as String? ?? '—'),
                _row('Frequency', _s['frequency'] as String? ?? '—'),
                _row('Day', _s['day_of_week'] as String? ?? '—'),
                _row('Time', _s['pickup_time'] as String? ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCard, borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Assign Collector', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                if (_s['assigned_collector_name'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Current: ${_s['assigned_collector_name']}',
                        style: const TextStyle(fontSize: 13, color: _kTextGray)),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<dynamic>(
                      isExpanded: true,
                      value: _collectors.any((c) => c['user_id'] == _selectedCollectorId)
                          ? _selectedCollectorId
                          : null,
                      hint: const Text('Select a collector', style: TextStyle(color: _kTextGray)),
                      items: _collectors.map((c) => DropdownMenuItem<dynamic>(
                        value: c['user_id'],
                        child: Text(c['name'] as String? ?? ''),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedCollectorId = v),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_loading || _selectedCollectorId == null) ? null : () => _assignCollector(_selectedCollectorId!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Assign Collector', style: TextStyle(fontWeight: FontWeight.bold)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Admin Create Schedule Page
// ─────────────────────────────────────────────────────────────────────────────
class _AdminCreateSchedulePage extends StatefulWidget {
  const _AdminCreateSchedulePage();
  @override
  State<_AdminCreateSchedulePage> createState() => _AdminCreateSchedulePageState();
}

class _AdminCreateSchedulePageState extends State<_AdminCreateSchedulePage> {
  final _addressCtrl = TextEditingController();
  bool _saving = false;
  bool _loadingCustomers = false;

  // Customer search
  final _customerSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _customerResults = [];
  Map<String, dynamic>? _selectedCustomer;
  Timer? _searchDebounce;

  // Form values
  String? _wasteType;
  String? _frequency;
  String? _dayOfWeek;
  TimeOfDay _pickupTime = const TimeOfDay(hour: 8, minute: 0);
  double? _lat;
  double? _lng;

  // Waste types from backend
  List<Map<String, dynamic>> _wasteTypeOptions = [];
  bool _loadingWasteTypes = false;

  // Bin type + num bins
  Map<String, dynamic>? _binType;
  int _numBins = 1;
  List<Map<String, dynamic>> _binTypes = [];
  bool _loadingBinTypes = false;
  final _numBinsCustomCtrl = TextEditingController(text: '1');

  static const _frequencies = ['weekly', 'biweekly', 'monthly'];
  static const _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

  @override
  void initState() {
    super.initState();
    _loadWasteTypes();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _customerSearchCtrl.dispose();
    _numBinsCustomCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadWasteTypes() async {
    setState(() => _loadingWasteTypes = true);
    try {
      final List<dynamic> list;
      if (SupabaseService.isLoggedIn) {
        list = await SupabaseService.fetchWasteTypes();
      } else {
        final res = await ApiService.get(ApiConstants.adminWasteTypes);
        list = (res['data'] as List?) ?? (res['results'] as List?) ?? [];
      }
      if (mounted) setState(() => _wasteTypeOptions = list.cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) {
        setState(() => _wasteTypeOptions = [
        {'key': 'general', 'label': 'General Waste'},
        {'key': 'recyclable', 'label': 'Recyclable'},
        {'key': 'organic', 'label': 'Organic'},
        {'key': 'hazardous', 'label': 'Hazardous'},
      ]);
      }
    } finally {
      if (mounted) setState(() => _loadingWasteTypes = false);
    }
  }

  Future<void> _fetchBinTypes(String wasteType) async {
    setState(() { _loadingBinTypes = true; _binTypes = []; _binType = null; });
    try {
      final List<dynamic> list;
      if (SupabaseService.isLoggedIn) {
        list = await SupabaseService.fetchBinTypesForWasteTypeKey(wasteType);
      } else {
        final res = await ApiService.get('${ApiConstants.adminBinTypes}?waste_type=$wasteType&page_size=50');
        list = (res['data'] as List?) ?? (res['results'] as List?) ?? [];
      }
      if (mounted) setState(() => _binTypes = list.cast<Map<String, dynamic>>());
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingBinTypes = false);
    }
  }

  void _onCustomerSearch(String q) {
    _searchDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _customerResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _searchCustomers(q.trim()));
  }

  Future<void> _searchCustomers(String q) async {
    setState(() => _loadingCustomers = true);
    try {
      final List<dynamic> results;
      if (SupabaseService.isLoggedIn) {
        results = await SupabaseService.searchCustomersByName(q);
      } else {
        final res = await ApiService.get('${ApiConstants.adminCustomers}?search=${Uri.encodeComponent(q)}&page_size=20');
        results = (res['results'] as List?) ?? [];
      }
      if (mounted) setState(() => _customerResults = results.cast<Map<String, dynamic>>());
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingCustomers = false);
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _pickupTime);
    if (t != null) setState(() => _pickupTime = t);
  }

  Future<void> _pickLocation() async {
    final result = await showLocationPicker(context, allowAnyLocation: true);
    if (result != null && mounted) {
      setState(() {
        _addressCtrl.text = result['address'] as String? ?? _addressCtrl.text;
        _lat = (result['lat'] as num?)?.toDouble();
        _lng = (result['lng'] as num?)?.toDouble();
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedCustomer == null) { _snack('Select a customer'); return; }
    if (_wasteType == null) { _snack('Select waste type'); return; }
    if (_addressCtrl.text.trim().isEmpty) { _snack('Enter pickup address'); return; }
    if (_frequency == null) { _snack('Select frequency'); return; }
    if (_dayOfWeek == null) { _snack('Select day of week'); return; }

    setState(() => _saving = true);
    try {
      final timeStr = '${_pickupTime.hour.toString().padLeft(2, '0')}:${_pickupTime.minute.toString().padLeft(2, '0')}:00';
      final fields = {
        'customer_id': _selectedCustomer!['id'],
        'waste_type': _wasteType,
        'pickup_address': _addressCtrl.text.trim(),
        if (_lat != null) 'pickup_lat': _lat,
        if (_lng != null) 'pickup_lng': _lng,
        'frequency': _frequency,
        'day_of_week': _dayOfWeek,
        'pickup_time': timeStr,
        if (_binType != null) 'bin_type_id': _binType!['id'],
        'num_bins': _numBins,
      };
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.adminCreateSchedule(fields);
      } else {
        await ApiService.post(ApiConstants.adminSchedules, fields);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kTextDark)),
  );

  Widget _dropdownField<T>(String hint, T? value, List<T> items, ValueChanged<T?> onChange, {String Function(T)? label}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true, value: value,
          hint: Text(hint, style: const TextStyle(color: _kTextGray)),
          items: items.map((v) => DropdownMenuItem<T>(
            value: v,
            child: Text(label != null ? label(v) : '$v'),
          )).toList(),
          onChanged: onChange,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Create Schedule', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel('Customer'),
          TextField(
            controller: _customerSearchCtrl,
            onChanged: _onCustomerSearch,
            decoration: InputDecoration(
              hintText: 'Search by name or phone…',
              prefixIcon: const Icon(Icons.search, color: _kPrimary, size: 20),
              suffixIcon: _loadingCustomers
                  ? const Padding(padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary)))
                  : null,
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            ),
          ),
          if (_selectedCustomer != null)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kLightGreen, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: _kPrimary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_selectedCustomer!['name'] ?? ''} • ${_selectedCustomer!['phone'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kPrimary),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() { _selectedCustomer = null; _customerSearchCtrl.clear(); _customerResults = []; }),
                    child: const Icon(Icons.close, size: 18, color: _kTextGray),
                  ),
                ],
              ),
            )
          else if (_customerResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(
                children: _customerResults.take(6).map((c) => ListTile(
                  dense: true,
                  leading: const CircleAvatar(backgroundColor: Color(0xFFE8F5E9), radius: 16, child: Icon(Icons.person, color: Color(0xFF2E7D32), size: 16)),
                  title: Text(c['name'] as String? ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(c['phone'] as String? ?? '', style: const TextStyle(fontSize: 11)),
                  onTap: () => setState(() {
                    _selectedCustomer = c;
                    _customerSearchCtrl.text = c['name'] as String? ?? '';
                    _customerResults = [];
                  }),
                )).toList(),
              ),
            ),
          const SizedBox(height: 8),
          _sectionLabel('Waste Type'),
          if (_loadingWasteTypes)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))),
            )
          else
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true, value: _wasteType,
                  hint: const Text('Select waste type', style: TextStyle(color: _kTextGray)),
                  items: _wasteTypeOptions.map((wt) => DropdownMenuItem<String>(
                    value: wt['key'] as String,
                    child: Text(wt['label'] as String? ?? wt['key'] as String),
                  )).toList(),
                  onChanged: (v) {
                    setState(() => _wasteType = v);
                    if (v != null) _fetchBinTypes(v);
                  },
                ),
              ),
            ),
          if (_wasteType != null) ...[
            _sectionLabel('Bin Type'),
            if (_loadingBinTypes)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))),
              )
            else
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Map<String, dynamic>?>(
                    isExpanded: true,
                    value: _binType,
                    hint: const Text('Select bin type (optional)', style: TextStyle(color: _kTextGray)),
                    items: [
                      const DropdownMenuItem<Map<String, dynamic>?>(value: null, child: Text('None')),
                      ..._binTypes.map((bt) => DropdownMenuItem<Map<String, dynamic>?>(
                        value: bt,
                        child: Text('${bt['display_name'] ?? ''} • ${bt['size_label'] ?? ''} — ${money(bt['price'], prefix: 'GHS', fallback: 'GHS 0.00')}'),
                      )),
                    ],
                    onChanged: (v) => setState(() => _binType = v),
                  ),
                ),
              ),
            _sectionLabel('Number of Bins'),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...[1, 2, 3, 4, 5, 6].map((n) => GestureDetector(
                        onTap: () => setState(() {
                          _numBins = n;
                          _numBinsCustomCtrl.text = '$n';
                        }),
                        child: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: _numBins == n ? _kPrimary : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _numBins == n ? _kPrimary : const Color(0xFFE0E0E0)),
                          ),
                          alignment: Alignment.center,
                          child: Text('$n', style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _numBins == n ? Colors.white : _kTextDark,
                          )),
                        ),
                      )),
                      SizedBox(
                        width: 80,
                        height: 44,
                        child: TextField(
                          controller: _numBinsCustomCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: 'Custom',
                            hintStyle: const TextStyle(fontSize: 12, color: _kTextGray),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                          ),
                          onChanged: (v) {
                            final parsed = int.tryParse(v);
                            if (parsed != null && parsed > 0) setState(() => _numBins = parsed);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          _sectionLabel('Pickup Address'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    hintText: 'Enter or pick address',
                    filled: true, fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.my_location, color: _kPrimary), onPressed: _pickLocation),
            ],
          ),
          const SizedBox(height: 14),
          _sectionLabel('Frequency'),
          _dropdownField<String>('Select frequency', _frequency, _frequencies,
              (v) => setState(() => _frequency = v),
              label: (v) => v[0].toUpperCase() + v.substring(1)),
          _sectionLabel('Day of Week'),
          _dropdownField<String>('Select day', _dayOfWeek, _days,
              (v) => setState(() => _dayOfWeek = v),
              label: (v) => v[0].toUpperCase() + v.substring(1)),
          _sectionLabel('Pickup Time'),
          GestureDetector(
            onTap: _pickTime,
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: _kPrimary, size: 20),
                  const SizedBox(width: 10),
                  Text(_pickupTime.format(context),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const Text('Tap to change', style: TextStyle(fontSize: 12, color: _kTextGray)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Create Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: _kPrimary.withValues(alpha: 0.15),
      checkmarkColor: _kPrimary,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reports Page
// ─────────────────────────────────────────────────────────────────────────────
class _ReportsPage extends StatefulWidget {
  const _ReportsPage();
  @override
  State<_ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<_ReportsPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  int _total = 0, _page = 1;
  String _status = '';

  static const _statusFilters = [
    ('', 'All'),
    ('pending', 'Pending'),
    ('investigating', 'Investigating'),
    ('resolved', 'Resolved'),
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (SupabaseService.isLoggedIn) {
        var all = await SupabaseService.fetchAdminReports();
        if (_status.isNotEmpty) all = all.where((r) => r['status'] == _status).toList();
        final total = all.length;
        const pageSize = 20;
        final start = (_page - 1) * pageSize;
        final end = (start + pageSize).clamp(0, total);
        setState(() {
          _items = start >= total ? [] : all.sublist(start, end);
          _total = total;
        });
      } else {
        var url = '${ApiConstants.adminReports}?page=$_page&page_size=20';
        if (_status.isNotEmpty) url += '&status=$_status';
        final res = await ApiService.get(url);
        setState(() {
          _items = (res['results'] as List? ?? []).cast<Map<String, dynamic>>();
          _total = (res['total'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {} finally { setState(() => _loading = false); }
  }

  void _goToPage(int p) { setState(() => _page = p); _load(); }

  void _setStatus(String s) {
    setState(() { _status = s; _page = 1; });
    _load();
  }

  Future<void> _resolve(int id) async {
    if (SupabaseService.isLoggedIn) {
      await SupabaseService.resolveReport(id);
    } else {
      await ApiService.post(ApiConstants.resolveReport(id), {});
    }
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Dumping Reports', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
    ),
    body: Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _statusFilters.length,
            itemBuilder: (_, i) {
              final (value, label) = _statusFilters[i];
              final selected = _status == value;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _setStatus(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? _kPrimary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: selected ? _kPrimary : const Color(0xFFE0E0E0)),
                    ),
                    child: Text(label,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : _kTextGray)),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : _items.isEmpty
                  ? const _EmptyState(icon: Icons.report_outlined, message: 'No reports')
                  : RefreshIndicator(
                      onRefresh: () { _page = 1; return _load(); },
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final r = _items[i];
                          final status = r['status'] as String? ?? 'pending';
                          final accent = _StatusBadge(status: status)._color;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: _kCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFEFEFEF)),
                              boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(width: 4, color: accent),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 34, height: 34,
                                                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                                                child: Icon(Icons.report_outlined, color: accent, size: 17),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(child: _StatusBadge(status: status, compact: true)),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Text(r['description'] as String? ?? '',
                                              maxLines: 2, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: _kTextDark)),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.location_on_outlined, size: 12, color: _kTextGray),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(r['location'] as String? ?? '',
                                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 11.5, color: _kTextGray)),
                                              ),
                                            ],
                                          ),
                                          if (status != 'resolved') ...[
                                            const SizedBox(height: 10),
                                            SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton(
                                                onPressed: () => _resolve(r['id'] as int),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: _kPrimary,
                                                  side: const BorderSide(color: Color(0xFFDCEEDD)),
                                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                child: Text(status == 'investigating' ? 'Mark Resolved' : 'Resolve',
                                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
        _PaginationBar(page: _page, total: _total, onPageChange: _goToPage),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Create User Page
// ─────────────────────────────────────────────────────────────────────────────
class _AdminCreateUserPage extends StatefulWidget {
  final bool isSuperAdmin;
  const _AdminCreateUserPage({this.isSuperAdmin = false});
  @override
  State<_AdminCreateUserPage> createState() => _AdminCreateUserPageState();
}

class _AdminCreateUserPageState extends State<_AdminCreateUserPage> with SingleTickerProviderStateMixin {
  late TabController _tc;
  bool _loading = false;
  final _picker = ImagePicker();

  static const _vehicleTypes = [
    'Pickup Truck',
    'Tricycle',
    'Motorcycle',
    'Van',
    'Mini Van',
    'Mini Truck',
    'Large Van',
    'Tipper Truck',
  ];

  final _custFirst = TextEditingController();
  final _custLast = TextEditingController();
  final _custPhone = TextEditingController();
  final _custEmail = TextEditingController();
  final _custPass = TextEditingController();

  final _colName = TextEditingController();
  final _colPhone = TextEditingController();
  final _colGhanaCard = TextEditingController();
  final _colLicense = TextEditingController();
  final _colVehicleName = TextEditingController();
  final _colVehicleNumber = TextEditingController();
  final _colPass = TextEditingController();
  String _colVehicleType = _vehicleTypes.first;
  bool _colAutoApprove = false;
  bool _colIsCompany = false;
  File? _colGhanaFront;
  File? _colGhanaBack;
  File? _colLicenseFront;
  File? _colLicenseBack;
  File? _colVehiclePhoto;

  // Branch assignment (super admin only)
  int? _colBranchId;
  List<Map<String, dynamic>> _availableBranches = [];
  bool _loadingBranches = false;

  // Existing vehicle assignment
  int? _existingVehicleId;
  List<Map<String, dynamic>> _availableVehicles = [];
  bool _loadingVehicles = false;

  final _invFirst = TextEditingController();
  final _invLast = TextEditingController();
  final _invPhone = TextEditingController();
  final _invLocation = TextEditingController();
  final _invAmount = TextEditingController();
  final _invRoi = TextEditingController();
  double? _invLat;
  double? _invLng;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: widget.isSuperAdmin ? 3 : 2, vsync: this);
    _fetchAvailableVehicles();
    if (widget.isSuperAdmin) _fetchAvailableBranches();
  }

  Future<void> _fetchAvailableBranches() async {
    setState(() => _loadingBranches = true);
    try {
      if (SupabaseService.isLoggedIn) {
        final list = await SupabaseService.fetchAllBranches();
        if (mounted) setState(() => _availableBranches = list);
      } else {
        final res = await ApiService.get('${ApiConstants.superAdminBranches}?page_size=100');
        if (mounted) setState(() => _availableBranches = (res['results'] as List? ?? []).cast<Map<String, dynamic>>());
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  Future<void> _fetchAvailableVehicles() async {
    setState(() => _loadingVehicles = true);
    try {
      if (SupabaseService.isLoggedIn) {
        final list = await SupabaseService.fetchUnassignedVehicles();
        if (mounted) setState(() => _availableVehicles = list);
      } else {
        final res = await ApiService.get('${ApiConstants.adminVehicles}?unassigned=true&page_size=100');
        if (mounted) setState(() => _availableVehicles = (res['results'] as List? ?? []).cast<Map<String, dynamic>>());
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    _custFirst.dispose(); _custLast.dispose(); _custPhone.dispose(); _custEmail.dispose(); _custPass.dispose();
    _colName.dispose(); _colPhone.dispose(); _colGhanaCard.dispose(); _colLicense.dispose();
    _colVehicleName.dispose(); _colVehicleNumber.dispose(); _colPass.dispose();
    _invFirst.dispose(); _invLast.dispose(); _invPhone.dispose();
    _invLocation.dispose(); _invAmount.dispose(); _invRoi.dispose();
    super.dispose();
  }

  Future<File?> _pickImage(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    return x != null ? File(x.path) : null;
  }

  Future<void> _choosePhoto(void Function(File?) setFile) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final f = await _pickImage(source);
    if (f != null) setState(() => setFile(f));
  }

  Widget _photoTile(File? file, VoidCallback onTap, {required String label}) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
      ),
      child: file != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FileImageView(file, fit: BoxFit.cover, width: double.infinity),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo_outlined, color: _kPrimary.withValues(alpha: 0.7)),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 11, color: _kTextGray)),
              ],
            ),
    ),
  );

  Future<void> _pickInvestorLocation() async {
    final result = await showLocationPicker(context, allowAnyLocation: true);
    if (result == null) return;
    setState(() {
      _invLocation.text = result['address'] as String? ?? '';
      _invLat = (result['lat'] as num?)?.toDouble();
      _invLng = (result['lng'] as num?)?.toDouble();
    });
  }

  Future<void> _createCustomer() async {
    setState(() => _loading = true);
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.adminCreateCustomer(
          firstName: _custFirst.text.trim(),
          lastName: _custLast.text.trim(),
          phone: _custPhone.text.trim(),
          email: _custEmail.text.trim(),
          password: _custPass.text.trim(),
        );
      } else {
        await ApiService.post(ApiConstants.adminCustomers, {
          'first_name': _custFirst.text.trim(),
          'last_name': _custLast.text.trim(),
          'phone': _custPhone.text.trim(),
          if (_custEmail.text.isNotEmpty) 'email': _custEmail.text.trim(),
          if (_custPass.text.isNotEmpty) 'password': _custPass.text.trim(),
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer created')));
      // Stay on this tab (for adding several accounts in a row) but clear
      // the form — otherwise tapping Create again resubmits the exact same
      // name/phone, risking a duplicate or a confusing uniqueness error.
      _custFirst.clear();
      _custLast.clear();
      _custPhone.clear();
      _custEmail.clear();
      _custPass.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _createCollector() async {
    final usingExisting = _existingVehicleId != null;

    if (_colName.text.trim().isEmpty ||
        _colPhone.text.trim().isEmpty ||
        _colGhanaCard.text.trim().isEmpty ||
        _colLicense.text.trim().isEmpty ||
        (!usingExisting && _colVehicleNumber.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in all required fields')),
      );
      return;
    }
    if (_colGhanaFront == null || _colGhanaBack == null ||
        _colLicenseFront == null || _colLicenseBack == null ||
        (!usingExisting && _colVehiclePhoto == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload Ghana card, license, and vehicle photos')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final Map<String, dynamic> res;
      if (SupabaseService.isLoggedIn) {
        final images = <String, Uint8List>{
          'ghana_card_front': await readFileBytes(_colGhanaFront!),
          'ghana_card_back': await readFileBytes(_colGhanaBack!),
          'license_front': await readFileBytes(_colLicenseFront!),
          'license_back': await readFileBytes(_colLicenseBack!),
          if (!usingExisting) 'vehicle_photo': await readFileBytes(_colVehiclePhoto!),
        };
        res = await SupabaseService.adminCreateCollector(
          name: _colName.text.trim(),
          phone: _colPhone.text.trim(),
          ghanaCardNumber: _colGhanaCard.text.trim(),
          licenseNumber: _colLicense.text.trim(),
          autoApprove: _colAutoApprove,
          isCompanyCollector: _colIsCompany,
          existingVehicleId: usingExisting ? _existingVehicleId : null,
          vehicleType: usingExisting ? null : _colVehicleType,
          vehicleNumber: usingExisting ? null : _colVehicleNumber.text.trim(),
          vehicleName: (!usingExisting && _colVehicleName.text.trim().isNotEmpty) ? _colVehicleName.text.trim() : null,
          password: _colPass.text.trim(),
          branchId: (widget.isSuperAdmin && _colBranchId != null) ? _colBranchId : null,
          images: images,
        );
      } else {
        final fields = <String, String>{
          'name': _colName.text.trim(),
          'phone': _colPhone.text.trim(),
          'ghana_card_number': _colGhanaCard.text.trim(),
          'license_number': _colLicense.text.trim(),
          'auto_approve': _colAutoApprove.toString(),
          'is_company_collector': _colIsCompany.toString(),
        };
        if (usingExisting) {
          fields['existing_vehicle_id'] = _existingVehicleId.toString();
        } else {
          fields['vehicle_type'] = _colVehicleType;
          fields['vehicle_number'] = _colVehicleNumber.text.trim();
          if (_colVehicleName.text.trim().isNotEmpty) {
            fields['vehicle_name'] = _colVehicleName.text.trim();
          }
        }
        if (_colPass.text.isNotEmpty) fields['password'] = _colPass.text.trim();
        if (widget.isSuperAdmin && _colBranchId != null) fields['branch_id'] = _colBranchId.toString();

        final files = <String, File>{
          'ghana_card_front': _colGhanaFront!,
          'ghana_card_back': _colGhanaBack!,
          'license_front': _colLicenseFront!,
          'license_back': _colLicenseBack!,
          if (!usingExisting) 'vehicle_photo': _colVehiclePhoto!,
        };

        res = await ApiService.postMultipart(ApiConstants.adminCollectors, fields, files);
      }
      if (!mounted) return;
      final temp = res['collector']?['temporary_password'];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(temp != null ? 'Collector created. Temp password: $temp' : 'Collector created'),
      ));
      // Stay on this tab but clear the form — otherwise tapping Create
      // again resubmits the same name/phone/photos as a duplicate.
      setState(() {
        _colName.clear();
        _colPhone.clear();
        _colGhanaCard.clear();
        _colLicense.clear();
        _colVehicleNumber.clear();
        _colVehicleName.clear();
        _colPass.clear();
        _colGhanaFront = null;
        _colGhanaBack = null;
        _colLicenseFront = null;
        _colLicenseBack = null;
        _colVehiclePhoto = null;
        _existingVehicleId = null;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _createInvestor() async {
    if (_invFirst.text.trim().isEmpty ||
        _invLast.text.trim().isEmpty ||
        _invPhone.text.trim().isEmpty ||
        _invLocation.text.trim().isEmpty ||
        _invAmount.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in all required fields')),
      );
      return;
    }
    if (looksLikeCoordinates(_invLocation.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location must be a place name, not GPS coordinates. '
            'Tap the GPS icon and pick an address from search.',
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.adminCreateInvestor(
          firstName: _invFirst.text.trim(),
          lastName: _invLast.text.trim(),
          phone: _invPhone.text.trim(),
          location: _invLocation.text.trim(),
          investmentAmount: _invAmount.text.trim(),
          roiPercentage: _invRoi.text.trim().isEmpty ? '0' : _invRoi.text.trim(),
          locationLat: _invLat,
          locationLng: _invLng,
        );
      } else {
        final payload = <String, dynamic>{
          'first_name': _invFirst.text.trim(),
          'last_name': _invLast.text.trim(),
          'phone': _invPhone.text.trim(),
          'location': _invLocation.text.trim(),
          'investment_amount': _invAmount.text.trim(),
          'roi_percentage': _invRoi.text.trim().isEmpty ? '0' : _invRoi.text.trim(),
        };
        if (_invLat != null) payload['location_latitude'] = _invLat.toString();
        if (_invLng != null) payload['location_longitude'] = _invLng.toString();

        await ApiService.post(ApiConstants.adminInvestors, payload);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Investor account created. They can set their password on first login.')),
      );
      Navigator.pop(context); // go back to investor list
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Widget _field(String label, TextEditingController c, {TextInputType? type, Widget? suffixIcon}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _kTextDark)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Create User', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
      bottom: TabBar(
        controller: _tc,
        labelColor: _kPrimary,
        unselectedLabelColor: _kTextGray,
        tabs: [
          const Tab(text: 'Customer'),
          const Tab(text: 'Collector'),
          if (widget.isSuperAdmin) const Tab(text: 'Investor'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tc,
      children: [
        ListView(padding: const EdgeInsets.all(16), children: [
          _field('First Name', _custFirst),
          _field('Last Name', _custLast),
          _field('Phone', _custPhone, type: TextInputType.phone),
          _field('Email (optional)', _custEmail, type: TextInputType.emailAddress),
          _field('Password (optional)', _custPass),
          ElevatedButton(onPressed: _loading ? null : _createCustomer,
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Create Customer')),
        ]),
        ListView(padding: const EdgeInsets.all(16), children: [
          _sectionTitle('Collector details'),
          if (widget.isSuperAdmin) ...[
            const Text('Assign to Branch', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _loadingBranches
                  ? const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2),
                    ))
                  : InputDecorator(
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _colBranchId,
                          isExpanded: true,
                          hint: const Text('No branch assigned', style: TextStyle(color: _kTextGray)),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('No branch assigned')),
                            ..._availableBranches.map((b) => DropdownMenuItem<int?>(
                              value: b['id'] as int?,
                              child: Text(b['name'] as String? ?? 'Branch ${b['id']}'),
                            )),
                          ],
                          onChanged: (v) => setState(() => _colBranchId = v),
                        ),
                      ),
                    ),
            ),
          ],
          _field('Full Name', _colName),
          _field('Phone', _colPhone, type: TextInputType.phone),
          _field('Ghana Card Number', _colGhanaCard),
          const Text('Ghana card (front & back)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _photoTile(_colGhanaFront, () => _choosePhoto((f) => _colGhanaFront = f), label: 'Front')),
            const SizedBox(width: 10),
            Expanded(child: _photoTile(_colGhanaBack, () => _choosePhoto((f) => _colGhanaBack = f), label: 'Back')),
          ]),
          const SizedBox(height: 12),
          _field('License Number', _colLicense),
          const Text('Driver license (front & back)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _photoTile(_colLicenseFront, () => _choosePhoto((f) => _colLicenseFront = f), label: 'Front')),
            const SizedBox(width: 10),
            Expanded(child: _photoTile(_colLicenseBack, () => _choosePhoto((f) => _colLicenseBack = f), label: 'Back')),
          ]),
          _sectionTitle('Vehicle'),
          // Assign existing vehicle section
          const Text('Assign Existing Vehicle (optional)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _loadingVehicles
                ? const Center(child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2),
                  ))
                : InputDecorator(
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _existingVehicleId,
                        isExpanded: true,
                        hint: const Text('None — create new vehicle below', style: TextStyle(color: _kTextGray)),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('None — create new vehicle below')),
                          ..._availableVehicles.map((v) => DropdownMenuItem<int?>(
                            value: v['id'] as int?,
                            child: Text('${v['vehicle_number'] ?? ''} • ${v['vehicle_type'] ?? ''}'),
                          )),
                        ],
                        onChanged: (v) => setState(() => _existingVehicleId = v),
                      ),
                    ),
                  ),
          ),
          if (_existingVehicleId != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _kLightGreen, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kPrimary.withValues(alpha: 0.3))),
              child: Row(children: [
                const Icon(Icons.check_circle, color: _kPrimary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    () {
                      final v = _availableVehicles.firstWhere((x) => x['id'] == _existingVehicleId, orElse: () => {});
                      return '${v['vehicle_number'] ?? ''} • ${v['vehicle_type'] ?? ''} — will be assigned to this collector';
                    }(),
                    style: const TextStyle(fontSize: 12, color: _kPrimary, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          if (_existingVehicleId == null) ...[
            // New vehicle creation fields
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Vehicle Type',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _colVehicleType,
                    isExpanded: true,
                    items: _vehicleTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) { if (v != null) setState(() => _colVehicleType = v); },
                  ),
                ),
              ),
            ),
            _field('Vehicle Name (optional)', _colVehicleName),
            _field('Registration Number', _colVehicleNumber),
            const Text('Vehicle photo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            _photoTile(_colVehiclePhoto, () => _choosePhoto((f) => _colVehiclePhoto = f), label: 'Vehicle'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'The new collector will be assigned as the driver for this vehicle.',
                style: TextStyle(fontSize: 12, color: _kTextGray),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _field('Password (optional)', _colPass),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Company Collector'),
            subtitle: const Text('Full collection amount counts as company revenue',
                style: TextStyle(fontSize: 11, color: _kTextGray)),
            value: _colIsCompany,
            activeThumbColor: _kPrimary,
            onChanged: (v) => setState(() => _colIsCompany = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Approve immediately'),
            value: _colAutoApprove,
            activeThumbColor: _kPrimary,
            onChanged: (v) => setState(() => _colAutoApprove = v),
          ),
          ElevatedButton(onPressed: _loading ? null : _createCollector,
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Create Collector')),
        ]),
        if (widget.isSuperAdmin)
          ListView(padding: const EdgeInsets.all(16), children: [
            _field('First Name', _invFirst),
            _field('Last Name', _invLast),
            _field('Phone', _invPhone, type: TextInputType.phone),
            _field(
              'Location',
              _invLocation,
              suffixIcon: IconButton(
                icon: const Icon(Icons.my_location, color: _kPrimary),
                tooltip: 'Pick location with GPS',
                onPressed: _pickInvestorLocation,
              ),
            ),
            _field('Investment Amount (GHS)', _invAmount, type: TextInputType.number),
            _field('ROI %', _invRoi, type: TextInputType.number),
            ElevatedButton(onPressed: _loading ? null : _createInvestor,
                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Create Investor')),
          ]),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Profile Page
// ─────────────────────────────────────────────────────────────────────────────
class _AdminProfilePage extends StatefulWidget {
  const _AdminProfilePage();
  @override
  State<_AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<_AdminProfilePage> {
  bool _loading = false;
  bool _loggingOut = false;
  Map<String, dynamic>? _profile;
  final _username = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  File? _imageFile;

  @override
  void initState() { super.initState(); _loadProfile(); }

  Future<void> _loadProfile() async {
    try {
      final res = SupabaseService.isLoggedIn
          ? await SupabaseService.fetchCurrentProfile()
          : await ApiService.get(ApiConstants.adminProfile);
      setState(() {
        _profile = res;
        _username.text = res['username'] as String? ?? '';
        _firstName.text = res['first_name'] as String? ?? '';
        _lastName.text = res['last_name'] as String? ?? '';
        _email.text = res['email'] as String? ?? '';
        _phone.text = res['phone'] as String? ?? '';
      });
    } catch (_) {}
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _imageFile = File(picked.path));
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _kTextGray)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: _kRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loggingOut = true);
    if (SupabaseService.isLoggedIn) {
      try { await SupabaseService.logout(); } catch (_) {}
    } else {
      final refresh = await ApiService.getRefreshToken();
      try {
        if (refresh != null) {
          await ApiService.post(ApiConstants.logout, {'refresh': refresh});
        }
      } catch (_) {}
      await ApiService.clearTokens();
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      bool emailChangePending = false;
      if (SupabaseService.isLoggedIn) {
        if (_imageFile != null) {
          final ext = kIsWeb ? 'jpg' : _imageFile!.path.split('.').last;
          await SupabaseService.uploadProfileImage(await readFileBytes(_imageFile!), ext: ext);
        }
        final newEmail = _email.text.trim();
        final oldEmail = _profile?['email'] as String? ?? '';
        if (newEmail.isNotEmpty && newEmail != oldEmail) {
          await SupabaseService.updateOwnEmail(newEmail);
          emailChangePending = true;
        }
        await SupabaseService.updateOwnProfile({
          'username': _username.text.trim(),
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'email': newEmail,
          'phone': _phone.text.trim(),
        });
      } else {
        await ApiService.patchMultipart(ApiConstants.adminProfile, {
          'username': _username.text,
          'first_name': _firstName.text,
          'last_name': _lastName.text,
          'email': _email.text,
          'phone': _phone.text,
        }, imageFile: _imageFile, imageField: 'profile_image');
      }
      if (!mounted) return;
      await context.read<AppProvider>().refreshProfileImageFromServer();
      await _loadProfile();
      if (mounted) {
        setState(() {
          _imageFile = null;
          if (context.read<AppProvider>().profileImageUrl != null) {
            _profile = {
              ...?_profile,
              'profile_image': context.read<AppProvider>().profileImageUrl,
            };
          }
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          emailChangePending
              ? 'Profile updated! Check your old and new email inboxes to confirm the email change.'
              : 'Profile updated!',
        )));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Admin Profile', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                _imageFile != null
                    ? FileCircleAvatar(file: _imageFile, radius: 50, backgroundColor: _kPrimary.withValues(alpha: 0.1))
                    : CircleAvatar(
                        radius: 50,
                        backgroundColor: _kPrimary.withValues(alpha: 0.1),
                        backgroundImage: _profile?['profile_image'] != null
                            ? profileImageProvider(_profile!['profile_image'] as String)
                            : null,
                        child: _profile?['profile_image'] == null
                            ? const Icon(Icons.admin_panel_settings, size: 50, color: _kPrimary)
                            : null,
                      ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: _kPrimary, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Field(_username, 'Username', Icons.alternate_email),
          const SizedBox(height: 12),
          _Field(_firstName, 'First Name', Icons.person_outline),
          const SizedBox(height: 12),
          _Field(_lastName, 'Last Name', Icons.person_outline),
          const SizedBox(height: 12),
          _Field(_email, 'Email', Icons.email_outlined, type: TextInputType.emailAddress),
          const SizedBox(height: 12),
          _Field(_phone, 'Phone', Icons.phone_outlined, type: TextInputType.phone),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
              ),
              icon: const Icon(Icons.lock_outline, color: _kPrimary, size: 20),
              label: const Text('Change Password', style: TextStyle(color: _kPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: _kPrimary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loggingOut ? null : _logout,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kRed),
                    )
                  : const Icon(Icons.logout, color: _kRed, size: 20),
              label: Text(
                _loggingOut ? 'Logging out…' : 'Logout',
                style: const TextStyle(
                  color: _kRed, fontWeight: FontWeight.w700, fontSize: 15,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: _kRed),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String title, value;
  final String? subtitle;
  final IconData icon;
  final List<Color> gradient;
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: gradient.first.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
    ),
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 22),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 11, fontWeight: FontWeight.w600)),
        if (subtitle != null)
          Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10),
              maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 10, color: _kTextGray)),
    ]),
  );
}

const _kPurple = Color(0xFF6A1B9A);
const _kTeal = Color(0xFF00838F);

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool compact;
  const _StatusBadge({required this.status, this.compact = false});

  Color get _color {
    switch (status) {
      case 'completed': return _kAccent;
      case 'cancelled': return _kRed;
      case 'on_way': return _kBlue;
      case 'arrived': return _kTeal;
      case 'assigned': return _kPrimary;
      case 'proposed': return _kPurple;
      case 'finding': return _kOrange;
      case 'active': return _kAccent;
      case 'inactive': return _kTextGray;
      case 'pending': return _kOrange;
      case 'investigating': return _kBlue;
      case 'resolved': return _kAccent;
      default: return _kOrange;
    }
  }

  IconData get _icon {
    switch (status) {
      case 'completed': return Icons.check_circle;
      case 'cancelled': return Icons.cancel;
      case 'on_way': return Icons.local_shipping;
      case 'arrived': return Icons.location_on;
      case 'assigned': return Icons.assignment_turned_in;
      case 'proposed': return Icons.hourglass_top;
      case 'finding': return Icons.search;
      case 'active': return Icons.check_circle;
      case 'inactive': return Icons.pause_circle;
      case 'pending': return Icons.schedule;
      case 'investigating': return Icons.search;
      case 'resolved': return Icons.check_circle;
      default: return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: compact ? 2 : 4),
    decoration: BoxDecoration(
      color: _color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon, size: compact ? 10 : 11, color: _color),
        const SizedBox(width: 4),
        Text(status.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(fontSize: compact ? 9 : 10, fontWeight: FontWeight.w800, color: _color, letterSpacing: 0.2)),
      ],
    ),
  );
}

/// Compact labeled field for the modernized collection/collector cards —
/// small caps label above a value line, used in place of stacked "Label: value" rows.
class _MiniField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool italic;
  const _MiniField(this.icon, this.label, this.value, {this.valueColor, this.italic = false});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 12, color: _kTextGray),
          const SizedBox(width: 4),
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: _kTextGray, letterSpacing: 0.3)),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: valueColor ?? _kTextDark,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    ],
  );
}

/// Small pill used for secondary metadata (distance, payment mode, etc.).
class _TagChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TagChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: _kTextGray),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10.5, color: _kTextGray, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _InfoChip extends StatelessWidget {
  final String value, label;
  const _InfoChip(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _kPrimary)),
    Text(label, style: const TextStyle(fontSize: 10, color: _kTextGray)),
  ]);
}

class _StatusSlice {
  final String label;
  final int count;
  final Color color;
  const _StatusSlice(this.label, this.count, this.color);
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kTextDark));
}

class _SectionTitle2 extends StatelessWidget {
  final String t;
  const _SectionTitle2(this.t);
  @override
  Widget build(BuildContext context) => Text(t,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _kTextDark));
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
            foregroundColor: color, side: BorderSide(color: color),
            padding: const EdgeInsets.symmetric(vertical: 12)),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ),
  );
}

class _NoBranchView extends StatelessWidget {
  const _NoBranchView();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(color: const Color(0xFFFFF3E0), shape: BoxShape.circle),
          child: const Icon(Icons.location_city_outlined, size: 40, color: _kOrange),
        ),
        const SizedBox(height: 20),
        const Text('No Branch Assigned', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: _kTextDark)),
        const SizedBox(height: 10),
        const Text(
          'Your account has not been assigned to a branch yet.\nPlease contact your administrator to get assigned.',
          style: TextStyle(color: _kTextGray, fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kOrange.withValues(alpha: 0.4)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, color: _kOrange, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text('Contact your super admin to be assigned to a branch.', style: TextStyle(color: _kOrange, fontSize: 13))),
          ]),
        ),
      ]),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, size: 64, color: _kRed),
      const SizedBox(height: 16),
      Text('Failed to load data', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 8),
      Text(error, style: const TextStyle(color: _kTextGray, fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: onRetry, style: ElevatedButton.styleFrom(backgroundColor: _kPrimary), child: const Text('Retry')),
    ]),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 64, color: const Color(0xFFDDDDDD)),
      const SizedBox(height: 16),
      Text(message, style: const TextStyle(color: _kTextGray, fontSize: 14)),
    ]),
  );
}

/// Standard numbered pagination footer — 20 items/page, matches the
/// backend's default `page_size`. Replaces "Load more" infinite-scroll
/// with an explicit Prev/Next control, the common admin-panel pattern.
class _PaginationBar extends StatelessWidget {
  final int page;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPageChange;
  const _PaginationBar({
    required this.page,
    required this.total,
    required this.onPageChange,
  }) : pageSize = 20;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final totalPages = ((total + pageSize - 1) ~/ pageSize).clamp(1, 999999);
    final startItem = (page - 1) * pageSize + 1;
    final endItem = (page * pageSize).clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing $startItem–$endItem of $total',
              style: const TextStyle(fontSize: 12, color: _kTextGray, fontWeight: FontWeight.w500),
            ),
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
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
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

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType type;
  final bool obscure;
  const _Field(this.controller, this.label, this.icon,
      {this.type = TextInputType.text}) : obscure = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: type,
    obscureText: obscure,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: _kTextGray),
      filled: true, fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEEEEEE))),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Super-Admin: Branch Management Tab
// ─────────────────────────────────────────────────────────────────────────────

class _BranchManagementTab extends StatefulWidget {
  const _BranchManagementTab();

  @override
  State<_BranchManagementTab> createState() => _BranchManagementTabState();
}

class _BranchManagementTabState extends State<_BranchManagementTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _branches = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      _branches = await provider.fetchBranches();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _kRed : _kPrimary,
    ));
  }

  // ── Set All Branches to Nationwide ──────────────────────────────────────────
  Future<void> _setAllNationwide() async {
    if (_branches.isEmpty) {
      _snack('No branches to update', error: true);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Set All to Nationwide?'),
        content: Text(
          'This will update all ${_branches.length} branch(es) to a 1000 km service radius, '
          'covering all of Ghana. Customers anywhere in the country can book pickups.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.updateAllBranchesRadius(1000);
      } else {
        await ApiService.patch(ApiConstants.superAdminBranchesBulkRadius, {'service_radius_km': 1000});
      }
      _snack('All branches updated to 1000 km (Nationwide)');
      _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } catch (_) {
      _snack('Failed to update branches', error: true);
    }
  }

  // ── Edit Branch ─────────────────────────────────────────────────────────────
  Future<void> _showEditBranchSheet(Map<String, dynamic> branch) async {
    double radius = (branch['service_radius_km'] as num?)?.toDouble() ?? 50.0;
    bool isActive = branch['is_active'] as bool? ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Edit: ${branch['name']}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextDark)),
                const SizedBox(height: 20),
                const Text('Service Coverage Radius',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kTextDark)),
                const SizedBox(height: 4),
                const Text('Customers must be within this distance of the branch centre to book',
                    style: TextStyle(color: _kTextGray, fontSize: 12)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    for (final opt in [
                      (km: 50.0, label: '50 km — City'),
                      (km: 150.0, label: '150 km — Region'),
                      (km: 300.0, label: '300 km — Wide'),
                      (km: 1000.0, label: '1000 km — Nationwide'),
                    ])
                      ChoiceChip(
                        label: Text(opt.label, style: const TextStyle(fontSize: 12)),
                        selected: radius == opt.km,
                        selectedColor: _kPrimary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: radius == opt.km ? _kPrimary : _kTextGray,
                          fontWeight: radius == opt.km ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => setSheet(() => radius = opt.km),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Selected: ${radius.toStringAsFixed(0)} km',
                    style: const TextStyle(color: _kTextGray, fontSize: 13)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Branch Active',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _kTextDark)),
                    Switch(
                      value: isActive,
                      activeThumbColor: _kPrimary,
                      onChanged: (v) => setSheet(() => isActive = v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        final provider = Provider.of<AppProvider>(context, listen: false);
                        await provider.updateBranch(branch['id'] as int, {
                          'service_radius_km': radius,
                          'is_active': isActive,
                        });
                        _snack('Branch updated');
                        _load();
                      } on ApiException catch (e) {
                        _snack(e.message, error: true);
                      } catch (_) {
                        _snack('Failed to update branch', error: true);
                      }
                    },
                    child: const Text('Save Changes',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Create Branch ───────────────────────────────────────────────────────────
  Future<void> _showCreateBranchSheet() async {
    final nameCtrl    = TextEditingController();
    final regionCtrl  = TextEditingController();
    final countryCtrl = TextEditingController(text: 'Ghana');
    final addressCtrl = TextEditingController();
    double? lat, lng;
    String locationLabel = 'Tap to pick on map';
    double serviceRadiusKm = 150.0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('New Branch',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextDark)),
                const SizedBox(height: 20),
                _SheetField(ctrl: nameCtrl,    label: 'Branch Name',  icon: Icons.business),
                const SizedBox(height: 12),
                _SheetField(ctrl: regionCtrl,  label: 'Region',       icon: Icons.map_outlined),
                const SizedBox(height: 12),
                _SheetField(ctrl: countryCtrl, label: 'Country',      icon: Icons.flag_outlined),
                const SizedBox(height: 12),
                _SheetField(ctrl: addressCtrl, label: 'Address (optional)', icon: Icons.location_on_outlined),
                const SizedBox(height: 16),
                // Map location picker — uses the tab's outer context so the
                // picker sheet opens above the create-branch sheet.
                GestureDetector(
                  onTap: () async {
                    final outerCtx = context; // capture before gap
                    final result = await showLocationPicker(outerCtx, allowAnyLocation: true);
                    if (result != null) {
                      setSheet(() {
                        lat = (result['lat'] as num).toDouble();
                        lng = (result['lng'] as num).toDouble();
                        locationLabel = result['address'] as String? ??
                            '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}';
                        if (addressCtrl.text.isEmpty && result['address'] != null) {
                          addressCtrl.text = result['address'] as String;
                        }
                      });
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: lat != null ? _kPrimary : const Color(0xFFE0E0E0)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.pin_drop_outlined,
                            color: lat != null ? _kPrimary : _kTextGray, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            locationLabel,
                            style: TextStyle(
                              color: lat != null ? _kTextDark : _kTextGray,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (lat != null)
                          const Icon(Icons.check_circle, color: _kPrimary, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Service Coverage Radius',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kTextDark)),
                const SizedBox(height: 4),
                const Text('Customers must be within this distance to book pickups',
                    style: TextStyle(color: _kTextGray, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    for (final opt in [
                      (km: 50.0, label: '50 km\nCity'),
                      (km: 150.0, label: '150 km\nRegion'),
                      (km: 300.0, label: '300 km\nWide'),
                      (km: 1000.0, label: '1000 km\nNationwide'),
                    ])
                      ChoiceChip(
                        label: Text(opt.label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                        selected: serviceRadiusKm == opt.km,
                        selectedColor: _kPrimary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: serviceRadiusKm == opt.km ? _kPrimary : _kTextGray,
                          fontWeight: serviceRadiusKm == opt.km ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => setSheet(() => serviceRadiusKm = opt.km),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        _snack('Branch name is required', error: true);
                        return;
                      }
                      if (regionCtrl.text.trim().isEmpty) {
                        _snack('Region is required', error: true);
                        return;
                      }
                      if (lat == null) {
                        _snack('Pick a location on the map', error: true);
                        return;
                      }
                      Navigator.pop(ctx);
                      try {
                        final provider = Provider.of<AppProvider>(context, listen: false);
                        await provider.createBranch(
                          name: nameCtrl.text.trim(),
                          region: regionCtrl.text.trim(),
                          country: countryCtrl.text.trim().isEmpty ? 'Ghana' : countryCtrl.text.trim(),
                          address: addressCtrl.text.trim(),
                          lat: lat!,
                          lng: lng!,
                          serviceRadiusKm: serviceRadiusKm,
                        );
                        _snack('Branch created');
                        _load();
                      } on ApiException catch (e) {
                        _snack(e.message, error: true);
                      } catch (e) {
                        _snack('Failed to create branch', error: true);
                      }
                    },
                    child: const Text('Create Branch',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    regionCtrl.dispose();
    countryCtrl.dispose();
    addressCtrl.dispose();
  }

  // ── Create Admin ────────────────────────────────────────────────────────────
  Future<void> _showCreateAdminSheet(int? preselectedBranchId) async {
    final firstCtrl = TextEditingController();
    final lastCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    int? selectedBranchId = preselectedBranchId;
    final isSA = Provider.of<AppProvider>(context, listen: false).isSuperAdmin;
    // Super admin default is 'admin'; regular admin default is 'staff'
    String selectedRole = isSA ? 'admin' : 'staff';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isSA ? 'Create Admin' : 'Create Staff',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextDark)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _SheetField(ctrl: firstCtrl, label: 'First Name', icon: Icons.person_outline)),
                    const SizedBox(width: 10),
                    Expanded(child: _SheetField(ctrl: lastCtrl,  label: 'Last Name',  icon: Icons.person_outline)),
                  ],
                ),
                const SizedBox(height: 12),
                _SheetField(ctrl: phoneCtrl, label: 'Phone', icon: Icons.phone_outlined, type: TextInputType.phone),
                const SizedBox(height: 12),
                _SheetField(ctrl: emailCtrl, label: 'Email (optional)', icon: Icons.email_outlined, type: TextInputType.emailAddress),
                const SizedBox(height: 16),
                // Role dropdown
                const Text('Role',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kTextDark)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedRole,
                      items: isSA
                          ? const [
                              DropdownMenuItem<String>(
                                value: 'admin',
                                child: Text('Admin'),
                              ),
                              DropdownMenuItem<String>(
                                value: 'super_admin',
                                child: Text('Super Admin'),
                              ),
                            ]
                          : const [
                              DropdownMenuItem<String>(
                                value: 'staff',
                                child: Text('Staff'),
                              ),
                              DropdownMenuItem<String>(
                                value: 'admin',
                                child: Text('Admin'),
                              ),
                            ],
                      onChanged: (v) => setSheet(
                          () => selectedRole = v ?? (isSA ? 'admin' : 'staff')),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Branch assignment dropdown
                const Text('Assign to Branch',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kTextDark)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      isExpanded: true,
                      value: selectedBranchId,
                      hint: const Text('No branch (assign later)', style: TextStyle(color: _kTextGray)),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('No branch (assign later)'),
                        ),
                        ..._branches.map((b) => DropdownMenuItem<int?>(
                          value: b['id'] as int,
                          child: Text('${b['name']} — ${b['region']}'),
                        )),
                      ],
                      onChanged: (v) => setSheet(() => selectedBranchId = v),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      if (firstCtrl.text.trim().isEmpty) { _snack('First name required', error: true); return; }
                      if (phoneCtrl.text.trim().isEmpty) { _snack('Phone required', error: true); return; }
                      Navigator.pop(ctx);
                      try {
                        final provider = Provider.of<AppProvider>(context, listen: false);
                        await provider.createAdminUser(
                          firstName: firstCtrl.text.trim(),
                          lastName:  lastCtrl.text.trim(),
                          phone:     phoneCtrl.text.trim(),
                          email:     emailCtrl.text.trim(),
                          branchId:  selectedBranchId,
                          role:      selectedRole,
                        );
                        _snack('Admin created');
                        _load();
                      } on ApiException catch (e) {
                        _snack(e.message, error: true);
                      } catch (e) {
                        _snack('Failed to create admin', error: true);
                      }
                    },
                    child: const Text('Create Admin',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    firstCtrl.dispose(); lastCtrl.dispose(); phoneCtrl.dispose();
    emailCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add_admin',
            onPressed: () => _showCreateAdminSheet(null),
            backgroundColor: _kBlue,
            icon: const Icon(Icons.person_add, color: Colors.white),
            label: const Text('Admin', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'add_branch',
            onPressed: _showCreateBranchSheet,
            backgroundColor: _kPrimary,
            icon: const Icon(Icons.add_location_alt, color: Colors.white),
            label: const Text('Branch', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _kPrimary,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: _kPrimary,
              title: const Text('Branch Management',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.public, color: Colors.white),
                  tooltip: 'Set all coverage to Nationwide (1000 km)',
                  onPressed: _setAllNationwide,
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_outlined, color: Colors.white),
                  tooltip: 'Create Admin',
                  onPressed: () => _showCreateAdminSheet(null),
                ),
              ],
            ),
            if (_loading)
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: _kPrimary)))
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: _kRed, size: 40),
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: _kRed)),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
            else if (_branches.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_city_outlined, size: 56, color: _kTextGray),
                      SizedBox(height: 12),
                      Text('No branches yet', style: TextStyle(color: _kTextGray, fontSize: 16)),
                      SizedBox(height: 6),
                      Text('Tap "Branch" below to create the first one',
                          style: TextStyle(color: _kTextGray, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _BranchCard(
                      branch: _branches[i],
                      onEdit: () => _showEditBranchSheet(_branches[i]),
                      onCreateAdmin: () => _showCreateAdminSheet(_branches[i]['id'] as int),
                      onDeleteAdmin: () async {
                        final branch = _branches[i];
                        final admin = branch['assigned_admin'] as Map<String, dynamic>?;
                        if (admin == null) return;
                        final adminId = admin['id'];
                        if (adminId == null) return;
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete Admin?'),
                            content: Text('Delete "${admin['name']}"? This cannot be undone.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: _kRed))),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        try {
                          if (SupabaseService.isLoggedIn) {
                            await SupabaseService.adminDeleteUser(adminId as String);
                          } else {
                            await ApiService.delete(ApiConstants.superAdminDeleteAdmin(adminId as int));
                          }
                          _snack('Admin deleted');
                          _load();
                        } catch (_) {
                          _snack('Failed to delete admin', error: true);
                        }
                      },
                      onDelete: () async {
                        final id = _branches[i]['id'] as int;
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete Branch?'),
                            content: Text(
                                'Delete "${_branches[i]['name']}"? Admins assigned to it will be unassigned.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete', style: TextStyle(color: _kRed))),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        try {
                          // ignore: use_build_context_synchronously
                          final provider = Provider.of<AppProvider>(context, listen: false);
                          await provider.deleteBranch(id);
                          _snack('Branch deleted');
                          _load();
                        } catch (_) {
                          _snack('Failed to delete branch', error: true);
                        }
                      },
                    ),
                    childCount: _branches.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.onEdit,
    required this.onCreateAdmin,
    required this.onDelete,
    this.onDeleteAdmin,
  });
  final Map<String, dynamic> branch;
  final VoidCallback onEdit;
  final VoidCallback onCreateAdmin;
  final VoidCallback onDelete;
  final VoidCallback? onDeleteAdmin;

  @override
  Widget build(BuildContext context) {
    final assignedAdmin = branch['assigned_admin'] as Map<String, dynamic>?;
    final adminCount    = branch['admin_count'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _kPrimary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.location_city, color: _kPrimary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(branch['name'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kTextDark)),
                      const SizedBox(height: 2),
                      Text('${branch['region']}, ${branch['country']}',
                          style: const TextStyle(color: _kTextGray, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: _kPrimary, size: 20),
                  tooltip: 'Edit branch',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: _kRed, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.pin_drop_outlined, size: 16, color: _kTextGray),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        branch['address'] != null && (branch['address'] as String).isNotEmpty
                            ? branch['address'] as String
                            : 'Lat ${(branch['lat'] as num?)?.toStringAsFixed(4)}, '
                              'Lng ${(branch['lng'] as num?)?.toStringAsFixed(4)}',
                        style: const TextStyle(color: _kTextGray, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.radio_button_checked, size: 16, color: _kTextGray),
                    const SizedBox(width: 6),
                    Text('Service radius: ${branch['service_radius_km']} km',
                        style: const TextStyle(color: _kTextGray, fontSize: 13)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: (branch['is_active'] as bool? ?? true)
                            ? _kAccent.withValues(alpha: 0.15)
                            : _kRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        (branch['is_active'] as bool? ?? true) ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: (branch['is_active'] as bool? ?? true) ? _kAccent : _kRed,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Admin section
                Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined, size: 16, color: _kTextGray),
                    const SizedBox(width: 6),
                    Expanded(
                      child: assignedAdmin != null
                          ? Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(assignedAdmin['name'] as String? ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kTextDark)),
                                      Text(assignedAdmin['phone'] as String? ?? '',
                                          style: const TextStyle(color: _kTextGray, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                if (onDeleteAdmin != null)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: _kRed, size: 18),
                                    tooltip: 'Delete admin',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: onDeleteAdmin,
                                  ),
                              ],
                            )
                          : const Text('No admin assigned',
                              style: TextStyle(color: _kTextGray, fontSize: 13)),
                    ),
                    TextButton.icon(
                      onPressed: onCreateAdmin,
                      icon: Icon(
                        adminCount > 0 ? Icons.person_add_outlined : Icons.person_add,
                        size: 16,
                        color: _kPrimary,
                      ),
                      label: Text(
                        adminCount > 0 ? 'Add Admin' : 'Assign Admin',
                        style: const TextStyle(color: _kPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.ctrl,
    required this.label,
    required this.icon,
    this.type = TextInputType.text,
  });
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType type;

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: type,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: _kTextGray),
      filled: true, fillColor: const Color(0xFFF5F5F5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Company Waste Bins Page
// ─────────────────────────────────────────────────────────────────────────────

class _CompanyBinsPage extends StatefulWidget {
  const _CompanyBinsPage();
  @override
  State<_CompanyBinsPage> createState() => _CompanyBinsPageState();
}

class _CompanyBinsPageState extends State<_CompanyBinsPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _bins = [];
  List<Map<String, dynamic>> _collectors = [];
  String _statusFilter = ''; // '' = all, 'true' = active, 'false' = inactive

  @override
  void initState() {
    super.initState();
    _load();
    _loadCollectors();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<dynamic> results;
      if (SupabaseService.isLoggedIn) {
        results = await SupabaseService.fetchCompanyBins(
          isActive: _statusFilter.isEmpty ? null : _statusFilter == 'true',
        );
      } else {
        var url = ApiConstants.adminCompanyBins;
        if (_statusFilter.isNotEmpty) url += '?is_active=$_statusFilter';
        final res = await ApiService.get(url);
        results = (res['results'] as List?) ?? [];
      }
      setState(() => _bins = results.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setStatusFilter(String s) {
    setState(() => _statusFilter = s);
    _load();
  }

  Future<void> _loadCollectors() async {
    try {
      final List<dynamic> results;
      if (SupabaseService.isLoggedIn) {
        results = await SupabaseService.fetchAdminCollectors();
      } else {
        final res = await ApiService.get('${ApiConstants.adminCollectors}?page_size=200');
        results = (res['results'] as List?) ?? [];
      }
      setState(() => _collectors = results.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Future<void> _delete(int id) async {
    try {
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.deleteCompanyBin(id);
      } else {
        await ApiService.delete(ApiConstants.adminCompanyBin(id));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _showForm({Map<String, dynamic>? bin}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _CompanyBinFormPage(bin: bin, collectors: _collectors),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Company Waste Bins', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
      actions: [
        IconButton(
          icon: const Icon(Icons.add, color: _kPrimary),
          onPressed: () => _showForm(),
        ),
      ],
    ),
    body: Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              _PeriodChip(label: 'All', selected: _statusFilter == '', onTap: () => _setStatusFilter('')),
              _PeriodChip(label: 'Active', selected: _statusFilter == 'true', onTap: () => _setStatusFilter('true')),
              _PeriodChip(label: 'Inactive', selected: _statusFilter == 'false', onTap: () => _setStatusFilter('false')),
            ],
          ),
        ),
        Expanded(
          child: _loading && _bins.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _kPrimary,
                  child: _bins.isEmpty
                      ? const _EmptyState(icon: Icons.delete_outline, message: 'No company bins yet.\nTap + to add one.')
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _bins.length,
                    itemBuilder: (_, i) {
                      final b = _bins[i];
                      final isActive = b['is_active'] as bool? ?? true;
                      final collector = b['assigned_collector_name'] as String?;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: _kCard,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))],
                          border: Border.all(color: isActive ? _kPrimary.withValues(alpha: 0.15) : const Color(0xFFDDDDDD)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: (isActive ? _kPrimary : _kTextGray).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.delete_outline,
                                color: isActive ? _kPrimary : _kTextGray, size: 22),
                          ),
                          title: Text('${b['name']} — ${b['size']}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(b['location'] as String? ?? '',
                                  style: const TextStyle(fontSize: 12, color: _kTextGray)),
                              if (collector != null)
                                Text('Collector: $collector',
                                    style: const TextStyle(fontSize: 11, color: _kBlue, fontWeight: FontWeight.w500)),
                              Text('${money(b['monthly_subscription'], prefix: 'GH₵')}/mo',
                                  style: const TextStyle(fontSize: 12, color: _kPrimary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _showForm(bin: b);
                              if (v == 'delete') _confirmDelete(b['id'] as int, b['name'] as String);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: _kRed))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );

  void _confirmDelete(int id, String name) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete Bin'),
      content: Text('Delete "$name"? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(context); _delete(id); },
            child: const Text('Delete', style: TextStyle(color: _kRed))),
      ],
    ),
  );
}

// ── Bin create / edit form ────────────────────────────────────────────────────

class _CompanyBinFormPage extends StatefulWidget {
  final Map<String, dynamic>? bin;
  final List<Map<String, dynamic>> collectors;
  const _CompanyBinFormPage({this.bin, required this.collectors});
  @override
  State<_CompanyBinFormPage> createState() => _CompanyBinFormPageState();
}

class _CompanyBinFormPageState extends State<_CompanyBinFormPage> {
  final _name = TextEditingController();
  final _size = TextEditingController();
  final _location = TextEditingController();
  final _subscription = TextEditingController();
  final _notes = TextEditingController();
  double? _lat;
  double? _lng;
  dynamic _collectorId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bin;
    if (b != null) {
      _name.text = b['name'] as String? ?? '';
      _size.text = b['size'] as String? ?? '';
      _location.text = b['location'] as String? ?? '';
      _subscription.text = b['monthly_subscription'] as String? ?? '';
      _notes.text = b['notes'] as String? ?? '';
      _lat = (b['lat'] as num?)?.toDouble();
      _lng = (b['lng'] as num?)?.toDouble();
      _collectorId = b['assigned_collector_id'];
    }
  }

  @override
  void dispose() {
    _name.dispose(); _size.dispose(); _location.dispose();
    _subscription.dispose(); _notes.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await showLocationPicker(context, allowAnyLocation: true);
    if (result != null && mounted) {
      setState(() {
        _location.text = result['address'] as String? ?? _location.text;
        _lat = (result['lat'] as num?)?.toDouble();
        _lng = (result['lng'] as num?)?.toDouble();
      });
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _size.text.trim().isEmpty || _location.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name, size and location are required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'name': _name.text.trim(),
        'size': _size.text.trim(),
        'location': _location.text.trim(),
        'monthly_subscription': _subscription.text.trim().isEmpty ? '0' : _subscription.text.trim(),
        'notes': _notes.text.trim(),
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
        'assigned_collector_id': _collectorId,
      };
      final binId = widget.bin?['id'] as int?;
      if (SupabaseService.isLoggedIn) {
        await SupabaseService.saveCompanyBin(binId, payload);
      } else if (binId != null) {
        await ApiService.put(ApiConstants.adminCompanyBin(binId), payload);
      } else {
        await ApiService.post(ApiConstants.adminCompanyBins, payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType? type}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.bin != null;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(isEdit ? 'Edit Waste Bin' : 'New Waste Bin',
            style: const TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('Bin Name', _name),
          _field('Size (e.g. 120L, Large)', _size),
          Row(children: [
            Expanded(child: _field('Location / Address', _location)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.my_location, color: _kPrimary),
              tooltip: 'Pick GPS location',
              onPressed: _pickLocation,
            ),
          ]),
          if (_lat != null && _lng != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text('GPS: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11, color: _kTextGray)),
            ),
          _field('Monthly Subscription (GHS)', _subscription,
              type: const TextInputType.numberWithOptions(decimal: true)),
          _field('Notes (optional)', _notes),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Assign Collector (optional)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: InputDecorator(
              decoration: InputDecoration(
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<dynamic>(
                  value: widget.collectors.any((c) => c['user_id'] == _collectorId)
                      ? _collectorId
                      : null,
                  isExpanded: true,
                  hint: const Text('No collector assigned'),
                  items: [
                    const DropdownMenuItem<dynamic>(value: null, child: Text('None')),
                    ...widget.collectors.map((c) => DropdownMenuItem<dynamic>(
                      value: c['user_id'],
                      child: Text(c['name'] as String? ?? ''),
                    )),
                  ],
                  onChanged: (v) => setState(() => _collectorId = v),
                ),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(isEdit ? 'Save Changes' : 'Create Bin',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waste Types Page
// ─────────────────────────────────────────────────────────────────────────────
class _WasteTypesPage extends StatefulWidget {
  const _WasteTypesPage();
  @override
  State<_WasteTypesPage> createState() => _WasteTypesPageState();
}

class _WasteTypesPageState extends State<_WasteTypesPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (SupabaseService.isLoggedIn) {
        _items = await SupabaseService.fetchAllWasteTypesAdmin();
      } else {
        final res = await ApiService.get('${ApiConstants.adminWasteTypes}?page_size=100');
        final list = (res['data'] as List?) ?? (res['results'] as List?) ?? [];
        _items = list.cast<Map<String, dynamic>>();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openSheet({Map<String, dynamic>? item}) {
    final isEdit = item != null;
    final labelCtrl = TextEditingController(text: item?['label'] as String? ?? '');
    final keyCtrl = TextEditingController(text: item?['key'] as String? ?? '');
    final priceCtrl = TextEditingController(text: item?['base_price']?.toString() ?? '');
    bool isActive = item?['is_active'] as bool? ?? true;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Edit Waste Type' : 'New Waste Type',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _kTextDark)),
              const SizedBox(height: 16),
              _sheetField('Label', labelCtrl),
              if (!isEdit) _sheetField('Key (snake_case)', keyCtrl, hint: 'e.g. general_waste'),
              _sheetField('Base Price (GHS)', priceCtrl,
                  type: const TextInputType.numberWithOptions(decimal: true)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Switch(
                    value: isActive,
                    activeThumbColor: _kPrimary,
                    onChanged: (v) => setSheet(() => isActive = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: saving ? null : () async {
                    if (labelCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty ||
                        (!isEdit && keyCtrl.text.trim().isEmpty)) {
                      _snack('Fill in all required fields');
                      return;
                    }
                    setSheet(() => saving = true);
                    try {
                      if (SupabaseService.isLoggedIn) {
                        await SupabaseService.adminSaveWasteType(
                          id: isEdit ? item['id'] as int : null,
                          label: labelCtrl.text.trim(),
                          key: isEdit ? null : keyCtrl.text.trim(),
                          basePrice: priceCtrl.text.trim(),
                          isActive: isActive,
                        );
                      } else {
                        final payload = <String, dynamic>{
                          'label': labelCtrl.text.trim(),
                          'base_price': priceCtrl.text.trim(),
                          'is_active': isActive,
                          if (!isEdit) 'key': keyCtrl.text.trim(),
                        };
                        if (isEdit) {
                          await ApiService.patch(ApiConstants.adminWasteType(item['id'] as int), payload);
                        } else {
                          await ApiService.post(ApiConstants.adminWasteTypes, payload);
                        }
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    } catch (e) {
                      _snack('$e');
                    } finally {
                      setSheet(() => saving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(isEdit ? 'Save Changes' : 'Create',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetField(String label, TextEditingController ctrl,
      {TextInputType? type, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          keyboardType: type,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            filled: true, fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Waste Types', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _openSheet(),
      backgroundColor: _kPrimary,
      child: const Icon(Icons.add, color: Colors.white),
    ),
    body: _loading && _items.isEmpty
        ? const Center(child: CircularProgressIndicator(color: _kPrimary))
        : _items.isEmpty
            ? const _EmptyState(icon: Icons.category_outlined, message: 'No waste types')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final w = _items[i];
                    final active = w['is_active'] as bool? ?? true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: active
                                ? _kPrimary.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.category_outlined,
                              color: active ? _kPrimary : _kTextGray, size: 20),
                        ),
                        title: Text(w['label'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Text(
                          '${money(w['base_price'], prefix: 'GHS')}  •  ${active ? 'Active' : 'Inactive'}',
                          style: TextStyle(fontSize: 12, color: active ? _kAccent : _kTextGray),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined, color: _kPrimary, size: 20),
                          onPressed: () => _openSheet(item: w),
                        ),
                      ),
                    );
                  },
                ),
              ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bin Types Page
// ─────────────────────────────────────────────────────────────────────────────
class _BinTypesPage extends StatefulWidget {
  const _BinTypesPage();
  @override
  State<_BinTypesPage> createState() => _BinTypesPageState();
}

class _BinTypesPageState extends State<_BinTypesPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _wasteTypes = [];
  String? _filterWasteType;

  @override
  void initState() { super.initState(); _loadAll(); }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      if (SupabaseService.isLoggedIn) {
        final results = await Future.wait([
          SupabaseService.fetchAllBinTypesAdmin(),
          SupabaseService.fetchAllWasteTypesAdmin(),
        ]);
        _items = results[0];
        _wasteTypes = results[1];
      } else {
        final results = await Future.wait([
          ApiService.get('${ApiConstants.adminBinTypes}?page_size=100'),
          ApiService.get('${ApiConstants.adminWasteTypes}?page_size=100'),
        ]);
        final r0 = results[0]; final r1 = results[1];
        final list0 = (r0['data'] as List?) ?? (r0['results'] as List?) ?? [];
        final list1 = (r1['data'] as List?) ?? (r1['results'] as List?) ?? [];
        _items = list0.cast<Map<String, dynamic>>();
        _wasteTypes = list1.cast<Map<String, dynamic>>();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadBinTypes() async {
    try {
      if (SupabaseService.isLoggedIn) {
        int? wasteTypeId;
        if (_filterWasteType != null) {
          final wt = _wasteTypes.firstWhere(
            (w) => w['key'] == _filterWasteType,
            orElse: () => const {},
          );
          wasteTypeId = wt['id'] as int?;
        }
        _items = await SupabaseService.fetchAllBinTypesAdmin(wasteTypeId: wasteTypeId);
      } else {
        final url = _filterWasteType != null
            ? '${ApiConstants.adminBinTypes}?waste_type=$_filterWasteType&page_size=100'
            : '${ApiConstants.adminBinTypes}?page_size=100';
        final res = await ApiService.get(url);
        final list = (res['data'] as List?) ?? (res['results'] as List?) ?? [];
        _items = list.cast<Map<String, dynamic>>();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openSheet({Map<String, dynamic>? item}) {
    final isEdit = item != null;
    final displayNameCtrl = TextEditingController(text: item?['display_name'] as String? ?? '');
    final sizeLabelCtrl = TextEditingController(text: item?['size_label'] as String? ?? '');
    final priceCtrl = TextEditingController(text: item?['price']?.toString() ?? '');
    bool isActive = item?['is_active'] as bool? ?? true;
    bool saving = false;
    int? selectedWasteTypeId;
    if (isEdit) {
      final wtRaw = item['waste_type'];
      if (wtRaw is int) {
        selectedWasteTypeId = wtRaw;
      } else if (wtRaw is Map) {
        selectedWasteTypeId = wtRaw['id'] as int?;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Edit Bin Type' : 'New Bin Type',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _kTextDark)),
              const SizedBox(height: 16),
              _sheetField('Display Name', displayNameCtrl),
              _sheetField('Size Label', sizeLabelCtrl, hint: 'e.g. 120L'),
              _sheetField('Price (GHS)', priceCtrl,
                  type: const TextInputType.numberWithOptions(decimal: true)),
              if (!isEdit) ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('Waste Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      filled: true, fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: selectedWasteTypeId,
                        isExpanded: true,
                        hint: const Text('Select waste type', style: TextStyle(color: _kTextGray)),
                        items: _wasteTypes.map((wt) => DropdownMenuItem<int?>(
                          value: wt['id'] as int?,
                          child: Text(wt['label'] as String? ?? ''),
                        )).toList(),
                        onChanged: (v) => setSheet(() => selectedWasteTypeId = v),
                      ),
                    ),
                  ),
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Switch(
                    value: isActive,
                    activeThumbColor: _kPrimary,
                    onChanged: (v) => setSheet(() => isActive = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: saving ? null : () async {
                    if (displayNameCtrl.text.trim().isEmpty ||
                        sizeLabelCtrl.text.trim().isEmpty ||
                        priceCtrl.text.trim().isEmpty ||
                        (!isEdit && selectedWasteTypeId == null)) {
                      _snack('Fill in all required fields');
                      return;
                    }
                    setSheet(() => saving = true);
                    try {
                      if (SupabaseService.isLoggedIn) {
                        await SupabaseService.adminSaveBinType(
                          id: isEdit ? item['id'] as int : null,
                          displayName: displayNameCtrl.text.trim(),
                          sizeLabel: sizeLabelCtrl.text.trim(),
                          price: priceCtrl.text.trim(),
                          wasteTypeId: selectedWasteTypeId,
                          isActive: isActive,
                        );
                      } else if (isEdit) {
                        await ApiService.patch(ApiConstants.adminBinType(item['id'] as int), {
                          'display_name': displayNameCtrl.text.trim(),
                          'size_label': sizeLabelCtrl.text.trim(),
                          'price': priceCtrl.text.trim(),
                          'is_active': isActive,
                        });
                      } else {
                        await ApiService.post(ApiConstants.adminBinTypes, {
                          'display_name': displayNameCtrl.text.trim(),
                          'size_label': sizeLabelCtrl.text.trim(),
                          'price': priceCtrl.text.trim(),
                          'waste_type_id': selectedWasteTypeId,
                          'is_active': isActive,
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _loadBinTypes();
                      _snack(isEdit
                          ? 'Bin type updated successfully.'
                          : 'Bin type created successfully.');
                    } catch (e) {
                      _snack('$e');
                    } finally {
                      setSheet(() => saving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(isEdit ? 'Save Changes' : 'Create',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetField(String label, TextEditingController ctrl,
      {TextInputType? type, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          keyboardType: type,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            filled: true, fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: Colors.white, elevation: 0,
      title: const Text('Bin Types', style: TextStyle(color: _kTextDark, fontWeight: FontWeight.w800)),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _openSheet(),
      backgroundColor: _kPrimary,
      child: const Icon(Icons.add, color: Colors.white),
    ),
    body: _loading && _items.isEmpty
        ? const Center(child: CircularProgressIndicator(color: _kPrimary))
        : Column(
            children: [
              if (_wasteTypes.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text('All'),
                          selected: _filterWasteType == null,
                          selectedColor: _kPrimary.withValues(alpha: 0.15),
                          checkmarkColor: _kPrimary,
                          onSelected: (_) {
                            setState(() => _filterWasteType = null);
                            _loadBinTypes();
                          },
                        ),
                      ),
                      ..._wasteTypes.map((wt) {
                        final key = wt['key'] as String? ?? '';
                        final lbl = wt['label'] as String? ?? key;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(lbl),
                            selected: _filterWasteType == key,
                            selectedColor: _kPrimary.withValues(alpha: 0.15),
                            checkmarkColor: _kPrimary,
                            onSelected: (_) {
                              setState(() => _filterWasteType = key);
                              _loadBinTypes();
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              Expanded(
                child: _items.isEmpty
                    ? const _EmptyState(icon: Icons.inventory_2_outlined, message: 'No bin types')
                    : RefreshIndicator(
                        onRefresh: _loadAll,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final bt = _items[i];
                            final active = bt['is_active'] as bool? ?? true;
                            final wtLabel = () {
                              final key = bt['waste_type_key'];
                              final match = _wasteTypes.where((w) => w['key'] == key).toList();
                              return match.isNotEmpty
                                  ? match.first['label'] as String? ?? ''
                                  : (key as String? ?? '');
                            }();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? _kPrimary.withValues(alpha: 0.1)
                                        : Colors.grey.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.inventory_2_outlined,
                                      color: active ? _kPrimary : _kTextGray, size: 20),
                                ),
                                title: Text(
                                  '${bt['display_name'] ?? ''} — ${bt['size_label'] ?? ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                subtitle: Text(
                                  '${money(bt['price'], prefix: 'GHS')}  •  $wtLabel  •  ${active ? 'Active' : 'Inactive'}',
                                  style: TextStyle(fontSize: 12, color: active ? _kAccent : _kTextGray),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: _kPrimary, size: 20),
                                  onPressed: () => _openSheet(item: bt),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
  );
}

// ── Investors List Page ────────────────────────────────────────────────────────
class _InvestorsListPage extends StatefulWidget {
  const _InvestorsListPage();
  @override
  State<_InvestorsListPage> createState() => _InvestorsListPageState();
}

class _InvestorsListPageState extends State<_InvestorsListPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _investors = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (SupabaseService.isLoggedIn) {
        final list = await SupabaseService.fetchAdminInvestorsList();
        if (mounted) setState(() => _investors = list);
      } else {
        final res = await ApiService.get('${ApiConstants.adminInvestors}?page_size=100');
        if (mounted) {
          setState(() => _investors = (res['results'] as List? ?? []).cast<Map<String, dynamic>>());
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(dynamic val, {String prefix = ''}) {
    if (val == null) return '—';
    final n = num.tryParse('$val');
    if (n != null) return '$prefix${n.toStringAsFixed(2)}';
    return '$val';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: const Text('Investors', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading && _investors.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _investors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart_outlined, size: 64, color: _kTextGray.withValues(alpha: .4)),
                      const SizedBox(height: 12),
                      const Text('No investors yet', style: TextStyle(color: _kTextGray, fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _kPrimary,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _investors.length,
                    itemBuilder: (_, i) {
                      final inv = _investors[i];
                      final user = inv['user'] as Map<String, dynamic>? ?? {};
                      final name = (user['name'] as String?) ?? (inv['name'] as String?) ?? '—';
                      final phone = (user['phone'] as String?) ?? (inv['phone'] as String?) ?? '—';
                      final amount = _fmt(inv['investment_amount'], prefix: 'GHS ');
                      final totalEarnings = _fmt(inv['total_earnings'], prefix: 'GHS ');
                      final roi = _fmt(inv['roi_actual'], prefix: '');
                      final isActive = inv['is_active'] as bool? ?? true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _kCard,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: _kPrimary.withValues(alpha: .12),
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : 'I',
                                    style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w700, fontSize: 18),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _kTextDark)),
                                      Text(phone, style: const TextStyle(color: _kTextGray, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive ? _kPrimary.withValues(alpha: .1) : _kRed.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(color: isActive ? _kPrimary : _kRed, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Divider(height: 1),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                _statCell('Amount Invested', amount),
                                const SizedBox(width: 16),
                                _statCell('Total Earnings', totalEarnings, color: _kAccent),
                                const SizedBox(width: 16),
                                _statCell('ROI', roi.isEmpty ? '—' : '$roi%', color: _kAccent),
                              ],
                            ),
                            if ((inv['contract_reference'] as String?) != null) ...[
                              const SizedBox(height: 10),
                              Text('Contract: ${inv['contract_reference']}',
                                  style: const TextStyle(fontSize: 11, color: _kTextGray)),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _statCell(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _kTextGray, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color ?? _kTextDark)),
        ],
      ),
    );
  }
}
