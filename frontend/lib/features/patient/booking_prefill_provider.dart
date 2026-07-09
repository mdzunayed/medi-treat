import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/service_catalog_item.dart';

/// Holds a catalog item selected from the service detail screen so that
/// [NewRequestTab] can prefill its form on the next build. Cleared by the
/// consumer once read.
final servicePrefillProvider = StateProvider<ServiceCatalogItem?>((_) => null);
