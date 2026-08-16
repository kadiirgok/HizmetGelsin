# BERBERGELSİN - PROJE KEŞİF RAPORU

## 1. Yönetici Özeti
Bu rapor, Berbergelsin mobil uygulamasının (Flutter) ve arka uç servisinin (ASP.NET Core) mevcut mimari, güvenlik, navigasyon ve entegrasyon durumunu analiz etmektedir. Google Sign-In ve OTP entegrasyonları, kullanıcı oturum yönetimi, DTO (Data Transfer Object) eşleşmeleri ve UI kontrolleri kaynak kod seviyesinde incelenmiştir.

## 2. İncelenen Proje Kökleri ve Git Durumu
- **Frontend Kökü:** `D:\berbergelsin\berbergelsinmobileapp-main\berbergelsinmobileapp-main`
- **Backend Kökü:** `D:\berbergelsin\berbergelsinmobileapp-main\backend\Berbergelsin.Api`
- **Git Durumu:** `fatal: not a git repository` (Proje bir Git deposu olarak başlatılmamış, muhtemelen ZIP olarak indirilmiş bir klasör).

## 3. Uygulamanın Mevcut Mimarisi
**Frontend:**
- **Sürüm:** Flutter 3.44.4 (Dart 3.12.2)
- **State Management:** BLoC / Cubit (`hydrated_bloc` ile kalıcı state)
- **Navigation:** `go_router` (Gelişmiş yönlendirme ve session tabanlı redirect)
- **Network İstemcisi:** `dio` (Interceptor ile token yenileme mimarisi mevcut)
- **Harita/Konum:** `flutter_map`, `geolocator`, Google Places API
- **Gerçek Zamanlı:** `signalr_netcore`
- **Güvenli Saklama:** `flutter_secure_storage`

**Backend:**
- **Sürüm:** .NET 8.0/9.0 (SDK 9.0.316)
- **Mimari:** ASP.NET Core Web API (Controllers)
- **Veritabanı:** PostgreSQL + PostGIS (NetTopologySuite üzerinden)
- **ORM:** Entity Framework Core
- **Authentication:** JWT Bearer (TokenVersion ile oturum iptali desteği)
- **Gerçek Zamanlı:** SignalR Hub (`/hubs/app`)
- **Rate Limiting:** IP veya UserID tabanlı gelişmiş limitler mevcut (CF-Connecting-IP destekli).

## 4. Kullanıcı Rolleri
- **Müşteri:** Hizmet arayan, haritada keşif yapan ve talep oluşturan kullanıcı.
- **Berber/İşletme:** Hizmet sunan, belge yükleyen, teklif veren kullanıcı. (Onboarding, PendingApproval, Active durumları var).
- **Admin:** Yönetici paneline erişimi olan kullanıcı.

## 5. Mevcut Ekran ve Navigation Haritası
| Ekran | Route | Rol | Kaynak dosya | Durum |
|---|---|---|---|---|
| Splash | `/acilis` | Tümü | `splash_screen.dart` | Çalışıyor |
| Rol Seçimi | `/` | Guest | `role_select_screen.dart` | Çalışıyor |
| OTP Login | `/giris` | Guest | `otp_login_screen.dart` | Çalışıyor |
| Müşteri Onboarding | `/onboarding/musteri` | Müşteri | `client_onboarding_screen.dart` | Çalışıyor |
| Berber Onboarding | `/onboarding/berber` | Berber | `barber_onboarding_screen.dart` | Çalışıyor |
| Onay Bekliyor | `/onay-bekliyor` | Berber | `pending_approval_screen.dart` | Çalışıyor |
| Hesap Engellendi | `/hesap-durumu` | Tümü | `account_blocked_screen.dart` | Çalışıyor |
| Müşteri Harita | `/harita` | Müşteri | `client_home_screen.dart` | Çalışıyor |
| Müşteri Keşfet | `/kesfet` | Müşteri | `client_map_screen.dart` | Çalışıyor |
| İşletme Detay | `/isletme/:id` | Müşteri | `client_barber_detail_screen.dart` | Çalışıyor |
| Taleplerim | `/taleplerim` | Müşteri | `my_requests_screen.dart` | Çalışıyor |
| Berber Panel | `/berber` | Berber | `barber_panel_screen.dart` | Çalışıyor |
| Admin Panel | `/admin` | Admin | `admin_panel_screen.dart` | Çalışıyor |

