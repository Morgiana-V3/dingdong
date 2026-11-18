/// Only user-activated navigation to web, mail, and supported content apps.
/// Android validates and reconstructs app routes again before launching them.
Uri? externalLink(String address) {
  final trimmed = address.trim();
  final uri = Uri.tryParse(
    trimmed.startsWith('//') ? 'https:$trimmed' : trimmed,
  );
  if (uri == null || uri.userInfo.isNotEmpty) return null;
  if (['http', 'https'].contains(uri.scheme)) {
    return uri.host.isNotEmpty ? uri : null;
  }
  if (uri.scheme == 'mailto') return uri.path.isNotEmpty ? uri : null;
  if ([
        'twitter',
        'com.baidu.tieba',
        'bilibili',
        'xhsdiscover',
      ].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      !uri.hasPort) {
    return uri;
  }
  return null;
}
