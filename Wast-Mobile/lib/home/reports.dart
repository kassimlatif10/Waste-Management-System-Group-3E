import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

const Color _kBg = Color(0xFFF0F7F0);
const Color _kPrimary = Color(0xFF2E7D32);
const Color _kCard = Colors.white;
const Color _kTextDark = Color(0xFF1A1A1A);
const Color _kTextGray = Color(0xFF757575);

class DumpingReportsPage extends StatefulWidget {
  const DumpingReportsPage({super.key});

  @override
  State<DumpingReportsPage> createState() => _DumpingReportsPageState();
}

class _DumpingReportsPageState extends State<DumpingReportsPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AppProvider>().fetchDumpingReports();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final reports = provider.dumpingReports;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Dumping Reports',
          style: TextStyle(
            color: _kTextDark,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _kPrimary),
            )
          : reports.isEmpty
              ? const Center(
                  child: Text(
                    'No reports submitted yet',
                    style: TextStyle(color: _kTextGray, fontSize: 15),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final item = reports[index];
                    final status = item['status']?.toString() ?? 'Pending';
                    final isInvestigated =
                        status.toLowerCase() == 'investigated';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['location']?.toString() ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _kTextDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item['description']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _kTextGray, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item['date']?.toString() ?? '',
                                style: const TextStyle(
                                    color: _kTextGray, fontSize: 12),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isInvestigated
                                      ? _kPrimary.withValues(alpha: 0.12)
                                      : Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isInvestigated
                                        ? _kPrimary
                                        : Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