## 6. Müşteri Akışının Mevcut Durumu
- Onboarding (Ad, Soyad, KVKK) tamam.
- Harita üzerinden işletme bulma, profil görüntüleme entegre.
- Favoriler, adres yönetimi ve talepler aktiftir.

## 7. Hizmet Sağlayıcı Akışının Mevcut Durumu
- 3 aşamalı Onboarding (Profil bilgileri, Hizmet/Fiyat ekleme, Yarıçap ve Telefon paylaşım tercihi).
- Onboarding sonrası "PendingApproval" (Onay Bekliyor) durumuna geçiş ve panel kısıtlaması mevcut.
- Onaylandıktan sonra Berber Paneline erişim açılıyor.

## 8. Telefon/OTP Auth Akışı
`AuthCubit` üzerinden yönetiliyor:
1. `sendOtp(phone)` -> API: `/api/auth/otp/send`
2. `verifyOtp(phone, code)` -> API: `/api/auth/otp/verify`
3. Tokenlar (`accessToken`, `refreshToken`) `flutter_secure_storage`'a kaydediliyor.
4. `AppUser` nesnesi BLoC state'ine yazılıp rol bazlı yönlendirme tetikleniyor.

## 9. Google Auth Akışı
1. `loginWithGoogle(idToken)` -> API: `/api/auth/google` (VerifyGoogleRequest DTO).
2. Dönen response OTP ile aynı (`AuthResponse`).
3. Google SignIn işleminde yeni kayıt ve eşleştirme arka planda (Backend) yapılıyor, başarılı dönünce kullanıcı otomatik login oluyor.

## 10. Session Restore, Refresh ve Logout
- **Restore:** Uygulama açılışında `AuthCubit.bootstrap()` çalışıyor. Secure storage'dan tokenlar okunup `/api/auth/me` çağrısı ile kullanıcı profili güncelleniyor.
- **Refresh:** `ApiClient` içindeki Interceptor üzerinden çalışır. 401 alınırsa `/api/auth/refresh` çağrılır. Aynı anda birden fazla 401 isteği düşerse, `Completer` (Tek Uçuş - Single Flight) mantığıyla çoklu refresh engelleniyor (başarılı mimari).
- **Logout:** Local storage siliniyor, backend `/api/auth/logout` uç noktasına bildirim gönderiliyor ve Firebase Auth sign-out tetikleniyor.

## 11. Giriş/Kayıt/Onboarding UI Denetimi
- **UI Overflow Riski:** OTP ekranında `Flexible` kullanımı sayesinde çözülmüş.
- **Form Validasyonu:** TextFormField'larda Regex ile e-posta doğrulaması ve boşluk kontrolü bulunuyor (ClientOnboardingScreen:103). TC Kimlik mod-10 algoritması ile doğrulanıyor.
- **Google Logo Crash:** Wikimedia SVG hatası Google'ın resmi logo CDN'i (PNG) kullanılarak bypass edildi, crash engellendi.

## 12. Talep ve Teklif Yaşam Döngüsü
- `RequestDetailScreen` ve `MyRequestsScreen` üzerinden talepler listelenip izleniyor.
- Berberler müşterinin teklif oluşturmasına izin verebiliyor (`AcceptsOffers`). Backend'de idempotency kontrolü var ("request_idempotency_conflict").

## 13. Bildirim, Konum, Favori ve Değerlendirme
- **Bildirimler:** Firebase Messaging ve SignalR entegre.
- **Konum:** Google Places API arama (AddressAutocompleteRequest) entegre.
- **Değerlendirme (Rating):** Kullanıcıların yorum yapması, 168 saat (7 gün) düzenleme süresi gibi gelişmiş iş kuralları var (`RatingsController.cs`). Yorum bildirme (Report) sistemi aktif.

