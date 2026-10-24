# safari-mcp

[English](README.md)

Claude Code'un senin açık Safari'ni, açık oturumlarınla kullanmasını sağlayan yerel bir MCP sunucusu. Tek bir Swift ikili dosyası, bağımlılığı yok.

Kuruluysa isteğe bağlı **Safari MCP Bridge** eklentisi üzerinden, değilse Apple Events üzerinden çalışır.

Anthropic ile bağlantısı olmayan bağımsız bir projedir. Claude in Chrome yalnızca Chromium tarayıcılarda çalıştığı için yazıldı.

## Ne zaman kullanılır

Giriş yaptığın sitelerde günlük işler için uygundur: okuma, arama, form doldurma, gezinme. Web uygulaması testi, CI ve tekrarlanabilir otomasyon için Playwright (ya da Apple'ın `safaridriver`'ı) daha doğru araçtır.

| | safari-mcp | Playwright |
|---|---|---|
| Tarayıcı | Senin açık Safari'n ve oturumların | Kendi başlattığı ayrı tarayıcı |
| Girdi | Sayfa içi olaylar; istenirse gerçek fare/klavye | Tarayıcı düzeyinde gerçek olaylar |
| İletişim kutusu, dosya yükleme | Var | Var |
| iframe | Eklentiyle var | Var |
| Ağ müdahalesi | Yok | Var |
| Platform | macOS 14+ | macOS, Windows, Linux |

## Kurulum

macOS 14 ya da üstü ve Command Line Tools gerekir (Xcode yalnızca eklenti için).

```bash
git clone https://github.com/sadopc/safari-mcp.git
cd safari-mcp && swift build -c release
claude mcp add --scope user safari -- "$PWD/.build/release/safari-mcp"
```

Klasörü taşırsan `claude mcp add` komutunu yeniden çalıştır. Yeniden derledikten sonra yeni sürüm için yeni bir Claude Code oturumu aç.

### Skill (önerilen)

`Skill/safari-browser/SKILL.md`, Claude'a araçları doğru kullanmayı öğretir: kendi sekmesinde çalışmak, ekran görüntüsü yerine `read` kullanmak, gönderme, satın alma ya da silmeden önce sormak.

```bash
ln -s "$PWD/Skill/safari-browser" ~/.claude/skills/safari-browser
```

### Safari eklentisi (önerilen)

Eklentiyle Otomasyon ve "Allow JavaScript from Apple Events" izinleri gerekmez, iframe'ler okunur, HTTP durum kodu (404) bildirilir, ağ kaydı sayfa açıldığı anda başlar ve görünür sekmenin ekran görüntüsü için Ekran Kaydı izni gerekmez. Eklenti yoksa sunucu Apple Events'e döner.

Derlemek için Xcode gerekir:

1. Xcode > Settings > Accounts'ta bir Apple ID ekle (ücretsiz hesap yeterli).
2. `Extension/Safari MCP Bridge/Safari MCP Bridge.xcodeproj`'yi aç, iki hedef için de Signing & Capabilities altında Personal Team'ini seç.
3. Derle ve kur:
   ```bash
   Extension/build.sh --schedule
   ```
   `--schedule`, eklentiyi her hafta yeniden imzalayan bir görev ekler; ücretsiz hesap imzalarının süresi dolar.
4. Safari > Ayarlar > Uzantılar'da **Safari MCP Bridge**'i aç ve her web sitesinde izin ver.

Sunucu ve eklenti `127.0.0.1` üzerinden (47391–47399 portları) konuşur ve `~/.config/safari-mcp/token` dosyasındaki anahtarla birbirini doğrular; başka sayfalar ya da yerel programlar bağlanamaz.

Safari eklentileri `file://` sayfalarına sokmaz; bu sayfalarda hep Apple Events kullanılır.

## İzinler

