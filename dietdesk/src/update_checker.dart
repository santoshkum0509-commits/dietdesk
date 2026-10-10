import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// Replaced automatically by the GitHub workflow with your "owner/repo".
const _repo = 'OWNER/REPO';

Future<void> checkForUpdate(BuildContext context) async {
  try {
    final res = await http.get(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'));
    if (res.statusCode != 200) return;
    final data = jsonDecode(res.body);
    final latest = int.tryParse((data['tag_name'] as String).replaceAll('v', '')) ?? 0;
    final current = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    if (latest <= current) return;
    final apk = (data['assets'] as List)
        .firstWhere((a) => (a['name'] as String).endsWith('.apk'))['browser_download_url'] as String;
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update available'),
        content: Text('New version (build $latest) is ready.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () => launchUrl(Uri.parse(apk), mode: LaunchMode.externalApplication),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  } catch (_) {}
}
