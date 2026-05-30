import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class McpConnectPage extends StatefulWidget {
  const McpConnectPage({super.key});

  @override
  State<McpConnectPage> createState() => _McpConnectPageState();
}

class _McpConnectPageState extends State<McpConnectPage> {
  String _status = 'checking';
  String _mcpUrl = '';
  String _version = '';
  bool _copyingUrl = false;
  bool _copyingConfig = false;

  @override
  void initState() {
    super.initState();
    _mcpUrl = _buildMcpUrl();
    _checkStatus();
  }

  String _buildMcpUrl() {
    final configured = AppConfig.mcpServerUrl;
    if (configured.isNotEmpty) return configured;
    if (AppConfig.fastApiBaseUrl.contains('worker') ||
        AppConfig.fastApiBaseUrl.contains('render')) {
      return 'https://mcp.bluepill.app';
    }
    return 'http://localhost:8001';
  }

  Future<void> _checkStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$_mcpUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map;
        setState(() {
          _status = 'connected';
          _version = body['version'] as String? ?? '';
        });
        return;
      }
    } catch (_) {}
    setState(() => _status = 'offline');
  }

  String _configJson(String platform) {
    return const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'bluepill': {
          'url': '$_mcpUrl/sse',
          if (platform == 'token')
            'headers': {
              'Authorization': 'Bearer <your-supabase-jwt>',
            }
          else
            'token': '<your-supabase-jwt>',
        },
      },
    });
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() {
      if (label == 'url') _copyingUrl = true;
      if (label == 'config') _copyingConfig = true;
    });
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      if (label == 'url') _copyingUrl = false;
      if (label == 'config') _copyingConfig = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Connect'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _statusCard(context),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Server URL'),
          const SizedBox(height: 8),
          _urlCopyCard(context),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Platform Config'),
          const SizedBox(height: 8),
          _configCard(
            context,
            'Claude Desktop',
            _configJson('token'),
            Icons.assistant,
          ),
          const SizedBox(height: 12),
          _configCard(
            context,
            'Cursor / Continue.dev',
            _configJson('token'),
            Icons.code,
          ),
          const SizedBox(height: 12),
          _configCard(
            context,
            'OpenAI (Custom GPT Action)',
            _configJson('token'),
            Icons.psychology,
          ),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Discovery Endpoint'),
          const SizedBox(height: 8),
          _copyField(
            context,
            '$_mcpUrl/.well-known/mcp.json',
            Icons.open_in_new,
            'endpoint',
            onTap: () => _copyToClipboard(
              '$_mcpUrl/.well-known/mcp.json',
              'endpoint',
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Need a JWT?'),
          const SizedBox(height: 8),
          _jwtHintCard(context),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (Color color, String label, IconData icon) = switch (_status) {
      'connected' => (Colors.green, 'Connected', Icons.check_circle),
      'checking' => (Colors.orange, 'Checking...', Icons.sync),
      _ => (Colors.red, 'Offline', Icons.error_outline),
    };
    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MCP Gateway',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (_version.isNotEmpty)
              Chip(
                label: Text('v$_version'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _urlCopyCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.link, color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                '$_mcpUrl/sse',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                _copyingUrl ? Icons.check : Icons.copy,
                size: 20,
              ),
              onPressed: () => _copyToClipboard('$_mcpUrl/sse', 'url'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _configCard(
    BuildContext context,
    String platform,
    String json,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  platform,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => _copyToClipboard(json, 'config'),
                  icon: Icon(
                    _copyingConfig ? Icons.check : Icons.copy,
                    size: 16,
                  ),
                  label: Text(_copyingConfig ? 'Copied!' : 'Copy'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                json,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _copyField(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(
                  value,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.copy, size: 16, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jwtHintCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Get your Supabase JWT',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your Supabase session token is used to authenticate MCP requests. '
                    'Copy it from the Supabase Auth session in your browser dev tools, '
                    'or use the OAuth2 flow documented at the discovery endpoint.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
