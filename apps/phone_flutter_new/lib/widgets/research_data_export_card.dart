import 'package:flutter/material.dart';

import '../services/export/research_data_export_service.dart';
import 'section_card.dart';

class ResearchDataExportCard extends StatefulWidget {
  const ResearchDataExportCard({super.key});

  @override
  State<ResearchDataExportCard> createState() => _ResearchDataExportCardState();
}

class _ResearchDataExportCardState extends State<ResearchDataExportCard> {
  final ResearchDataExportService _exportService = ResearchDataExportService();

  bool _exporting = false;
  String? _status;

  Future<void> _export(BuildContext context) async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _status = 'Preparing export...';
    });

    try {
      final result = await _exportService.createExport(
        onProgress: (message) {
          if (!mounted) return;
          setState(() => _status = message);
        },
      );

      if (!context.mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      try {
        await _exportService.shareExport(
          result,
          sharePositionOrigin: renderBox == null
              ? null
              : renderBox.localToGlobal(Offset.zero) & renderBox.size,
        );
      } finally {
        await _exportService.deleteTemporaryExport(result);
      }

      if (!mounted) return;
      setState(() => _status = 'Export shared. Keep the saved ZIP protected.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Export created: ${result.counts['sensor_samples'] ?? 0} sensor '
            'samples, ${result.counts['ema_events'] ?? 0} EMA events, '
            '${result.counts['sleep_sessions'] ?? 0} sleep sessions.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Research export failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _status = 'Export failed.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not create the export. Check your connection and try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Your Research Data',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create a ZIP copy of the research data stored for your signed-in account. Keep exported files protected because they may contain sensitive study information.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _exporting ? null : () => _export(context),
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
              label: Text(_exporting ? 'Preparing export...' : 'Export research data'),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(
              _status!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              'What is included?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            children: [
              Text(
                'The ZIP contains lossless Firestore NDJSON and analysis-ready CSV files for sensor batches, craving check-ins, baseline context, sleep records, and model records. Raw PPG is included only if that capability is enabled in a future build. Authentication passwords are never exported.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
