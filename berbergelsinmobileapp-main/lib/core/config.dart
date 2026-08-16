class AppConfig {
  /// Tüm flavor/build türlerinde güvenli varsayılan canlı HTTPS backend'dir.
  /// Yerel geliştirme yalnız açık API_BASE_URL dart-define ile etkinleştirilir;
  /// böylece fiziksel cihaz debug APK'sı emülatöre özel 10.0.2.2'ye düşmez.
  /// Geçici Cloudflare Tüneli (Bot Korumasını ve DPI'ı Aşmak İçin)
  static const String _prodBaseUrl = 'https://infrastructure-cooper-accomplished-richmond.trycloudflare.com';
  static String get baseUrl {
    final url = const String.fromEnvironment('API_BASE_URL', defaultValue: _prodBaseUrl).trim();
    // Sondaki yanlışlıkla eklenmiş slash veya karakterleri temizle
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static String get hubUrl => '$baseUrl/hubs/app';

  /// Virgülle ayrılmış HTTPS app-link hostları. Domain doğrulanmadan boş kalır;
  /// örnek: --dart-define=DEEP_LINK_HOSTS=links.example.com
  static List<String> get deepLinkHosts =>
      const String.fromEnvironment('DEEP_LINK_HOSTS', defaultValue: '')
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
}
