# BerberGelsin — Prodüksiyona Hazırlama Master Promptu

Aşağıdaki görevi mevcut çalışma alanındaki kod üzerinde gerçekleştir. Bu bir yeniden yazım görevi değildir. Mevcut çalışan davranışları ve doğrulanmış backend sözleşmelerini koruyarak uygulamayı ölçülebilir, küçük ve güvenli adımlarla prodüksiyon kalitesine taşı.

## Rolün ve çalışma biçimin

Kıdemli Flutter/Dart mühendisi, mobil güvenlik uzmanı ve ürün odaklı teknik lider gibi hareket et. Yalnızca rapor üretme; önce kısa bir durum tespiti yap, öncelikli uygulama sırasını belirle ve ardından kullanıcıdan tekrar onay beklemeden güvenli, kapsam içi değişiklikleri uygula.

Şu kurallara kesinlikle uy:

1. Önce depoyu ve gerçek kodu incele. Dosya adlarına veya bu prompttaki özete dayanarak varsayım yapma.
2. Mevcut API yollarını, JSON alanlarını, durum değerlerini ve SignalR olaylarını koddan çıkar. Backend deposu veya güncel bir API şeması yoksa yeni endpoint, alan, durum ya da hub olayı uydurma.
3. Backend değişikliği gerektiren konuları mobil istemcide sahte bir çözümle gizleme. Bunları “backend bağımlılığı” olarak, gereken sözleşmeyle birlikte son rapora yaz.
4. Mevcut kullanıcı akışlarını sebepsiz yere değiştirme. Büyük çaplı yeniden yazım yerine küçük, gözden geçirilebilir değişiklikler yap.
5. Her aşamanın ardından biçimlendirme kontrolü, statik analiz ve ilgili testleri çalıştır. Araç veya SDK yoksa bunu açıkça belirt; mevcut ortamda çalıştırılabilen en yakın doğrulamayı yap.
6. Kaynak dosyaları UTF-8 olarak koru. Türkçe metinlerde karakter bozulmasına yol açma.
7. Gizli anahtar, gerçek telefon, token, sertifika veya kişisel veri ekleme ve loglama.
8. Güvenlik sorunlarını yalnızca UI’da saklayarak çözme. Yetkilendirmenin backend tarafından uygulanması gerektiği yerleri açıkça belirt.

## Ürün bağlamı

BerberGelsin, müşterinin yakındaki uygun berberleri haritada görüp evine hizmet çağırabildiği üç rollü bir mobil platformdur:

- **Müşteri:** OTP ile giriş, müşteri onboarding’i ve KVKK onayı, konum izni, haritada çevrimiçi berberleri görme, profil/hizmet inceleme, doğrudan talep veya fiyat teklifi oluşturma, karşı teklif yönetimi, talep takibi, iptal/tamamlama ve puanlama.
- **Berber:** OTP ile giriş, çok adımlı profil–belge–hizmet onboarding’i, admin onayı bekleme, çevrimiçi olma, konum paylaşma, talepleri kabul veya reddetme, yola çıkma/başlatma/tamamlama, teklif yönetimi, müşteriyi puanlama, profil/logo/hizmet yönetimi.
- **Admin:** Berber başvurularını durumlarına göre listeleme, başvuru ve belgeleri inceleme, onaylama veya gerekçeli reddetme.

Kritik talep durumları kodda `Pending`, `Accepted`, `OnTheWay`, `Started`, `Completed` ve iptal/red varyantlarıyla; berber onay durumları `Onboarding`, `PendingApproval`, `Approved`, `Rejected` değerleriyle temsil ediliyor. Gerçek ve eksiksiz durum kümesini modellerden ve ekran koşullarından doğrula; karşılaştırmaları mümkün olduğunca merkezi ve tip güvenli hale getirirken wire değerlerini değiştirme.

## Mevcut teknik çerçeve

Projede Flutter/Dart ve ağırlıklı olarak şu bileşenler kullanılıyor:

- `flutter_bloc` ve `hydrated_bloc`
- `dio` tabanlı merkezi API istemcisi
- `go_router` ile rol/onboarding durumuna bağlı yönlendirme
- `flutter_secure_storage` ile access/refresh token saklama
- `signalr_netcore` ile `/hubs/app` gerçek zamanlı bağlantısı
- `flutter_map`, OpenStreetMap tile’ları, `latlong2` ve `geolocator`
- Dosya seçimi/yükleme, Markdown KVKK metni, URL açma ve Türkçe yerelleştirme
- Android ve iOS hedefleri ile Codemagic yapılandırması

