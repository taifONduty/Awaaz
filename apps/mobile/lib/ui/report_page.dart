import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'components.dart';
import 'journey_view_model.dart';
import 'theme.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.vm, required this.onSaved});
  final JourneyViewModel vm;
  final VoidCallback onSaved;
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _form = GlobalKey<FormState>();
  final _place = TextEditingController();
  final _description = TextEditingController();
  ReportCategory _category = ReportCategory.obstruction;
  bool _consent = false;
  @override
  void dispose() {
    _place.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_consent || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final l = AppLocalizations.of(context);
    final saved = await widget.vm.saveDraft(
      _category,
      _place.text,
      _description.text,
    );
    if (!mounted || !saved) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.savedDraft)));
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(title: l.reportTitle, subtitle: l.reportSubtitle),
          InfoCard(
            title: l.reportPrivacyTitle,
            body: l.reportPrivacyCaption,
            icon: Icons.lock_outline,
            color: AwaazColors.tint,
          ),
          const SizedBox(height: 22),
          SectionLabel(l.reportBasics),
          const SizedBox(height: 14),
          DropdownButtonFormField<ReportCategory>(
            initialValue: _category,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.category),
            items: [
              for (final category in ReportCategory.values)
                DropdownMenuItem(
                  value: category,
                  child: Text(categoryLabel(l, category)),
                ),
            ],
            onChanged: widget.vm.saving
                ? null
                : (value) => setState(() => _category = value!),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('report-place'),
            controller: _place,
            maxLength: 100,
            decoration: InputDecoration(labelText: l.place),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? l.validation : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('report-description'),
            controller: _description,
            minLines: 4,
            maxLines: 7,
            maxLength: 700,
            decoration: InputDecoration(labelText: l.description),
            validator: (value) =>
                (value?.trim().length ?? 0) < 10 ? l.validation : null,
          ),
          const SizedBox(height: 12),
          Text(l.privacyCopy),
          const SizedBox(height: 12),
          CheckboxListTile(
            key: const Key('draft-consent'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            title: Text(l.privacyConsent),
            onChanged: widget.vm.saving
                ? null
                : (value) => setState(() => _consent = value!),
          ),
          const SizedBox(height: 20),
          ActionButton(
            key: const Key('save-draft'),
            label: l.saveDraft,
            onPressed: !_consent || widget.vm.saving ? null : _save,
          ),
          if (widget.vm.saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
