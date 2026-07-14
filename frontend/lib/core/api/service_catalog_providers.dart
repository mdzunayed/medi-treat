import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/service_catalog_item.dart';
import 'service_catalog_repository.dart';

/// Base URL of the backend. Reads the same `API_BASE_URL` dart-define as
/// [DioClient], so one flag configures the whole app:
///   local:             (default) http://localhost:5000
///   Android emulator:  --dart-define=API_BASE_URL=http://10.0.2.2:5000
///   deployed (Render): --dart-define=API_BASE_URL=https://medi-treat-backend-api.onrender.com
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:5000',
);

final serviceCatalogDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: kApiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  return dio;
});

final serviceCatalogRepositoryProvider = Provider<ServiceCatalogRepository>((ref) {
  final repo = ServiceCatalogRepository(ref.watch(serviceCatalogDioProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final allServicesProvider = StreamProvider<List<ServiceCatalogItem>>((ref) {
  return ref.watch(serviceCatalogRepositoryProvider).watchAll();
});

final activeServicesProvider = StreamProvider<List<ServiceCatalogItem>>((ref) {
  return ref.watch(serviceCatalogRepositoryProvider).watchActive();
});
