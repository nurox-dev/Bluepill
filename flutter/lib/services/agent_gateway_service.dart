import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'supabase_service.dart';

class AgentGatewayService {
  AgentGatewayService({SupabaseClient? client, http.Client? httpClient})
    : _client = client ?? SupabaseService.client,
      _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;

  Future<Map<String, dynamic>> createAgentRun({
    required String message,
    Object? conversationId,
    List<Map<String, dynamic>> attachments = const [],
    String? idempotencyKey,
  }) async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Sign in again before messaging Agent.');
    }

    final response = await _http
        .post(
          _workerUri('/agent/chat'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'message': message,
            if (conversationId != null) 'conversation_id': conversationId,
            if (attachments.isNotEmpty) 'attachments': attachments,
            if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
          }),
        )
        .timeout(const Duration(seconds: 90));

    final data = _decodeJsonResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data['detail'] ?? data['error'] ?? response.body;
      throw StateError(detail.toString());
    }
    return data;
  }

  Future<Map<String, dynamic>> getAgentRun(Object runId) async {
    final data = await _client
        .from('agent_runs')
        .select('id, status, result, error, conversation_id, updated_at')
        .eq('id', runId)
        .single();
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> createScheduledJob({
    required String jobType,
    required DateTime scheduledFor,
    Map<String, dynamic> payload = const {},
    String? idempotencyKey,
  }) async {
    final response = await _client.functions.invoke(
      'schedule-job',
      body: {
        'job_type': jobType,
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        'payload': payload,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      },
    );
    return _mapResponse(response.data);
  }

  Future<List<Map<String, dynamic>>> listCronJobs() async {
    final response = await _http.get(
      _workerUri('/cron/jobs'),
      headers: _workerHeaders(),
    );
    final data = _decodeJsonResponse(response.body);
    _throwForWorkerError(response, data);
    final jobs = data['jobs'];
    if (jobs is List) {
      return jobs.map((job) => Map<String, dynamic>.from(job as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> createCronJob({
    required String name,
    required String schedule,
    required String task,
    Map<String, dynamic> payload = const {},
    bool enabled = true,
    String timezone = 'UTC',
    int maxRetries = 0,
    int timeoutSeconds = 300,
    int retryDelaySeconds = 30,
    String? idempotencyKey,
  }) async {
    final response = await _http.post(
      _workerUri('/cron/jobs'),
      headers: _workerHeaders(),
      body: jsonEncode({
        'name': name,
        'schedule': schedule,
        'task': task,
        'payload': payload,
        'enabled': enabled,
        'timezone': timezone,
        'max_retries': maxRetries,
        'timeout_seconds': timeoutSeconds,
        'retry_delay_seconds': retryDelaySeconds,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      }),
    );
    final data = _decodeJsonResponse(response.body);
    _throwForWorkerError(response, data);
    return Map<String, dynamic>.from(data['job'] as Map);
  }

  Future<Map<String, dynamic>> updateCronJob(
    Object jobId, {
    String? name,
    String? schedule,
    String? task,
    Map<String, dynamic>? payload,
    bool? enabled,
    String? timezone,
    int? maxRetries,
    int? timeoutSeconds,
    int? retryDelaySeconds,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (schedule != null) 'schedule': schedule,
      if (task != null) 'task': task,
      if (payload != null) 'payload': payload,
      if (enabled != null) 'enabled': enabled,
      if (timezone != null) 'timezone': timezone,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (timeoutSeconds != null) 'timeout_seconds': timeoutSeconds,
      if (retryDelaySeconds != null) 'retry_delay_seconds': retryDelaySeconds,
    };
    final response = await _http.patch(
      _workerUri('/cron/jobs/$jobId'),
      headers: _workerHeaders(),
      body: jsonEncode(body),
    );
    final data = _decodeJsonResponse(response.body);
    _throwForWorkerError(response, data);
    return Map<String, dynamic>.from(data['job'] as Map);
  }

  Future<List<Map<String, dynamic>>> listCronJobExecutions(
    Object jobId, {
    int limit = 50,
  }) async {
    final response = await _http.get(
      _workerUri('/cron/jobs/$jobId/executions?limit=$limit'),
      headers: _workerHeaders(),
    );
    final data = _decodeJsonResponse(response.body);
    _throwForWorkerError(response, data);
    final executions = data['executions'];
    if (executions is List) {
      return executions
          .map((execution) => Map<String, dynamic>.from(execution as Map))
          .toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> decideApproval({
    required Object approvalId,
    required bool approved,
    Map<String, dynamic> decisionPayload = const {},
  }) async {
    final response = await _client.functions.invoke(
      'approve-action',
      body: {
        'approval_id': approvalId,
        'decision': approved ? 'approved' : 'rejected',
        'decision_payload': decisionPayload,
      },
    );
    return _mapResponse(response.data);
  }

  Map<String, dynamic> _mapResponse(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'data': data};
  }

  Uri _workerUri(String path) {
    final baseUrl = AppConfig.fastApiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw StateError('FASTAPI_BASE_URL is not configured.');
    }
    return Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path');
  }

  Map<String, String> _workerHeaders() {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Sign in again before using Agent jobs.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  void _throwForWorkerError(http.Response response, Map<String, dynamic> data) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final detail = data['detail'] ?? data['error'] ?? response.body;
    throw StateError(detail.toString());
  }

  Map<String, dynamic> _decodeJsonResponse(String body) {
    if (body.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'data': decoded};
    } catch (_) {
      return {'data': body};
    }
  }
}
