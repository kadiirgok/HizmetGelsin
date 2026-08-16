# Yapılan Değişiklikler ve Düzeltmeler (21 Temmuz 2026)

## 1. Çift Rol Desteği (Müşteri & İşletme)
- **Sorun:** İşletme profiline sahip kullanıcılar "Müşteri olarak devam et" seçeneğiyle giriş yapmak istediklerinde backend tarafından `auth_role_mismatch` (Rol uyuşmazlığı) hatası dönüyor ve bu hata uygulamada yanlış çevrilerek "Oturumunuz sona erdi" şeklinde ekrana yansıyordu.
- **Çözüm:**
  - `Berbergelsin.Api/Controllers/AuthController.cs` dosyasındaki katı rol kontrolleri esnetildi.
  - Eğer kullanıcı Müşteri olarak kayıtlıysa ve "İşletme olarak devam et" seçerse, otomatik olarak rolü `Berber` olarak güncelleniyor ve bir `BarberProfile` oluşturuluyor.
  - Eğer kullanıcı Berber (İşletme) ise ve "Müşteri olarak devam et" seçerse, herhangi bir hata vermeden giriş yapmasına izin veriliyor.
  - `Berbergelsin.Api/Services/TokenService.cs` dosyasında JWT token oluşturulurken, `Berber` yetkisine sahip hesaplara otomatik olarak `Musteri` yetkisi de ekleniyor. Böylece Müşteri API endpoint'lerinde yetki hatası (403 Forbidden) alınması engellendi.
  - Uygulama tarafında (`lib/core/api/api_client.dart`) "auth_role_mismatch" hatası gelmesi ihtimaline karşı doğru Türkçe uyarı eklendi.

## 2. Arayüz Düzeltmeleri
- **Sorun:** İşletme randevu ekranında (`barber_panel_screen.dart`) ikonların arka planında yeni siyah-beyaz temaya uymayan gereksiz gri/tonal bir arka plan (filledTonal) kalmıştı.
- **Çözüm:** 
  - `IconButton.filledTonal` kullanımları standart şeffaf `IconButton` ile değiştirilerek siyah/beyaz minimalist tasarımla tam uyum sağlandı. (Örn. Bildirim, Yenileme ve Tarih ikonları).

## 3. Resimlerin Yüklenmemesi
- **Sorun Analizi:** Yeni sunucuya veritabanı taşınmış olmasına rağmen, büyük ihtimalle eski sunucudaki yüklenmiş fiziksel resim dosyaları (`uploads` klasöründeki dosyalar) kopyalanmadığı için resimlerin kaynak linkleri kırık gelmektedir.
- **Çözüm (Not):** API resim URL'lerini doğru üretse bile, sunucuda ilgili UUID formatındaki resim dosyası bulunmadığı için resimler görünmeyecektir. Çözüm olarak kullanıcıların profil/işletme resimlerini uygulamadan tekrar yüklemeleri gerekmektedir. Yeni eklenen resimler yeni sunucunun hafızasında (storage klasöründe) tutulacağı için sorunsuz yüklenecektir.

## 4. Yayınlama
- Yukarıdaki API değişiklikleri derlendi ve yeni sunucuya (<SUNUCU_IP>) `berbergelsin-publish-production-staging-20260721` adıyla aktarıldı.
- Mobil uygulamanın yeni APK'sı (DNS sorununu bypass edecek geçici TryCloudflare Tunnel URL'i gömülü olarak) cihaza yüklendi.