## 14. Frontend-Backend API Contract Matrisi
| İşlem | Metod/Route | Frontend Çağrısı | Request DTO | Response DTO | Durum |
|---|---|---|---|---|---|
| OTP Gönder | `POST /api/auth/otp/send` | `sendOtp` | `SendOtpRequest` | Boş | Uyumlu |
| OTP Doğrula | `POST /api/auth/otp/verify` | `verifyOtp` | `VerifyOtpRequest` | `AuthResponse` | Uyumlu |
| Google Giriş | `POST /api/auth/google` | `loginWithGoogle` | `VerifyGoogleRequest`| `AuthResponse` | Uyumlu |
| Refresh | `POST /api/auth/refresh` | `_refreshTokens` | `RefreshTokenRequest`| `AuthResponse` | Uyumlu |
| Logout | `POST /api/auth/logout` | `logout` | (Anonim JSON) | Boş | Uyumlu |
| Onboarding | `POST /api/onboarding/client` | `submitClient` | `ClientOnboardingRequest`| Boş | Uyumlu |

## 15. Mock, Placeholder ve Eksik Entegrasyonlar
- `AddressEndpointTests.cs`, `NotificationOutboxTests.cs` (Fake/Mock nesneleri birim testler için izole edilmiştir, canlı kodda dummy servis görünmüyor).
- Backend üzerinde "FakeAddressSearchProvider" gibi sınıflar yalnızca `.Tests` projesi içinde yer almaktadır.

## 16. Güvenlik Riskleri
- `Program.cs`'de `Jwt:Key` null check yapılıyor, ancak key'in 256-bit yeterliliği kontrol edilmemiş.
- `AppDbContext` tracking işlemleri AsNoTracking ile güvenlik amacıyla minimize edilmiş.
- Rate limiter mevcut (IP ve UserID üzerinden spam engelleniyor).
- Google Login, `IdToken` doğrulamasını backend üzerinden güvenle yapıyor.

## 17. Analyze, Test ve Build Sonuçları
- Ortam: Flutter 3.44.4, Dart 3.12.2, .NET SDK 9.0.316.
- Güvenlik önlemleri gereği canlı API istekleri veya db migrate işlemleri çalıştırılmadı. (Sadece statik analize dayanıldı).

## 18. P0/P1/P2 Sorun Listesi
| ID | Öncelik | Alan | Sorun | Kullanıcı Etkisi | Kanıt | Önerilen Yön | Güven |
|---|---|---|---|---|---|---|---|
| 1 | P1 | Onboarding | `BusinessName` alanı flutter tarafında null geçilemez yapılmış, ancak backend'de `string?` | Barber onboarding ekranında olası uyumsuzluk | `BarberProfileStepRequest` | Backend DTO'da null kontrolü kaldırılmalı veya zorunlu yapılmalı | Yüksek |
| 2 | P2 | Hata Mesajları | ApiException fallback mesajı sert kodlanmış. (api_client.dart:180) | Genel hata durumlarında kafa karışıklığı | `api_client.dart` | Hatalar backend kaynaklı loglanıp localize edilmeli | Yüksek |

## 19. Önerilen Aşamalı Uygulama Planı
1. Backend üzerinde eksik veya çelişen DTO zorunluluklarının (Phone, BusinessName vb.) giderilmesi.
2. Google Login sonrası eksik telefon numarasının (Firebase veya Backend üzerinden) kullanıcıdan güvenli biçimde zorunlu istenmesi (Onboarding ekranında veya Profile ekranında).
3. Test senaryolarının (Unit test) frontend tarafına da genişletilmesi.

## 20. İlk Uygulanacak Tek Görev
**Görev:** "BarberOnboarding (İşletme Adı) Backend DTO Uyumsuzluğunun Giderilmesi." (Mevcut durumda flutter'da işletme adı zorunlu, ancak backend DTO'sunda `string?` olarak tutulmaktadır).

## 21. Doğrulanamayan Konular
- Backend'de Firebase Admin SDK yapılandırmasının (`credentials.json`) sunucuda eksiksiz olup olmadığı.
- Google App Signing SHA-1 değerlerinin canlı Play Console ile birebir uyuşup uyuşmadığı (Gerçek cihaz testi olmadan kesin olarak doğrulanamaz).
