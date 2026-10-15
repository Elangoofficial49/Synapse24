import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8002/api/v1';
  late final Dio dio;

  ApiService() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  // Authentication
  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    final data = response.data;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', data['access_token']);
    await prefs.setString('current_user', jsonEncode(data['user']));
    return data;
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> details) async {
    final response = await dio.post('/auth/register', data: details);
    return Map<String, dynamic>.from(response.data);
  }

  Future<List<dynamic>> getPendingUsers() async {
    final response = await dio.get('/auth/pending-users');
    return response.data;
  }

  Future<void> approveUser(String userId) async {
    await dio.post('/auth/users/$userId/approve');
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('current_user');
    if (value == null) return null;
    return Map<String, dynamic>.from(jsonDecode(value));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('current_user');
  }

  // Verification
  Future<Map<String, dynamic>> verifyPackage(String rawData) async {
    final response = await dio.post('/verify', data: {'raw_data': rawData});
    return response.data;
  }

  // Products & Batches
  Future<List<dynamic>> getProducts() async {
    final response = await dio.get('/products');
    return response.data;
  }

  Future<List<dynamic>> getBatches() async {
    final response = await dio.get('/batches');
    return response.data;
  }

  Future<Map<String, dynamic>> createProduct(
      Map<String, dynamic> product) async {
    final response = await dio.post('/products', data: product);
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> createBatch(Map<String, dynamic> batch) async {
    final response = await dio.post('/batches', data: batch);
    return Map<String, dynamic>.from(response.data);
  }

  Future<List<dynamic>> generatePackages(String batchId, int count) async {
    final response = await dio.post(
      '/batches/$batchId/generate-packages',
      data: {'batch_id': batchId, 'count': count},
    );
    return response.data;
  }

  // Shipments & Two-Party Custody
  Future<List<dynamic>> getShipments() async {
    final response = await dio.get('/shipments');
    return response.data;
  }

  Future<Map<String, dynamic>> receiveShipment(
      String shipmentId, int actualQuantity, String? notes) async {
    final response = await dio.post('/shipments/$shipmentId/receive', data: {
      'actual_quantity_received': actualQuantity,
      'notes': notes,
    });
    return response.data;
  }

  // Disputes & Alerts
  Future<List<dynamic>> getDisputes() async {
    final response = await dio.get('/disputes');
    return response.data;
  }

  Future<List<dynamic>> getAlerts() async {
    final response = await dio.get('/alerts');
    return response.data;
  }

  // Analytics
  Future<Map<String, dynamic>> getDashboardMetrics() async {
    final response = await dio.get('/analytics/dashboard');
    return response.data;
  }
}

final apiService = ApiService();
