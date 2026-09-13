import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../utils/parse_utils.dart';
import 'location_picker.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kLightGreen = Color(0xFFE8F5E9);
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

// ── Frequency options ──────────────────────────────────────────────────────────
// Must match scheduled_pickups.frequency's backend check constraint exactly
// (supabase/migrations/0001_init.sql): 'weekly' | 'biweekly' | 'monthly'.
const _kFrequencies = [
  {'key': 'weekly',   'label': 'Weekly',        'icon': Icons.view_week},
  {'key': 'biweekly', 'label': 'Every 2 Weeks', 'icon': Icons.date_range},
  {'key': 'monthly',  'label': 'Monthly',       'icon': Icons.calendar_month},
];

// ── Payment period options ─────────────────────────────────────────────────────
const _kPaymentPeriods = [
  {'key': 'per_pickup', 'label': 'Pay Per Pickup',   'sub': 'Charged after each collection'},
  {'key': 'weekly',     'label': 'Weekly Payment',   'sub': 'One payment covers the week'},
  {'key': 'monthly',    'label': 'Monthly Payment',  'sub': 'One payment covers the month'},
];

class SchedulePickupPage extends StatefulWidget {
  const SchedulePickupPage({super.key});

  @override
  State<SchedulePickupPage> createState() => _SchedulePickupPageState();
}

class _SchedulePickupPageState extends State<SchedulePickupPage> {
  final PageController _pageCtrl = PageController();
  int _step = 0;

  // Step 0 — Waste type
  Map<String, dynamic>? _wasteType;

  // Step 1 — Bin type
  Map<String, dynamic>? _binType;

  // Step 2 — Location
  String _pickupAddress = '';
  double? _pickupLat;
  double? _pickupLng;

  // Step 3 — Date & Time
  String? _selectedDate;
  String _selectedTime = '09:00';

  // Step 4 — Recurring
  bool _isRecurring = false;
  String _frequency = 'weekly';
  String _paymentPeriod = 'per_pickup';

  bool _submitting = false;

  static const int _totalSteps = 5;

  static const List<String> _times = [
    '06:00', '07:00', '08:00', '09:00', '10:00', '11:00',
    '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00',
  ];

