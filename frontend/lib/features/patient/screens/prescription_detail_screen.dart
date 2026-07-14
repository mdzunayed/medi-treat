import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/models/prescription.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_button.dart';
import '../../../core/widgets/mt_error_state.dart';
import '../../prescriptions/prescriptions_provider.dart';

const List<DoseSlot> _slotOrder = [
  DoseSlot.morning,
  DoseSlot.afternoon,
  DoseSlot.night,
];

String _freqLabel(PrescriptionItem it) {
  final parts = [
    for (final s in _slotOrder)
      if (it.frequency.contains(s)) s.labelEn,
  ];
  return parts.isEmpty ? '—' : parts.join(', ');
}

/// Typeset digital prescription card. Renders the issuing doctor's verified
/// credentials, diagnosis + symptoms, and an itemized Rx table. Offers a PDF
/// export (print/share) and a high-contrast "Pharmacy Scan View".
class PrescriptionDetailScreen extends ConsumerStatefulWidget {
  final String prescriptionId;
  const PrescriptionDetailScreen({super.key, required this.prescriptionId});

  @override
  ConsumerState<PrescriptionDetailScreen> createState() =>
      _PrescriptionDetailScreenState();
}

class _PrescriptionDetailScreenState
    extends ConsumerState<PrescriptionDetailScreen> {
  bool _scanView = false;
  bool _generatingPdf = false;

  Future<void> _downloadPdf(Prescription p) async {
    if (_generatingPdf) return;
    HapticFeedback.lightImpact();
    setState(() => _generatingPdf = true);
    try {
      await Printing.layoutPdf(
        name: 'prescription_${p.id}.pdf',
        onLayout: (format) => _buildPdf(p, format),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MtColors.rejected,
          content: Text("Couldn't generate the PDF: $e"),
        ),
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(prescriptionDetailProvider(widget.prescriptionId));

    return Scaffold(
      backgroundColor: _scanView ? Colors.white : MtColors.bg,
      appBar: AppBar(
        backgroundColor: _scanView ? Colors.white : MtColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(_scanView ? 'Pharmacy Scan View' : 'Prescription',
            style: MtTextStyles.h3.copyWith(
                color: _scanView ? Colors.black : MtColors.ink)),
        actions: [
          async.maybeWhen(
            data: (p) => IconButton(
              tooltip: _scanView ? 'Exit scan view' : 'Pharmacy scan view',
              icon: Icon(
                _scanView ? Icons.close_fullscreen : Icons.zoom_out_map,
                color: _scanView ? Colors.black : MtColors.ink2,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() => _scanView = !_scanView);
              },
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: MtColors.brand)),
        error: (e, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MtErrorState(
            title: "Couldn't load prescription",
            message: e.toString(),
            onRetry: () => ref.invalidate(
                prescriptionDetailProvider(widget.prescriptionId)),
          ),
        ),
        data: (p) => _scanView ? _ScanView(script: p) : _buildDetail(p),
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (p) => _scanView
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: MtButton(
                        label: 'Scan View',
                        isOutlined: true,
                        leadingIcon: Icons.zoom_out_map,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() => _scanView = true);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MtButton(
                        label: 'Download PDF',
                        leadingIcon: Icons.picture_as_pdf_outlined,
                        isLoading: _generatingPdf,
                        onPressed: () => _downloadPdf(p),
                      ),
                    ),
                  ],
                ),
              ),
        orElse: () => null,
      ),
    );
  }

  Widget _buildDetail(Prescription p) {
    final date = DateFormat('d MMMM y').format(p.issuedAt);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _CredentialsHeader(script: p),
        const SizedBox(height: 16),
        _Section(
          title: 'Diagnosis',
          icon: Icons.coronavirus_outlined,
          child: Text(
            p.diagnosis.isEmpty ? 'Not recorded' : p.diagnosis,
            style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
          ),
        ),
        if (p.symptoms.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _Section(
            title: 'Reported symptoms',
            icon: Icons.sick_outlined,
            child: Text(
              p.symptoms,
              style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Section(
          title: 'Medications (Rx)',
          icon: Icons.medication_outlined,
          child: Column(
            children: [
              for (var i = 0; i < p.items.length; i++) ...[
                if (i > 0) const Divider(height: 18, color: MtColors.line),
                _RxRow(item: p.items[i]),
              ],
              if (p.items.isEmpty)
                Text('No medications listed.',
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Issued $date',
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
      ],
    );
  }

  // ── PDF document ───────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdf(Prescription p, PdfPageFormat format) async {
    final doc = pw.Document();
    final date = DateFormat('d MMMM y').format(p.issuedAt);
    final teal = PdfColor.fromInt(0xFF0D9488);
    final ink = PdfColor.fromInt(0xFF111827);
    final ink3 = PdfColor.fromInt(0xFF6B7280);

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text('$k: $v',
              style: pw.TextStyle(fontSize: 10, color: ink3)),
        );

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: teal, width: 2)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        p.doctorName.isEmpty
                            ? 'Attending Physician'
                            : p.doctorName,
                        style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: ink),
                      ),
                      if (p.doctorSpecialization.isNotEmpty)
                        pw.Text(p.doctorSpecialization,
                            style: pw.TextStyle(fontSize: 10, color: ink3)),
                      if (p.doctorBmdc.isNotEmpty)
                        pw.Text('BMDC Reg: ${p.doctorBmdc}',
                            style: pw.TextStyle(fontSize: 10, color: ink3)),
                      if (p.doctorVerified)
                        pw.Text('BMDC Verified',
                            style: pw.TextStyle(fontSize: 9, color: teal)),
                    ],
                  ),
                  pw.Text('Taafi',
                      style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: teal)),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            kv('Diagnosis', p.diagnosis.isEmpty ? 'Not recorded' : p.diagnosis),
            if (p.symptoms.trim().isNotEmpty) kv('Symptoms', p.symptoms),
            kv('Issued', date),
            pw.SizedBox(height: 14),
            pw.Text('Rx',
                style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: teal)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColor.fromInt(0xFFD1D5DB), width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(3),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration:
                      pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F4F6)),
                  children: [
                    _pdfCell('Drug', bold: true),
                    _pdfCell('Dosage', bold: true),
                    _pdfCell('Frequency', bold: true),
                    _pdfCell('Meal', bold: true),
                    _pdfCell('Duration', bold: true),
                  ],
                ),
                for (final it in p.items)
                  pw.TableRow(children: [
                    _pdfCell(it.drugName),
                    _pdfCell(it.dosage),
                    _pdfCell(_freqLabel(it)),
                    _pdfCell(it.mealContext.labelEn),
                    _pdfCell('${it.durationDays} days'),
                  ]),
              ],
            ),
            pw.Spacer(),
            pw.SizedBox(height: 30),
            pw.Container(
              width: 200,
              padding: const pw.EdgeInsets.only(top: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: ink3)),
              ),
              child: pw.Text(
                p.doctorName.isEmpty
                    ? 'Authorised digital signature'
                    : '${p.doctorName} · Digital signature',
                style: pw.TextStyle(
                    fontSize: 9,
                    color: ink3,
                    fontStyle: pw.FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(
          text.isEmpty ? '—' : text,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      );
}

// ─── Credentials header ──────────────────────────────────────────────────────

class _CredentialsHeader extends StatelessWidget {
  final Prescription script;
  const _CredentialsHeader({required this.script});

  static const _teal = Color(0xFF0D9488);
  static const _tealSoft = Color(0xFFCCFBF1);

  @override
  Widget build(BuildContext context) {
    final verified = script.doctorVerified;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _tealSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_hospital_outlined,
                    color: _teal, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      script.doctorName.isEmpty
                          ? 'Attending physician'
                          : script.doctorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.h3.copyWith(color: MtColors.ink),
                    ),
                    if (script.doctorSpecialization.isNotEmpty)
                      Text(script.doctorSpecialization,
                          style: MtTextStyles.bodySm
                              .copyWith(color: MtColors.ink2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (script.doctorBmdc.isNotEmpty) ...[
                const Icon(Icons.badge_outlined, size: 15, color: MtColors.ink3),
                const SizedBox(width: 4),
                Text('BMDC: ${script.doctorBmdc}',
                    style:
                        MtTextStyles.labelMd.copyWith(color: MtColors.ink2)),
                const SizedBox(width: 12),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: verified ? _tealSoft : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      verified
                          ? Icons.verified_rounded
                          : Icons.pending_outlined,
                      size: 13,
                      color: verified ? _teal : const Color(0xFFB45309),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      verified ? 'BMDC Verified' : 'Verification pending',
                      style: MtTextStyles.labelSm.copyWith(
                        color: verified ? _teal : const Color(0xFFB45309),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: MtColors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MtColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  script.doctorName.isEmpty
                      ? 'Authorised physician'
                      : script.doctorName,
                  style: MtTextStyles.labelLg.copyWith(
                    color: MtColors.ink,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Digital signature',
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section + Rx row ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Section({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: MtColors.brand),
              const SizedBox(width: 6),
              Text(title.toUpperCase(),
                  style: MtTextStyles.labelSm.copyWith(
                      color: MtColors.ink3, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _RxRow extends StatelessWidget {
  final PrescriptionItem item;
  const _RxRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(item.drugName,
                  style: MtTextStyles.labelLg.copyWith(
                      color: MtColors.ink, fontWeight: FontWeight.w800)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: MtColors.brandSofter,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(item.dosage,
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.brand)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _meta(Icons.schedule, _freqLabel(item)),
            _meta(Icons.restaurant_outlined, item.mealContext.labelEn),
            _meta(Icons.event_outlined, '${item.durationDays} days'),
          ],
        ),
        if (item.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(item.notes,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        ],
      ],
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: MtColors.ink3),
        const SizedBox(width: 4),
        Text(text, style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2)),
      ],
    );
  }
}

// ─── Pharmacy scan view (high-contrast, large text) ──────────────────────────

class _ScanView extends StatelessWidget {
  final Prescription script;
  const _ScanView({required this.script});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            script.doctorName.isEmpty ? 'Prescription' : script.doctorName,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black),
          ),
          if (script.doctorBmdc.isNotEmpty)
            Text('BMDC: ${script.doctorBmdc}',
                style: const TextStyle(fontSize: 18, color: Colors.black87)),
          const Divider(height: 28, thickness: 2, color: Colors.black),
          if (script.diagnosis.isNotEmpty) ...[
            const Text('Diagnosis',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54)),
            Text(script.diagnosis,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black)),
            const SizedBox(height: 20),
          ],
          const Text('Medications',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54)),
          const SizedBox(height: 8),
          for (final it in script.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${it.drugName}  —  ${it.dosage}',
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.black)),
                  const SizedBox(height: 2),
                  Text(
                    '${_freqLabel(it)} · ${it.mealContext.labelEn} · ${it.durationDays} days',
                    style: const TextStyle(
                        fontSize: 20, color: Colors.black87),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
