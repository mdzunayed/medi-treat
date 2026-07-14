import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/service_catalog_providers.dart';
import '../new_request/new_request_notifier.dart';
import 'patient_nav_provider.dart';

/// Dispatches a server-driven `navigationRoute` string (from a dynamic home
/// section item) onto the patient shell.
///
/// Supported route strings:
///   • `home` / `new_request` / `account`      — tab switch
///   • `activities`                            — Activities, default sub-tab
///   • `activities:under_review|tracking|history|medications`
///   • `service:<serviceId>`                   — prefill the booking form with
///     that catalog service and jump to New Request (same flow as tapping a
///     service card)
///   • `http://…` / `https://…`                — external browser
///
/// Anything else (including null) is a silent no-op so newer backends can
/// ship routes this app version doesn't know yet. [args] is the item's
/// `routeArguments` map — reserved for future route types.
void dispatchDynamicRoute(
  WidgetRef ref,
  String? route, {
  Map<String, String> args = const {},
}) {
  final value = route?.trim();
  if (value == null || value.isEmpty) return;

  if (value.startsWith('http://') || value.startsWith('https://')) {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  if (value.startsWith('service:')) {
    final serviceId = value.substring('service:'.length).trim();
    final services = ref.read(activeServicesProvider).valueOrNull;
    final match = services?.where((s) => s.id == serviceId).toList();
    if (match == null || match.isEmpty) {
      // Catalog not loaded or the service is gone — land on the booking
      // form unprefilled rather than dead-ending the tap.
      ref.goToNewRequest();
      return;
    }
    ref.read(newRequestProvider.notifier).applyServicePrefill(match.first);
    ref.goToNewRequest();
    return;
  }

  switch (value) {
    case 'home':
      ref.goToHome();
      return;
    case 'new_request':
      ref.goToNewRequest();
      return;
    case 'account':
      ref.goToAccount();
      return;
    case 'activities':
      ref.goToActivities();
      return;
    case 'activities:under_review':
      ref.goToActivities(sub: PatientActivitiesTab.underReview);
      return;
    case 'activities:tracking':
      ref.goToActivities(sub: PatientActivitiesTab.tracking);
      return;
    case 'activities:history':
      ref.goToActivities(sub: PatientActivitiesTab.history);
      return;
    case 'activities:medications':
      ref.goToActivities(sub: PatientActivitiesTab.medications);
      return;
    default:
      debugPrint('dispatchDynamicRoute: unknown route "$value" — ignored');
  }
}
