# HizmetGelsin Mobil Uygulaması

HizmetGelsin; müşterilerin yakındaki çevrimiçi berberlerden eve hizmet talep etmesini, fiyat teklifi vermesini ve randevuyu canlı takip etmesini sağlayan Flutter uygulamasıdır. Aynı uygulama müşteri, berber ve admin rollerini destekler.

## Proje yapısı

- `berbergelsinmobileapp-main/` — Flutter mobil uygulaması
- `backend/` — .NET 8 Web API (PostgreSQL, SignalR, Firebase Admin)

Aşağıdaki Flutter ile ilgili komutlar ve yollar aksi belirtilmedikçe `berbergelsinmobileapp-main/` klasörüne göredir.

## Temel akışlar

- Müşteri: OTP ile giriş, onboarding/KVKK, harita, talep ve teklif, canlı takip, puanlama
- Berber: OTP ile giriş, belge ve hizmet onboarding'i, admin onayı, çevrimiçi olma, konum paylaşımı, talep/teklif yönetimi
- Admin: Berber başvurularını ve belgelerini inceleme, onaylama veya gerekçeli reddetme

## Teknik yapı

- Flutter 3.35.2 / Dart 3.9 veya uyumlu daha yeni sürüm
- BLoC ve Hydrated BLoC
- Dio tabanlı REST istemcisi
- GoRouter ile rol ve onboarding odaklı yönlendirme
- SignalR ile gerçek zamanlı talep, teklif ve konum güncellemeleri
- Flutter Map ve OpenStreetMap
- Güvenli token saklama için Flutter Secure Storage

Uygulama kodu özellik bazlı olarak `berbergelsinmobileapp-main/lib/features` altında; API, router, SignalR, tema ve ortam yapılandırması `berbergelsinmobileapp-main/lib/core` altında bulunur.

## Kurulum

1. Flutter SDK'nın uygun sürümünü kurun ve `flutter doctor` çıktısındaki platform eksiklerini giderin.
2. Flutter uygulaması klasöründe (`berbergelsinmobileapp-main/`) bağımlılıkları yükleyin:

   ```text
   flutter pub get
   ```

3. Geliştirme backend'ini çalıştırın veya API adresini `API_BASE_URL` ile verin.
4. Uygulamayı başlatın:

   ```text
   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080
   ```

Android emülatöründe `10.0.2.2` host makineyi ifade eder. Fiziksel cihazda bilgisayarın cihazdan erişilebilen yerel ağ adresini kullanın.

## Firebase ve backend yapılandırması

Repoya girmeyen (gitignore'lu) dosyaları kendi değerlerinizle oluşturun; repoda yalnızca `.example` şablonları bulunur.

### Firebase (mobil)

FlutterFire CLI ile hem `firebase_options.dart` hem `google-services.json` üretilir:

```text
flutterfire configure
```

Alternatif olarak örnek şablonları kopyalayıp kendi Firebase proje değerlerinizle doldurun:

- `berbergelsinmobileapp-main/lib/firebase_options.example.dart` → `berbergelsinmobileapp-main/lib/firebase_options.dart`
- `berbergelsinmobileapp-main/android/app/google-services.example.json` → `berbergelsinmobileapp-main/android/app/google-services.json`
  (veya Firebase Console → Proje ayarları → Uygulamalar → Android → `google-services.json` indirip `berbergelsinmobileapp-main/android/app/` altına koyun)

Bu iki dosya git'e girmez; `firebase.json` (proje/app kimliği) repoda tutulur.

### Backend (.NET)

`appsettings.Example.json` dosyasını `appsettings.json` olarak kopyalayıp kendi değerlerinizle doldurun:

```text
cp backend/Berbergelsin.Api/appsettings.Example.json backend/Berbergelsin.Api/appsettings.json
```

Doldurulacak alanlar: `ConnectionStrings:Default` (PostgreSQL bağlantısı), `Jwt:Key`, `Otp:Pepper`, `SmsSettings` ve `Email` SMTP bilgileri. `appsettings.json`, `appsettings.Development.json` ve `appsettings.Production.json` git'e girmez; yalnızca `.Example` şablonu commit edilir.

## Ortam yapılandırması

`API_BASE_URL`, derleme zamanında `--dart-define` ile değiştirilebilir. Güvenli
varsayılan tüm flavor ve build türlerinde production HTTPS backend'idir. Yerel
backend kullanımı açıkça `--dart-define=API_BASE_URL=http://10.0.2.2:5080` ile
seçilmelidir; `10.0.2.2` yalnız Android emülatörü içindir.

- Debug: `http://10.0.2.2:5080`
- Release: `https://api.tivigo.online`
- SignalR hub: seçili API adresine eklenen `/hubs/app`

Release üretmeden önce hedef backend adresini açıkça doğrulayın. Token, imzalama anahtarı, sertifika ve diğer sırları repoya eklemeyin.

## Kalite kontrolleri

Değişiklik göndermeden önce çalıştırın:

```text
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Codemagic iş akışları bu kontrolleri platform build'lerinden önce zorunlu olarak çalıştırır.

## Platform izinleri

Konum izni müşteriye yakındaki berberleri göstermek ve çevrimiçi berberin konumunu paylaşmak için kullanılır. Uygulama; servis kapalı, geçici ret ve kalıcı ret durumlarını ayrı ele alır.

Berber panelindeki Android konum akışı foreground service bildirimi kullanır. iOS arka plan konum davranışı ve App Store/Google Play izin beyanları gerçek cihazda ve mağaza politikalarına göre ayrıca doğrulanmalıdır. İhtiyaç olmayan yüksek riskli izinler release öncesinde kaldırılmalıdır.

## Build ve dağıtım

Android yerel release kontrolü:

```text
flutter build appbundle --release --dart-define=API_BASE_URL=https://example.com
```

iOS release, geçerli Apple signing yapılandırmasıyla macOS/Xcode üzerinde üretilmelidir. `codemagic.yaml` içinde Android APK, iOS simulator ve geliştirme amaçlı unsigned IPA akışları bulunur. Unsigned IPA App Store dağıtımı değildir. Mağaza sırlarını Codemagic'in şifreli environment gruplarında tutun.

## Güvenlik notları

- İstemcideki rol yönlendirmeleri kullanıcı deneyimi içindir; tüm yetkilendirme backend'de ayrıca zorunlu olmalıdır.
- OTP, refresh token, belge erişimi, admin işlemleri ve SignalR hub metotları backend'de rol ve kaynak sahipliği kontrolü yapmalıdır.
- Kaynak kodda OTP'siz admin/test giriş yolu bulunmamalıdır. Böyle bir backend endpoint'i varsa prodüksiyonda kapatılmalıdır.
- Hassas response gövdeleri, tokenlar, telefonlar ve belge verileri loglanmamalıdır.

## Bilinen dış bağımlılıklar

Mobil uygulama backend sözleşmelerini değiştirmez. Aşağıdakiler backend/operasyon tarafında ayrıca doğrulanmalıdır:

- Admin bootstrap/test endpoint'inin prodüksiyonda kapalı olması
- Her endpoint ve SignalR metodunda rol/kaynak yetkilendirmesi
- Refresh token rotasyonu, iptal ve tekrar kullanım politikası
- OTP hız sınırı, deneme sınırı ve kötüye kullanım koruması
- Belge indirme yetkileri ve saklama politikası
- KVKK metni, açık rıza kayıtları ve mağaza gizlilik beyanları
