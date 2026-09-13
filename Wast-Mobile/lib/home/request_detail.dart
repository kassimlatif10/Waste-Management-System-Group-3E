import 'package:flutter/material.dart';

import '../utils/parse_utils.dart';

class RequestDetailScreen extends StatelessWidget {
  final Map<String, dynamic> request;

  const RequestDetailScreen({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    final rawStatus = request['status'].toString();
    final trackingLabel = bookingStatusLabel(rawStatus);
    final trackingColor = bookingStatusColor(rawStatus);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
        title: const Text("Details", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoSection("Request Status", [
            _buildInfoRow("Booking Status", trackingLabel, isStatus: true, color: trackingColor),
            _buildInfoRow("Detail", rawStatus.toUpperCase()),
            _buildInfoRow("Request ID", '${request['id']}'),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection("Pickup Information", [
            _buildInfoRow("Waste Type", request['wasteType']),
            _buildInfoRow("Address", request['address']),
            _buildInfoRow("Total Cost", money(request['cost'], prefix: "GH₵")),
          ]),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[100]!),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isStatus ? color : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}