Bu kütüphaneleri sırf kişisel tercih nedeniyle değiştirme. Değişiklik ancak somut güvenlik, bakım, uyumluluk veya test edilebilirlik faydası sağlıyorsa ve kapsamı kontrollüyse yapılmalı.

## Ön incelemede mutlaka doğrulanacak noktalar

İlk incelemede aşağıdakileri kod üzerinden doğrula ve önem derecesi ver:

- `AuthCubit` içinde sabit bir telefonla çalışan `admin-bootstrap` yolunun ve `/api/auth/admin-bootstrap` çağrısının prodüksiyon güvenlik etkisi.
- Access token yenileme, aynı anda gelen 401 yanıtları, refresh başarısızlığı, oturum sonlandırma ve güvenli saklama davranışı.
- Router yönlendirmelerinin üç rol, onboarding ve berber onay durumları için döngüsüz ve güvenli olması.
- Rol ve yetki kontrollerinin istemcideki görünürlük kontrolünden ibaret kalıp kalmadığı; gerçek yetkinin backend’de zorunlu olduğu noktalar.
- SignalR bağlantı/yeniden bağlantı yaşam döngüsü, dinleyici temizliği, sessizce yutulan hatalar ve REST fallback davranışı.
- Konum izinleri, servis kapalı durumu, uygulama yaşam döngüsü ve berber konum paylaşımının gerçekten ne zaman başlayıp bittiği.
- Android manifestindeki foreground service/background location niyeti ile gerçek native/service uygulamasının uyumu; iOS izin açıklamaları ve mağaza politikaları.
- Kaynaklarda görülen `Ã`, `Ä`, `Å`, `â` gibi mojibake/karakter kodlama bozulmaları.
- `Map<String, dynamic>` kullanılan admin ve diğer ekranlarda tip güvenliği ve parse hataları.
- Ekranlarda doğrudan singleton/repository/API kullanımının test edilebilirliğe etkisi.
- Yükleme, boş veri, tekrar deneme, çevrimdışı olma, timeout, iptal ve beklenmeyen sunucu cevabı durumları.
- README’nin varsayılan Flutter metni olarak kalması, test dizinlerinin bulunmaması ve CI’ın analiz/test kapısı içermemesi.
- Release API adresi, `--dart-define`/ortam ayrımı, Android cleartext geliştirme trafiği, imzalama ve mağaza dağıtım ayarları.

## Uygulama aşamaları

### 1. Envanter ve güvenlik tabanı

- Uygulama giriş noktası, router, auth/token akışı, API istemcisi, SignalR servisi, repository’ler, platform manifestleri ve CI yapılandırmasını incele.
- Mevcut REST yolları, request/response modelleri ve SignalR event/metot sözleşmelerini kısa bir envantere dönüştür; bu envanteri kodu değiştirirken referans al.
- Admin bootstrap kestirmesini prodüksiyon derlemesinden kaldır veya yalnızca açık, derleme zamanı kontrollü ve release modunda etkinleşmesi imkânsız bir geliştirme mekanizmasına dönüştür. Backend endpoint’i prodüksiyonda açıksa bunun ayrıca backend açığı olduğunu raporla.
- Token yenilemede yarış koşullarını önle; aynı anda birden fazla refresh yapılmamasını, başarısız refresh sonrasında kuyruğun güvenli biçimde sonlanmasını ve tek bir oturum düşürme akışını sağla.
- Kullanıcıya gösterilen hata ile geliştirici tanı bilgisini ayır. Token, telefon, belge içeriği ve hassas response gövdelerini loglama.

### 2. Mimari ve güvenilirlik

- String tabanlı rol/durum karşılaştırmalarını wire değerlerini koruyan enum/value object veya merkezi dönüştürücülerle tip güvenli hale getir.
- Admin ekranlarındaki ham map kullanımı dahil olmak üzere hata riski yüksek yanıtlar için doğrulamalı modeller oluştur. Eksik/bozuk alanlarda uygulamanın çökmesi yerine kontrollü hata üret.
- API hata sınıflandırmasını bağlantı, timeout, yetkisiz, doğrulama, sunucu ve bilinmeyen hata türlerini ayıracak şekilde merkezileştir; Türkçe kullanıcı mesajlarını tutarlı hale getir.
- Repository ve state bağımlılıklarını test doubles enjekte edilebilecek biçimde düzenle. Tüm projeyi tek seferde yeni mimariye taşımaya çalışma; kritik auth, talep ve harita akışlarından başla.
- SignalR için bağlantı durumu, reconnect sonrası gerekli gruba yeniden katılma, dinleyici yaşam döngüsü ve başarısız invoke davranışlarını görünür ve test edilebilir yap.
- Sessiz `catch` bloklarını incele. Kullanıcı aksiyonu başarısızsa geri bildirim göster; yalnızca gerçekten best-effort olan işlemleri sessiz bırak ve gerekçelendir.