| İzin | Ne için | Eklentiyle | Eklentisiz |
|---|---|---|---|
| Safari eklentisi, her web sitesinde | Her şey | Gerekli | — |
| Otomasyon (Safari'yi denetleme) | Her şey | Gerekmez | Gerekli, ilk kullanımda sorulur |
| Safari > Ayarlar > Geliştirici > "Allow JavaScript from Apple Events" | `tabs` dışındaki araçlar | Gerekmez | Gerekli |
| Ekran Kaydı | `screenshot` | Yalnızca sekme ekranda değilken | Gerekli |
| Erişilebilirlik | `os: true`, yerel iletişim kutuları, tam ekran görüntüsü kırpma | İsteğe bağlı | İsteğe bağlı |

Geliştirici sekmesi yoksa Ayarlar > Gelişmiş > "Web geliştiricileri için özellikleri göster"i aç. "Allow JavaScript from Apple Events", Safari'yi denetleme izni olan her uygulama için geçerlidir.

## Kullanım

Claude Code'a doğrudan söylemen yeterli:

- "Safari'de açık sekmelerimi listele."
- "Wikipedia'da Boğaziçi Köprüsü'nü ara, açılış yılını söyle."
- "Bu sayfadaki formu şu bilgilerle doldur ama gönderme."

## Araçlar

| Araç | İş |
|---|---|
| `tabs` | Sekmeleri listeler, açar, kapatır, seçer |
| `navigate` | URL'ye gider ya da `back` / `forward` / `reload`; yüklenmeyi bekler |
| `read` | Sayfayı okur: etkileşimli öğeler (varsayılan), `all`, `text` (markdown), `links`; `query` ile arama; `diff` ile yalnızca değişen |
| `act` | `click`, `dblclick`, `hover`, `type`, `fill`, `select`, `key`, `scroll`, `wait`, `upload`, `dialog` |
| `js` | Sayfada JavaScript çalıştırır (async işlev gövdesi, 15 sn sınırı) |
| `screenshot` | Görünüm alanının, bir öğenin ya da bölgenin JPEG görüntüsü |
| `logs` | Konsol ve ağ kayıtları; `id` ile yanıt gövdesi |
| `batch` | Birden çok çağrıyı tek turda çalıştırır |

Nasıl davranır:

- **Ref'ler.** `read` her öğeye `e12` gibi bir ref verir, `act` bunu kullanır. Ref'ler yalnızca o sayfa için geçerlidir.
- **Sekmeler.** Sekmeler `t3` gibi kalıcı kimlikler alır. Safari her işlemden önce sekmenin hâlâ beklenen sekme olduğunu doğrular; sunucu yanlış sekmede işlem yapmaz. `tab` verilmeyen çağrılar son kullanılan sekmeye gider; yeni sekmeler arka planda açılır.
- **Sonuçlar.** İşlemler sayfa yüklenmesini bekler ve sayfa değişince `→ başlık | adres` bildirir. Yeni beliren metni, başarısız istekleri (4xx/5xx) ve değişen diğer alanları da yazar.
- **Girdi.** Tıklama ve yazma varsayılan olarak sayfa içi olaylardır: Safari arka planda kalır, imleç sende kalır. `os: true`, sayfa içi olayları yok sayan siteler için gerçek fare/klavye olayı gönderir ve Safari'yi kısa süre öne getirir.
- **İletişim kutuları.** `alert` onaylanır; `confirm`/`prompt`, önceden `act dialog` ile yanıt verilmediyse reddedilir. Her biri sonuçta bildirilir. Yalnızca sunucunun çalıştığı sekmeler etkilenir; kendi gezinmende kutular normal çıkar.
- **Ekran görüntüsü.** Safari başka bir masaüstündeyse ya da tam ekrandaysa yaklaşık bir saniye öne getirilir, sonra önceki uygulamaya dönülür.

## Kaynak kullanımı

Tek bir Mac'te ölçüldü:

| | |
|---|---|
| Araç şemaları | yaklaşık 875 token |
| Varsayılan `read` | yaklaşık 500 token (Wikipedia ana sayfa), 1.100 (Hacker News) |
| Çağrı süresi | `read` 7–60 ms, `act` 170–470 ms, `screenshot` 0,9–2,1 sn |
| Bellek | Boşta 9 MB, kullanımdan sonra yaklaşık 34 MB |
| Boşta CPU | 0 |

Her Claude Code oturumu kendi `safari-mcp` sürecini çalıştırır; süreç oturumla birlikte kapanır.

## Sınanma durumu

Claude Haiku ajanlarının araçları yalnızca açıklamalarından kullanarak gerçek görevler yaptığı altı turda sınandı: Wikipedia, Hacker News, MDN, GitHub, DuckDuckGo, demo mağazalarda hesap açma, sepet ve ödeme (automationexercise, Toolshop/Angular, saucedemo/React, demowebshop), the-internet ve TodoMVC. Her turda bulunan hatalar düzeltildi; son turlarda bütün görevler, işlemler için `js` ya da `os: true`'ya başvurmadan doğru bitti ve en zor görevlerde çağrı sayısı yaklaşık yarıya indi.

Sınama tek bir Mac'te (macOS 27) yapıldı, geniş bir site yelpazesinde denenmedi.

## Sınırlar

- Kapalı shadow DOM okunmaz. En çok 8 iframe okunur; eklentisiz yalnızca aynı kökenli ve CSP'si izin veren çerçeveler.
- Bazı siteler sayfa içi olayları yok sayar; `hover` yalnızca okunabilen CSS `:hover` kurallarını taklit eder. Bu durumlarda `os: true` kullan.
- Katı CSP'li sitelerde (GitHub, Gmail) eklenti `js`'i ayrı bir ortamda çalıştırır: DOM'u görür, sayfanın JavaScript değişkenlerini görmez.
- HTTP durum kodu yalnızca eklentiyle bildirilir.
- Eklentisiz modda kayıtlar sunucunun sayfaya ilk girdiği andan başlar; ondan önce açılan iletişim kutuları çağrıları 20 sn bekletir (Erişilebilirlik ile yanıtlanabilir).
- Aynı sunucuyu paylaşan ajanlar, birden fazla yeni sekme açıkken `tab`'ı açıkça vermelidir.
- Eklentisiz modda, bir sekme başka bir siteye giderken aynı anda sekme açılıp kapanırsa sekme kaybolabilir; sunucu tahmin etmek yerine hata döner.
- `text` kipi bağlantı metinlerini ve tablo hücrelerini kırpar; karmaşık tablolarda düzen bozulabilir.
- Tam tarayıcı denetimi (gerçek girdi, bütün ağ trafiği) Safari'nin Web Inspector protokolünü gerektirir; kendi Safari'nde bunu yalnızca Apple imzalı uygulamalar kullanabilir. Apple'ın `safaridriver --mcp`'si bunu sekmelerini ve çerezlerini görmeyen ayrı, temiz bir oturumda sunar.

## Geliştirme

```bash
Tests/smoke.sh                                             # protokol testi, Safari izni gerekmez
(cd Tests && python3 -m http.server 8765 --bind 127.0.0.1)  # test sayfalarını sun
```

Elle sınama için `http://127.0.0.1:8765/fixture.html`'i `tabs new` ile aç (form, iletişim kutuları, gecikmeli öğe, tablo, fetch, iframe).

## Lisans

[MIT](LICENSE)
