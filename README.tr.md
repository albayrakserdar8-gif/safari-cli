# safari-cli

[English](README.md)

Kod ajanlarının (Claude Code, opencode, kabuğu olan herhangi bir ajan) senin açık Safari'ni, açık oturumlarınla kullanmasını sağlayan bir `safari` komutu. Tek bir Swift ikili dosyası, bağımlılığı yok. [safari-mcp](https://github.com/sadopc/safari-mcp)'den çatallandı: aynı motor, MCP sunucusu yerine bir CLI ve bir skill.

Kuruluysa isteğe bağlı **Safari MCP Bridge** eklentisi üzerinden, değilse Apple Events üzerinden çalışır.

Anthropic ile bağlantısı olmayan bağımsız bir projedir. Claude in Chrome yalnızca Chromium tarayıcılarda çalıştığı için yazıldı.

## Ne zaman kullanılır

Giriş yaptığın sitelerde günlük işler için uygundur: okuma, arama, form doldurma, gezinme. Web uygulaması testi, CI ve tekrarlanabilir otomasyon için Playwright (ya da Apple'ın `safaridriver`'ı) daha doğru araçtır. Sayfalarda işlem yapmak yerine kaynak gösteren araştırılmış cevaplar istiyorsan [Vane](https://github.com/ItzCrazyKns/Vane) gibi bir arama motoru daha uygundur.

| | safari-cli | Playwright | Vane |
|---|---|---|---|
| Ne | Safari'ni süren komut satırı aracı | Tarayıcı otomasyon kütüphanesi | Kendi sunucunda çalışan yapay zekâ cevap motoru |
| Kim yönetir | Claude Code, opencode, kabuğu olan her ajan | Senin betiklerin ya da Playwright MCP üzerinden bir ajan | Kendi LLM akışı; web arayüzünden ya da API'den |
| Tarayıcı | Senin açık Safari'n | Kendi başlattığı ayrı tarayıcı | Başsız Chromium (Playwright ile), yalnızca sayfa okumak için |
| Açık oturumların | Var | Yalnızca kayıtlı profil ya da oturum durumuyla | Yok |
| Tıklama, yazma, form | Var | Var | Yok, yalnızca okur |
| İletişim kutusu, dosya yükleme, iframe | Var (iframe eklentiyle) | Var | — |
| Ağ müdahalesi | Yok (yalnızca kayıt) | Var | — |
| Kaynak gösteren web araması | Açtığı siteler üzerinden | Yok | Var (SearxNG) |
| LLM | Ajanınki | Kendi LLM'i yok | Herhangi biri: Ollama, OpenAI, Claude, Gemini, Groq |
| Kurulum | Swift derlemesi, isteğe bağlı Safari eklentisi | npm ya da pip paketi | Docker imajı (SearxNG dahil) |
| Platform | macOS 14+ | macOS, Windows, Linux | Docker çalışan her yer |
| En uygun iş | Giriş yaptığın sitelerde günlük işler | Test, CI, tekrarlanabilir otomasyon | Kaynak gösteren, gizli araştırma soruları |

## Neden MCP yerine CLI

- Çıktı kabukta süzülüp kaydedilebilir (`| grep`, `| head`, `> sayfa.md`); uzun sayfaların konuşmaya girmesi gerekmez.
- Bilinen adımlar `&&` ile tek komutta çalışır; döngüler her sonucu modele göstermeden sayfaları tarar.
- Sunucu kaydı yok: komut çalıştırabilen her ajan kullanabilir, yeniden derleme bir sonraki komutta devreye girer.
- Kullanım kılavuzu yalnızca tarayıcı işlerinde yüklenen bir skill'dedir.

## Kurulum

macOS 14 ya da üstü ve Command Line Tools gerekir (Xcode yalnızca eklenti için).

```bash
git clone https://github.com/albayrakserdar8-gif/safari-cli.git
cd safari-cli && swift build -c release
ln -s "$PWD/.build/release/safari" /opt/homebrew/bin/safari     # ya da PATH'teki herhangi bir klasör
```

Arka plandaki bir süreç (daemon), sekme kimliklerini ve eklenti bağlantısını komutlar arasında tutar. İlk `safari` komutu onu başlatır (yaklaşık 0,2 sn), sonraki komutlar birkaç milisaniye sürer ve 30 dakika boşta kalınca kapanır. Yeniden derledikten sonraki ilk komut onu yeni sürümle yeniden başlatır. `safari status` durumunu gösterir, `safari stop` durdurur.

### Skill

`Skill/safari-browser/SKILL.md`, ajana komutları ve kuralları öğretir: kendi sekmesinde çalışmak, ekran görüntüsü yerine `read` kullanmak, gönderme, satın alma ya da silmeden önce sormak.

```bash
ln -s "$PWD/Skill/safari-browser" ~/.claude/skills/safari-browser            # Claude Code
ln -s "$PWD/Skill/safari-browser" ~/.config/opencode/skills/safari-browser   # opencode
```

Claude Code'da `~/.claude/settings.json` içindeki `permissions.allow` listesine `"Bash(safari:*)"` eklersen her komutta izin sorulmaz.

### Safari eklentisi (önerilen)

Eklentiyle Otomasyon ve "Allow JavaScript from Apple Events" izinleri gerekmez, iframe'ler okunur, HTTP durum kodu (404) bildirilir, ağ kaydı sayfa açıldığı anda başlar ve görünür sekmenin ekran görüntüsü için Ekran Kaydı izni gerekmez. Eklenti yoksa safari Apple Events'e döner.

Derlemek için Xcode gerekir:

1. Xcode > Settings > Accounts'ta bir Apple ID ekle (ücretsiz hesap yeterli).
2. `Extension/Safari MCP Bridge/Safari MCP Bridge.xcodeproj`'yi aç, iki hedef için de Signing & Capabilities altında Personal Team'ini seç.
3. Derle ve kur:
   ```bash
   Extension/build.sh --schedule
   ```
   `--schedule`, eklentiyi her hafta yeniden imzalayan bir görev ekler; ücretsiz hesap imzalarının süresi dolar.
4. Safari > Ayarlar > Uzantılar'da **Safari MCP Bridge**'i aç ve her web sitesinde izin ver. Gizli sekmeler için "Özel Dolaşımda İzin Ver"i de aç.

Daemon ve eklenti `127.0.0.1` üzerinden (47391–47399 portları) konuşur ve `~/.config/safari-mcp/token` dosyasındaki anahtarla birbirini doğrular; başka sayfalar ya da yerel programlar bağlanamaz. Eklenti safari-mcp'nin kullandığıyla aynıdır; ikisi aynı anda kurulu olabilir.

Safari eklentileri `file://` sayfalarına sokmaz; bu sayfalarda hep Apple Events kullanılır.

## İzinler

| İzin | Ne için | Eklentiyle | Eklentisiz |
|---|---|---|---|
| Safari eklentisi, her web sitesinde | Her şey | Gerekli | — |
| Otomasyon (Safari'yi denetleme) | Her şey | Gerekmez | Gerekli, ilk kullanımda sorulur |
| Safari > Ayarlar > Geliştirici > "Allow JavaScript from Apple Events" | `tabs` dışındaki her şey | Gerekmez | Gerekli |
| Ekran Kaydı | `shot` | Yalnızca sekme ekranda değilken | Gerekli |
| Erişilebilirlik | `--os`, yerel iletişim kutuları, tam ekran görüntüsü kırpma | İsteğe bağlı | İsteğe bağlı; gizli pencere için gerekli |

Bu izinler ajanı çalıştıran uygulamaya (terminaline) verilir. Geliştirici sekmesi yoksa Ayarlar > Gelişmiş > "Web geliştiricileri için özellikleri göster"i aç. "Allow JavaScript from Apple Events", Safari'yi denetleme izni olan her uygulama için geçerlidir.

## Kullanım

Ajana doğrudan söylemen yeterli:

- "Safari'de açık sekmelerimi listele."
- "Wikipedia'da Boğaziçi Köprüsü'nü ara, açılış yılını söyle."
- "Bu sayfadaki formu şu bilgilerle doldur ama gönderme."

## Komutlar

`safari help` hepsini listeler. `T` bir sekme kimliği (`t3`), `R` `read`'den gelen bir ref'tir (`e12`).

| Komut | İş |
|---|---|
| `tabs`, `open URL [--private]`, `T show`, `T close` | Sekmeleri listeler, (arka planda) açar, gösterir, kapatır |
| `T go URL\|back\|forward\|reload` | Yükler ve bekler |
| `T read`, `T text`, `T links` | Ref'li öğeler, markdown olarak sayfa, bağlantılar; `-q` ile arama, `--diff` ile yalnızca değişen |
| `T click R`, `dblclick`, `hover`, `fill`, `type`, `select`, `key`, `scroll`, `wait`, `upload`, `dialog` | Sayfada işlem yapar |
| `T js KOD` | Sayfada JavaScript çalıştırır (async işlev gövdesi, 15 sn sınırı; `-` stdin'den okur) |
| `T shot` | Görünüm alanının, bir öğenin ya da bölgenin JPEG'i; dosya yolunu yazar |
| `T logs` | Konsol ve ağ kayıtları; `--id` ile yanıt gövdesi |

Sonuçlar stdout'a gider; hatalar stderr'e, çıkış kodu 1 ile (yanlış kullanımda 2).

Nasıl davranır:

- **Ref'ler.** `read` her öğeye `e12` gibi bir ref verir, işlemler bunu kullanır. Ref'ler yalnızca o sayfa için geçerlidir.
- **Sekmeler.** Sekmeler `t3` gibi kalıcı kimlikler alır. Safari her işlemden önce sekmenin hâlâ beklenen sekme olduğunu doğrular; safari yanlış sekmede işlem yapmaz. Sekme kimliği verilmeyen komutlar son kullanılan sekmeye gider; yeni sekmeler arka planda açılır. `open --private` gizli pencere açar (sonraki gizli sekmeler ona eklenir); `tabs` bu sekmeleri `(private)` diye işaretler.
- **Sonuçlar.** İşlemler sayfa yüklenmesini bekler ve sayfa değişince `→ başlık | adres` bildirir. Yeni beliren metni, başarısız istekleri (4xx/5xx) ve değişen diğer alanları da yazar.
- **Girdi.** Tıklama ve yazma varsayılan olarak sayfa içi olaylardır: Safari arka planda kalır, imleç sende kalır. `--os`, sayfa içi olayları yok sayan siteler için gerçek fare/klavye olayı gönderir ve Safari'yi kısa süre öne getirir.
- **İletişim kutuları.** `alert` onaylanır; `confirm`/`prompt`, önceden `dialog` ya da `click --answer` ile yanıt verilmediyse reddedilir. Her biri sonuçta bildirilir. Yalnızca safari'nin çalıştığı sekmeler etkilenir; kendi gezinmende kutular normal çıkar.
- **Ekran görüntüsü.** Safari başka bir masaüstündeyse ya da tam ekrandaysa yaklaşık bir saniye öne getirilir, sonra önceki uygulamaya dönülür.

## Kaynak kullanımı

Tek bir Mac'te ölçüldü:

| | |
|---|---|
| Skill | yaklaşık 2.800 token, yalnızca tarayıcı işlerinde yüklenir (MCP sürümü her oturumda yaklaşık 875 token araç şeması gönderiyordu, skill'i de ayrıca) |
| Varsayılan `read` | yaklaşık 500 token (Wikipedia ana sayfa), 1.100 (Hacker News) |
| Çağrı süresi | `read` 7–60 ms, işlemler 170–470 ms, `shot` 0,9–2,1 sn; komut başına yaklaşık 10 ms daha, daemon'u başlatan ilk komutta 0,2 sn |
| Bellek | Boşta 9 MB, kullanımdan sonra yaklaşık 34 MB |
| Boşta CPU | 0 |

Tek bir daemon bütün ajanlara ve oturumlara hizmet eder; 30 dakika boşta kalınca kapanır.

## Sınanma durumu

Sayfa motoru safari-mcp'de, Claude Haiku ajanlarının araçları yalnızca açıklamalarından kullanarak gerçek görevler yaptığı altı turda sınandı: Wikipedia, Hacker News, MDN, GitHub, DuckDuckGo, demo mağazalarda hesap açma, sepet ve ödeme (automationexercise, Toolshop/Angular, saucedemo/React, demowebshop), the-internet ve TodoMVC. Her turda bulunan hatalar düzeltildi; son turlarda bütün görevler, işlemler için `js` ya da `os: true`'ya başvurmadan doğru bitti ve en zor görevlerde çağrı sayısı yaklaşık yarıya indi. CLI ardından, yalnızca skill'i bilen ve tek bir daemon'u paylaşan sekiz paralel Claude Haiku ajanıyla bir turda sınandı: Wikipedia, Hacker News, MDN site içi arama, GitHub (sürüm, issue arama, dosya ağacı), ekran görüntülü DuckDuckGo, saucedemo ödeme akışı, the-internet bileşenleri ve TodoMVC. Sekizi de `--os` kullanmadan, 7–37 komutta doğru bitti. `js` yalnızca CLI'nin göstermediği metni okumak için gerekti: tam bir Hacker News yorumu, bir öznitelikte duran tarih yılı ve bir GitHub kod görünümü. Bunlardan ilk ikisi ardından düzeltildi: düzen tabloları ve `<article>` sonuç listeleri artık tam okunuyor, tek bir alanda `read --ref` bütün değeri gösteriyor. Sekiz zor görevlik ikinci tur (tarih seçicili, otomatik tamamlamalı ve React select'li demoqa formu; Toolshop/Angular sepeti; the-internet'te TinyMCE, iç içe frame'ler, yükleme, hover, sonsuz kaydırma ve shadow DOM; books.toscrape'te sayfalı tarama ve dosyaya yazma; beş makalelik Wikipedia karşılaştırması; automationexercise'da kayıt, sipariş ve hesap silme; GitHub'da sürüm notu, kaynak kod, birleştirilmiş PR ve katkıcılar; Hacker News ve dış makaleler), o sırada komutu olmayan sağ tık dışında doğru bitti. Ardından `click --right`, yalnızca simgeden oluşan butonlar için adlar (bir ajan "btn" diye listelenen bir butonla sepetten ürün silmişti), `open --id-only`, düz metin `js` sonuçları ve daha açıklayıcı `select` hataları eklendi. Üçüncü tur başka alanları kapsadı: aynı anda birden çok sekme, gizli pencere (oturum sızmadı), hata ayıklama (JS hataları, kırık görseller, 404/500, yanıt gövdeleri), Quill ve CodeMirror editörleri, slider ve sürükle-bırak, Türkçe siteler (karakter bozulmadı), ekran görüntüsünden okunan canvas içeriği ve hatalı kullanım (bilinmeyen kimlik ve ref, erişilemeyen adres, zaman aşımı, yanlış argüman). Ardından `drag`, yüklenemeyen gezinme ve `js` zaman aşımı için çıkış kodu 1, çakışan öğe argümanları için kullanım hatası ve daemon yeniden başlasa da korunan sekme kimlikleri eklendi. Zengin metin biçimlendirme kısayolları (`cmd+b`, shift+ok ile seçme) `--os` olmadan hâlâ çalışmıyor.

Sınama tek bir Mac'te (macOS 27) yapıldı, geniş bir site yelpazesinde denenmedi.

## Sınırlar

- Kapalı shadow DOM okunmaz. En çok 8 iframe okunur; eklentisiz yalnızca aynı kökenli ve CSP'si izin veren çerçeveler.
- Bazı siteler sayfa içi olayları yok sayar; `hover` yalnızca okunabilen CSS `:hover` kurallarını taklit eder. Bu durumlarda `--os` kullan.
- Katı CSP'li sitelerde (GitHub, Gmail) eklenti `js`'i ayrı bir ortamda çalıştırır: DOM'u görür, sayfanın JavaScript değişkenlerini görmez.
- HTTP durum kodu yalnızca eklentiyle bildirilir.
- Eklentisiz modda kayıtlar safari'nin sayfaya ilk girdiği andan başlar; ondan önce açılan iletişim kutuları çağrıları 20 sn bekletir (Erişilebilirlik ile yanıtlanabilir).
- Ajanlar tek bir daemon'u paylaşır; birden fazla yeni sekme açıkken sekme kimliğini başa yazmalıdır.
- Eklentisiz modda, bir sekme başka bir siteye giderken aynı anda sekme açılıp kapanırsa sekme kaybolabilir; safari tahmin etmek yerine hata döner.
- `text` kipi bağlantı metinlerini ve veri tablosu hücrelerini kırpar (200 karakter, 60 satır); karmaşık tablolarda düzen bozulabilir. Sayfa düzeni için kullanılan tablolar metin olarak okunur.
- Tam tarayıcı denetimi (gerçek girdi, bütün ağ trafiği) Safari'nin Web Inspector protokolünü gerektirir; kendi Safari'nde bunu yalnızca Apple imzalı uygulamalar kullanabilir. Apple'ın `safaridriver --mcp`'si bunu sekmelerini ve çerezlerini görmeyen ayrı, temiz bir oturumda sunar.

## Geliştirme

```bash
Tests/smoke.sh                                             # CLI ve daemon testi, Safari izni gerekmez
(cd Tests && python3 -m http.server 8765 --bind 127.0.0.1)  # test sayfalarını sun
```

Elle sınama için `http://127.0.0.1:8765/fixture.html`'i `safari open` ile aç (form, iletişim kutuları, gecikmeli öğe, tablo, fetch, iframe).

## Lisans

[MIT](LICENSE)