### 3. UX, erişilebilirlik ve yerelleştirme

- Her veri ekranında birbirinden ayrılmış yükleniyor, içerik, boş, hata ve tekrar dene durumları sağla.
- OTP/telefon, profil, fiyat, hizmet, tarih-saat ve ret gerekçesi alanlarında açık doğrulama ve klavye davranışı kullan.
- Konum izni reddedildi, kalıcı reddedildi ve servis kapalı durumlarını ayrı ele al; kullanıcıyı uygun sistem ayarına yönlendir.
- Çift gönderimi önle, uzun işlemlerde butonları kontrollü devre dışı bırak ve başarılı/başarısız işlemleri erişilebilir şekilde bildir.
- Dokunma hedefleri, semantik etiketler, metin ölçekleme, kontrast, ekran okuyucu sırası ve klavye açıldığında taşma durumlarını kontrol et.
- Türkçe metinleri ve ürün adını tutarlılaştır. Tüm mojibake bozulmalarını gerçek UTF-8 Türkçe karşılıklarıyla düzelt; API wire değerlerini çevirmeye çalışma.
- KVKK onayını zorunlu, izlenebilir ve anlaşılır tut; hukuki metnin içeriğini hukuk görüşü olmadan yeniden yazma.

### 4. Konum, gerçek zamanlı takip ve platform uyumu

- Müşterinin harita katılımı ile berberin çevrimiçi/konum paylaşımı akışlarını yaşam döngüsü açısından doğrula.
- Konum güncelleme sıklığı, doğruluk ve pil tüketimi arasında makul denge kur; gereksiz güncellemeleri azalt ve ekran/oturum kapanışında kaynakları temizle.
- Uygulama arka plandayken konum takibi gerçekten gerekmiyorsa gereksiz izin/manifest beyanlarını kaldır. Gerekiyorsa Android foreground service bildirimi ve iOS background mode dahil eksik native altyapıyı ve politika gereklerini açıkça ele al; yalnızca manifest izni eklemeyi tamamlanmış çözüm sayma.
- OpenStreetMap tile kullanımında uygun user-agent/attribution, hata davranışı ve üretim kullanım politikasını kontrol et. Sağlayıcı değişimi gerekiyorsa bunu kanıt ve yapılandırma gereksinimiyle raporla; key uydurma.

### 5. Otomatik testler ve kalite kapıları

Test altyapısı yoksa oluştur. Minimum olarak şunları kapsa:

- Auth bootstrap: refresh token yok, `/me` başarılı, 401, geçici ağ hatası ve refresh başarısızlığı.
- Router matrisi: unauthenticated; müşteri onboarding tamamlanmış/tamamlanmamış; berber onboarding/pending/rejected/approved; admin.
- API token refresh eşzamanlılığı ve yalnızca bir kez session-expired bildirimi.
- Talep durum geçişleri: oluşturma, kabul/red, yola çıkma, başlatma, tamamlama, iptal ve karşılıklı puanlama görünürlüğü.
- Fiyat teklifi: oluşturma, kabul/red, karşı teklif ve karşı teklif kabul/red.
- Model parsing: geçerli cevaplar, opsiyonel alanlar, eksik/yanlış tipli kritik alanlar.
- En az kritik müşteri ve berber ekranları için loading/empty/error/success widget testleri.
- Mümkünse sahte API/SignalR ile müşteri talebi → berber kabulü → yola çıkma → başlatma → tamamlama → puanlama entegrasyon senaryosu.

Testleri gerçek backend’e ve gerçek konum servisine bağımlı yapma. Saat, ağ, storage, konum ve gerçek zamanlı bağlantıları taklit edilebilir hale getir. Snapshot/golden test yalnızca kararlı ve anlamlı olacaksa ekle.

CI’a en az şu kalite kapılarını ekle: dependency çözümleme, format kontrolü, `flutter analyze`, unit/widget testleri ve ardından platform build. Bir kontrol başarısızsa build başarısız olmalı; hataları `|| true` benzeri yöntemlerle gizleme.

### 6. Release hazırlığı ve dokümantasyon