  static const List<String> _dayAbbr = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  List<Map<String, String>> _generateDates() {
    final now = DateTime.now();
    return List.generate(30, (i) {
      final d = now.add(Duration(days: i));
      final abbr = _dayAbbr[d.weekday - 1];
      final dateStr =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return {'dayName': abbr, 'dayNum': '${d.day}', 'dateStr': dateStr};
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().fetchWasteTypes();
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_step < _totalSteps - 1) {
      _pageCtrl.animateToPage(
        _step + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _goBack() {
    if (_step > 0) {
      _pageCtrl.animateToPage(
        _step - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _step--);
    } else {
      Navigator.pop(context);
    }
  }

  bool get _canProceed {
    switch (_step) {
      case 0: return _wasteType != null;
      case 1: return _binType != null;
      case 2: return _pickupAddress.isNotEmpty && _pickupLat != null;
      case 3: return _selectedDate != null;
      case 4: return true;
      default: return false;
    }
  }

  String _dayOfWeekFromDate(String dateStr) {
    final d = DateTime.parse(dateStr);
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    return days[d.weekday - 1];
  }

  String get _nextLabel {
    if (_step == _totalSteps - 1) return 'Schedule Pickup';
    if (_step == 2) return 'Confirm Location';
    return 'Next';
  }

  Future<void> _submit() async {
    if (_submitting || _wasteType == null || _selectedDate == null) return;
    setState(() => _submitting = true);
    try {
      final provider = context.read<AppProvider>();
      await provider.addSchedule({
        'waste_type': _wasteType!['name'],
        'bin_type_id': _binType?['id'],
        'pickup_address': _pickupAddress,
        'pickup_lat': _pickupLat,
        'pickup_lng': _pickupLng,
        'frequency': _frequency,
        'day_of_week': _dayOfWeekFromDate(_selectedDate!),
        'pickup_time': '$_selectedTime:00',
      });
      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                  color: _kLightGreen, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline,
                  color: _kPrimary, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scheduled!',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _kTextDark),
            ),
            const SizedBox(height: 8),
            Text(
              'Your ${_wasteType?['label'] ?? 'pickup'} has been scheduled.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextGray, fontSize: 14),
            ),
            if (_isRecurring) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _kLightGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Repeats ${_frequencyLabel(_frequency)}',
                  style: const TextStyle(
                      color: _kPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _frequencyLabel(String key) {
    for (final f in _kFrequencies) {
      if (f['key'] == key) return f['label'] as String;
    }
    return key;
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
          onPressed: _goBack,
        ),
        title: const Text(
          'Schedule Pickup',
          style: TextStyle(
              color: _kTextDark,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _StepProgress(step: _step, total: _totalSteps),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _WasteTypeStep(
                  selected: _wasteType,
                  onSelect: (w) => setState(() {
                    _wasteType = w;
                    _binType = null;
                  }),
                ),
                _BinTypeStep(
                  wasteType: _wasteType,
                  selected: _binType,
                  onSelect: (b) => setState(() => _binType = b),
                ),
                _LocationStep(
                  address: _pickupAddress,
                  onPick: (addr, lat, lng) => setState(() {
                    _pickupAddress = addr;
                    _pickupLat = lat;
                    _pickupLng = lng;
                  }),
                ),
                _DateTimeStep(
                  selectedDate: _selectedDate,
                  selectedTime: _selectedTime,
                  dates: _generateDates(),
                  times: _times,
                  onDateSelect: (d) => setState(() => _selectedDate = d),
                  onTimeSelect: (t) => setState(() => _selectedTime = t),
                ),
                _RecurringStep(
                  isRecurring: _isRecurring,
                  frequency: _frequency,
                  paymentPeriod: _paymentPeriod,
                  wasteType: _wasteType,
                  binType: _binType,
                  selectedDate: _selectedDate,
                  selectedTime: _selectedTime,
                  onRecurringToggle: (v) =>
                      setState(() => _isRecurring = v),
                  onFrequencySelect: (f) =>
                      setState(() => _frequency = f),
                  onPaymentPeriodSelect: (p) =>
                      setState(() => _paymentPeriod = p),
                ),
              ],
            ),
          ),

          // Bottom CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: (_canProceed && !_submitting) ? _goNext : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  disabledBackgroundColor:
                      const Color(0xFFBDBDBD),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        _nextLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step progress bar ──────────────────────────────────────────────────────────
class _StepProgress extends StatelessWidget {
  final int step;
  final int total;
  const _StepProgress({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: List.generate(total, (i) {
          final active = i == step;
          final done = i < step;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 4,
                decoration: BoxDecoration(
                  color: done || active
                      ? _kPrimary
                      : const Color(0xFFBDBDBD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Step 0: Waste Type ─────────────────────────────────────────────────────────
class _WasteTypeStep extends StatelessWidget {
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;
  const _WasteTypeStep({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final wasteTypes = context.watch<AppProvider>().wasteTypes;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What type of waste?',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _kTextDark),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select the waste category for this pickup.',
            style: TextStyle(color: _kTextGray, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ...wasteTypes.map((w) {
            final isSelected = selected?['name'] == w['name'];
            final color = w['color'] as Color? ?? _kTextGray;
            final icon = w['icon'] as IconData? ?? Icons.delete_outline;
            return GestureDetector(
              onTap: () => onSelect(w),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.08)
                      : _kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? color : const Color(0xFFE0E0E0),
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: [
                    if (!isSelected)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            w['label'] as String? ?? '',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color:
                                    isSelected ? color : _kTextDark),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            w['sub'] as String? ?? '',
                            style: const TextStyle(
                                color: _kTextGray, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle,
                          color: color, size: 22),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Step 1: Bin Type ───────────────────────────────────────────────────────────
class _BinTypeStep extends StatelessWidget {
  final Map<String, dynamic>? wasteType;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;
  const _BinTypeStep({
    required this.wasteType,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final bins = (wasteType?['bin_types'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose bin size',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _kTextDark),
          ),
          const SizedBox(height: 6),
          Text(
            'Bin size determines the price for ${wasteType?['label'] ?? 'this waste type'}.',
            style: const TextStyle(color: _kTextGray, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (bins.isEmpty)
            const Center(
              child: Text('No bin types available.',
                  style: TextStyle(color: _kTextGray)),
            )
          else
            ...bins.map((b) {
              final isSelected = selected?['name'] == b['name'];
              final price = (b['price'] as num?) ?? 0;
              return GestureDetector(
                onTap: () => onSelect(b),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? _kLightGreen : _kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? _kPrimary
                          : const Color(0xFFE0E0E0),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      if (!isSelected)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _kPrimary.withValues(alpha: 0.12)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.delete_outline,
                          color: isSelected ? _kPrimary : _kTextGray,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b['display_name'] as String? ??
                                  b['name'] as String? ??
                                  '',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isSelected
                                      ? _kPrimary
                                      : _kTextDark),
                            ),
                            if ((b['description'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              Text(
                                b['description'] as String,
                                style: const TextStyle(
                                    color: _kTextGray, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _kPrimary
                              : const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          money(price, prefix: 'GH₵'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isSelected
                                ? Colors.white
                                : _kTextDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Step 2: Pickup Location ───────────────────────────────────────────────────
class _LocationStep extends StatefulWidget {
  final String address;
  final void Function(String addr, double lat, double lng) onPick;
  const _LocationStep({required this.address, required this.onPick});

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  bool _picking = false;

  Future<void> _openPicker() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await showLocationPicker(context, allowAnyLocation: true);
      if (result != null && mounted) {
        widget.onPick(
          result['address'] as String? ?? '',
          (result['lat'] as num).toDouble(),
          (result['lng'] as num).toDouble(),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAddress = widget.address.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pickup Location',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: _kTextDark),
          ),
          const SizedBox(height: 6),
          const Text(
            'Where should we collect your waste?',
            style: TextStyle(color: _kTextGray, fontSize: 13),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _openPicker,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hasAddress
                    ? _kPrimary.withValues(alpha: 0.06)
                    : _kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasAddress ? _kPrimary : const Color(0xFFBDBDBD),
                  width: hasAddress ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      hasAddress ? Icons.location_on : Icons.location_on_outlined,
                      color: _kPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      hasAddress ? widget.address : 'Tap to choose a location',
                      style: TextStyle(
                        color: hasAddress ? _kTextDark : _kTextGray,
                        fontWeight:
                            hasAddress ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (_picking)
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kPrimary),
                    )
                  else
                    Icon(
                      Icons.chevron_right,
                      color: hasAddress ? _kPrimary : _kTextGray,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _optionTile(
                  Icons.gps_fixed,
                  'Use GPS',
                  'Your current location',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _optionTile(
                  Icons.map_outlined,
                  'Pin on Map',
                  'Tap the map to choose',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optionTile(IconData icon, String title, String sub) {
    return GestureDetector(
      onTap: _openPicker,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _kPrimary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _kTextDark)),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 11, color: _kTextGray)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 3: Date & Time ────────────────────────────────────────────────────────
class _DateTimeStep extends StatelessWidget {
  final String? selectedDate;
  final String selectedTime;
  final List<Map<String, String>> dates;
  final List<String> times;
  final ValueChanged<String> onDateSelect;
  final ValueChanged<String> onTimeSelect;

  const _DateTimeStep({
    required this.selectedDate,
    required this.selectedTime,
    required this.dates,
    required this.times,
    required this.onDateSelect,
    required this.onTimeSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'When should we collect?',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _kTextDark),
          ),
          const SizedBox(height: 20),

          // Date picker
          const Text(
            'Select Date',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _kTextDark),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 78,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: dates.length,
              itemBuilder: (_, i) {
                final d = dates[i];
                final isSelected = selectedDate == d['dateStr'];
                return GestureDetector(
                  onTap: () => onDateSelect(d['dateStr']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 60,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? _kLightGreen : _kCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? _kPrimary
                            : const Color(0xFFBDBDBD),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          d['dayName']!,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? _kPrimary
                                  : _kTextGray),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d['dayNum']!,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? _kPrimary
                                  : _kTextDark),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Time picker
          const Text(
            'Preferred Time',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _kTextDark),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: times.map((t) {
              final isSelected = selectedTime == t;
              return GestureDetector(
                onTap: () => onTimeSelect(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? _kPrimary : _kCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? _kPrimary
                          : const Color(0xFFBDBDBD),
                    ),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(
                      color: isSelected ? Colors.white : _kTextGray,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Recurring Options ──────────────────────────────────────────────────
class _RecurringStep extends StatelessWidget {
  final bool isRecurring;
  final String frequency;
  final String paymentPeriod;
  final Map<String, dynamic>? wasteType;
  final Map<String, dynamic>? binType;
  final String? selectedDate;
  final String selectedTime;
  final ValueChanged<bool> onRecurringToggle;
  final ValueChanged<String> onFrequencySelect;
  final ValueChanged<String> onPaymentPeriodSelect;

  const _RecurringStep({
    required this.isRecurring,
    required this.frequency,
    required this.paymentPeriod,
    required this.wasteType,
    required this.binType,
    required this.selectedDate,
    required this.selectedTime,
    required this.onRecurringToggle,
    required this.onFrequencySelect,
    required this.onPaymentPeriodSelect,
  });

  @override
  Widget build(BuildContext context) {
    final price = (binType?['price'] as num?) ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pickup schedule',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _kTextDark),
          ),
          const SizedBox(height: 6),
          const Text(
            'Set as one-time or choose a recurring frequency.',
            style: TextStyle(color: _kTextGray, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // One-time vs Recurring toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8F5E9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isRecurring
                        ? _kLightGreen
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.refresh,
                    color: isRecurring ? _kPrimary : _kTextGray,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recurring Pickup',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _kTextDark,
                            fontSize: 15),
                      ),
                      Text(
                        'Automatically repeat on a schedule',
                        style:
                            TextStyle(color: _kTextGray, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isRecurring,
                  onChanged: onRecurringToggle,
                  activeThumbColor: _kPrimary,
                  activeTrackColor: _kLightGreen,
                ),
              ],
            ),
          ),

          // Frequency options (only when recurring)
          if (isRecurring) ...[
            const SizedBox(height: 20),
            const Text(
              'How often?',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _kTextDark),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _kFrequencies.map((f) {
                final isSel = frequency == f['key'];
                return GestureDetector(
                  onTap: () =>
                      onFrequencySelect(f['key'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSel ? _kLightGreen : _kCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSel
                            ? _kPrimary
                            : const Color(0xFFBDBDBD),
                        width: isSel ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          f['icon'] as IconData,
                          size: 16,
                          color: isSel ? _kPrimary : _kTextGray,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          f['label'] as String,
                          style: TextStyle(
                            color: isSel ? _kPrimary : _kTextGray,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),
            const Text(
              'Payment preference',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _kTextDark),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose how you\'d like to pay for recurring pickups.',
              style: TextStyle(color: _kTextGray, fontSize: 12),
            ),
            const SizedBox(height: 10),
            ..._kPaymentPeriods.map((p) {
              final isSel = paymentPeriod == p['key'];
              return GestureDetector(
                onTap: () =>
                    onPaymentPeriodSelect(p['key'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSel ? _kLightGreen : _kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSel
                          ? _kPrimary
                          : const Color(0xFFE0E0E0),
                      width: isSel ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSel
                                ? _kPrimary
                                : const Color(0xFFBDBDBD),
                            width: 2,
                          ),
                          color: isSel
                              ? _kPrimary
                              : Colors.transparent,
                        ),
                        child: isSel
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 12)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              p['label'] as String,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isSel
                                      ? _kPrimary
                                      : _kTextDark),
                            ),
                            Text(
                              p['sub'] as String,
                              style: const TextStyle(
                                  color: _kTextGray, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Payment alert info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.alarm, color: Color(0xFFF57C00), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You\'ll receive an alarm reminder before each payment is due to keep your schedule active.',
                      style: TextStyle(
                          color: Color(0xFF6D4C00),
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Summary card
          _SummaryCard(
            wasteType: wasteType,
            binType: binType,
            date: selectedDate,
            time: selectedTime,
            isRecurring: isRecurring,
            frequency: frequency,
            price: price,
          ),
        ],
      ),
    );
  }
}

// ── Summary card shown on final step ──────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic>? wasteType;
  final Map<String, dynamic>? binType;
  final String? date;
  final String time;
  final bool isRecurring;
  final String frequency;
  final num price;

  const _SummaryCard({
    required this.wasteType,
    required this.binType,
    required this.date,
    required this.time,
    required this.isRecurring,
    required this.frequency,
    required this.price,
  });

  String _formatDate(String? d) {
    if (d == null || d.isEmpty) return '—';
    try {
      final dt = DateTime.parse(d);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return d;
    }
  }

  String _freqLabel(String key) {
    for (final f in _kFrequencies) {
      if (f['key'] == key) return f['label'] as String;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8F5E9)),
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
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  color: _kPrimary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Schedule Summary',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kTextDark),
              ),
              const Spacer(),
              Text(
                money(price, prefix: 'GH₵'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _kPrimary),
              ),
            ],
          ),
          const Divider(height: 20),
          _SummaryRow(
            Icons.delete_outline,
            'Waste',
            wasteType?['label'] as String? ?? '—',
          ),
          if (binType != null)
            _SummaryRow(
              Icons.inventory_2_outlined,
              'Bin',
              binType?['display_name'] as String? ??
                  binType?['name'] as String? ??
                  '—',
            ),
          _SummaryRow(
            Icons.calendar_today_outlined,
            'Date',
            _formatDate(date),
          ),
          _SummaryRow(
            Icons.access_time_outlined,
            'Time',
            time,
          ),
          _SummaryRow(
            Icons.refresh,
            'Frequency',
            isRecurring ? _freqLabel(frequency) : 'One-time',
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: _kPrimary),
          const SizedBox(width: 8),
          Text('$label: ',
              style:
                  const TextStyle(color: _kTextGray, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  color: _kTextDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