- Dev/staging/prod API adreslerini güvenli ve açık bir ortam stratejisine bağla. Release’in yanlışlıkla localhost veya cleartext endpoint kullanmasını engelle.
- Android/iOS izinlerini yalnızca gerçek özelliklerle uyumlu tut; kullanıcıya gösterilen izin gerekçelerini Türkçeleştir ve mağaza beyanlarıyla uyumlu hale getir.
- Android imzalı AAB ve iOS TestFlight/App Store süreci için gereken yapılandırmayı, sırları repoya koymadan dokümante et. Mevcut unsigned IPA akışını geliştirme amacıyla açıkça etiketle.
- Crash/telemetry altyapısı yoksa sağlayıcı uydurup bağımlılık ekleme; kişisel veri toplamayan bir loglama arayüzü hazırla ve harici servis seçimini açık karar olarak raporla.
- README’yi gerçek proje dokümanına dönüştür: ürün özeti, roller, gereksinimler, Flutter/Dart sürümü, kurulum, ortam değişkenleri, geliştirme backend adresi, analiz/test/build komutları, platform izinleri, mimari özet, CI/release ve bilinen backend bağımlılıkları.

## Korunacak davranışlar ve sözleşmeler

- `Musteri`, `Berber`, `Admin` wire rol değerleri backend doğrulanmadan değiştirilmemeli.
- Mevcut auth, onboarding, barbers, requests, offers ve admin API yolları doğrulanmadan yeniden adlandırılmamalı.
- `/hubs/app` ile kullanılan `JoinMap`, `LeaveMap`, `SetOnline`, `UpdateLocation` ve dinlenen olaylar backend doğrulanmadan değiştirilmemeli.
- GoRouter’ın rol/onboarding/onay yönlendirme mantığı davranış olarak korunmalı; yalnızca hata, döngü veya güvenlik problemi kanıtlanırsa düzeltilmeli.
- KVKK metni hukuki içerik olarak kendiliğinden yeniden yazılmamalı.
- Tasarım yenilemesi bu görevin ana amacı değildir; tutarlılık, erişilebilirlik ve hata durumları önceliklidir.

## Kabul kriterleri

Görevi ancak aşağıdaki koşullar karşılandığında tamamlanmış say:

1. Üç rolün giriş, yönlendirme ve onboarding/onay akışları korunuyor ve otomatik testlerle doğrulanıyor.
2. Admin bootstrap prodüksiyon istemcisinde kullanılamıyor; backend riski varsa açıkça raporlanıyor.
3. Oturum yenileme eşzamanlı isteklerde güvenli; 401/refresh hataları kontrollü logout üretiyor.
4. Ağ, timeout, bozuk response, bağlantı kaybı, izin reddi ve servis kapalı durumları uygulamayı çökertmeden anlaşılır geri bildirim veriyor.
5. Talep ve teklif yaşam döngüsünün kritik geçişleri testlerle kapsanıyor.
6. SignalR dinleyicileri sızmıyor; reconnect ve REST fallback davranışı tanımlı.
7. Türkçe karakter bozuklukları giderilmiş ve dosyalar UTF-8.
8. `flutter analyze` ve tüm testler geçiyor. Çalıştırılamayan kontrol varsa komut, engel ve beklenen çözüm son raporda yazıyor.
9. CI analiz ve testleri build’den önce zorunlu kalite kapısı olarak çalıştırıyor.
10. README gerçek kurulum, ortam, test ve release sürecini tekrar edilebilir biçimde anlatıyor.
11. Android ve iOS izinleri gerçek davranışla uyumlu; gereksiz yüksek riskli izin yok.
12. Backend sözleşmesi uydurulmamış; backend gerektiren her konu ayrı ve uygulanabilir şekilde listelenmiş.

## İstenen başlangıç çıktısı

Kod değişikliğine başlamadan önce kısa ve yoğun bir başlangıç özeti ver:

1. Doğrulanan mimari ve kullanıcı akışları.
2. P0/P1/P2 olarak önemlendirilmiş bulgular.
3. Uygulanacak aşamalar ve her aşamanın doğrulama komutları.
4. Backend veya dış servis bağımlılıkları.

Bu özetten sonra onay istemeden uygulamaya geç.

## İstenen final raporu

Çalışma bittiğinde şu formatta raporla:

- **Sonuç:** Uygulamanın prodüksiyon hazırlık düzeyi ve kısa özet.
- **Uygulanan değişiklikler:** Davranış odaklı, dosya dökümü olmayan gruplandırılmış liste.
- **Doğrulama:** Çalıştırılan format, analiz, test ve build komutları ile sonuçları.
- **Güvenlik:** Kapatılan riskler ve devam eden riskler.
- **Backend bağımlılıkları:** Mobil tarafta çözülemeyen, backend’de yapılması gereken maddeler.
- **Kalan işler:** Yalnızca gerçekten kapsam dışı veya dış bağımlılığa bağlı işler; önem sırasıyla.

Başarı ölçütü çok dosya değiştirmek değil; doğrulanmış güvenlik ve güvenilirlik kazanımları üretirken mevcut ürünü çalışır halde tutmaktır.
