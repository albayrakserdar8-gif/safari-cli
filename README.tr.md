# safari-cli

[English](README.md)

Kod ajanlarının (Claude Code, opencode, kabuğu olan herhangi bir ajan) senin açık Safari'ni, açık oturumlarınla kullanmasını sağlayan bir `safari` komutu. Tek bir Swift ikili dosyası, bağımlılığı yok. [safari-mcp](https://github.com/sadopc/safari-mcp)'den çatallandı: aynı motor, MCP sunucusu yerine bir CLI ve bir skill.

Safari ile zorunlu **Safari CLI Bridge** eklentisi üzerinden konuşur: eklenti her sekmeye ve çerçeveye ulaşır, ağ trafiğine de müdahale edebilir.

Anthropic ile bağlantısı olmayan bağımsız bir projedir. Claude in Chrome yalnızca Chromium tarayıcılarda çalıştığı için yazıldı.

## Ne zaman kullanılır

Giriş yaptığın sitelerde günlük işler için uygundur: okuma, arama, form doldurma, gezinme. Web uygulaması testi, CI ve tekrarlanabilir otomasyon için Playwright (ya da Apple'ın `safaridriver`'ı) daha doğru araçtır; [playwright-cli](https://github.com/microsoft/playwright-cli) aynısını ayrı bir tarayıcıda bir ajana sunar. Sayfalarda işlem yapmak yerine kaynak gösteren araştırılmış cevaplar istiyorsan [Vane](https://github.com/ItzCrazyKns/Vane) gibi bir arama motoru daha uygundur.

| | safari-cli | Playwright | playwright-cli | Vane |
|---|---|---|---|---|
| Ne | Safari'ni süren komut satırı aracı | Tarayıcı otomasyon kütüphanesi | Playwright'ın kodlama ajanları için komut satırı aracı | Kendi sunucunda çalışan yapay zekâ cevap motoru |
| Kim yönetir | Claude Code, opencode, kabuğu olan her ajan | Senin betiklerin ya da Playwright MCP üzerinden bir ajan | Claude Code, Copilot, kabuğu olan her ajan (skill'i üzerinden) | Kendi LLM akışı; web arayüzünden ya da API'den |
| Tarayıcı | Senin açık Safari'n | Kendi başlattığı ayrı tarayıcı | Kendi Chromium, Firefox ya da WebKit'i (varsayılan başsız) ya da bağlandığı Chrome/Edge | Başsız Chromium (Playwright ile), yalnızca sayfa okumak için |
| Açık oturumların | Var | Yalnızca kayıtlı profil ya da oturum durumuyla | Kalıcı profille ya da Chrome'una bağlanarak | Yok |
| Tıklama, yazma, form | Var | Var | Var | Yok, yalnızca okur |
| İletişim kutusu, dosya yükleme, iframe | Var | Var | Var | — |
| Ağ müdahalesi | Sekme başına: fetch/XHR'yi taklit etme, engelleme, yönlendirme ya da başlıklarını değiştirme. `--global`: her istek (betikler, stiller, görseller, çerçeveler, sayfanın kendisi), bütün sekmelerde (`route`) | Var | Var (`route`) | — |
| Çerezler, kayıtlı oturum, PDF | Var (`cookies`, `state`, `pdf`) | Var | Var | — |
| Kaynak gösteren web araması | Açtığı siteler üzerinden | Yok | Açtığı siteler üzerinden | Var (SearxNG) |
| LLM | Ajanınki | Kendi LLM'i yok | Ajanınki | Herhangi biri: Ollama, OpenAI, Claude, Gemini, Groq |
| Kurulum | Swift derlemesi ve Safari eklentisi (Xcode gerekir) | npm ya da pip paketi | npm paketi (Node 18+), skill `install --skills` ile | Docker imajı (SearxNG dahil) |
| Platform | macOS 14+ | macOS, Windows, Linux | macOS, Windows, Linux | Docker çalışan her yer |
| En uygun iş | Giriş yaptığın sitelerde günlük işler | Test, CI, tekrarlanabilir otomasyon | Ayrı bir tarayıcıda ajanla test ve otomasyon | Kaynak gösteren, gizli araştırma soruları |

## Neden MCP yerine CLI

- Çıktı kabukta süzülüp kaydedilebilir (`| grep`, `| head`, `> sayfa.md`); uzun sayfaların konuşmaya girmesi gerekmez.
- Bilinen adımlar `&&` ile tek komutta çalışır; döngüler her sonucu modele göstermeden sayfaları tarar.
- Sunucu kaydı yok: komut çalıştırabilen her ajan kullanabilir, yeniden derleme bir sonraki komutta devreye girer.
- Kullanım kılavuzu yalnızca tarayıcı işlerinde yüklenen bir skill'dedir.

## Nasıl çalışır

`safari` fiili çözümler, arka plandaki daemon'a unix soket üzerinden tek bir istek gönderir ve yanıtı yazar. Daemon, Safari'yi eklentinin WebSocket'i üzerinden sürer; sayfada iki enjekte betikle çalışır: biri sayfanın kendi dünyasında (konsol ve fetch kancaları, iletişim kutuları, `js`, route'lar), diğeri eklentinin izole dünyasında (ref'ler, okuma, işlemler). `docs/architecture.png` bütün resmi gösterir; `docs/architecture.excalidraw` düzenlenebilir sahnesidir.

## Kurulum

macOS 14 ya da üstü, Command Line Tools ve Safari eklentisi için Xcode gerekir.

```bash
git clone https://github.com/albayrakserdar8-gif/safari-cli.git
cd safari-cli && make install
```

`make install` programı derler, `/opt/homebrew/bin`'e (ya da `/usr/local/bin`'e; başka bir yer için `PREFIX=`) bağlar ve skill'i Claude Code ile opencode için bağlar. `make uninstall` bağlantıları kaldırır.

Arka plandaki bir süreç (daemon), sekme kimliklerini ve eklenti bağlantısını komutlar arasında tutar. İlk `safari` komutu onu başlatır (yaklaşık 0,2 sn), sonraki komutlar birkaç milisaniye sürer ve 30 dakika boşta kalınca kapanır. Yeniden derledikten sonraki ilk komut onu yeni sürümle yeniden başlatır. `safari status` durumunu gösterir, `safari stop` durdurur.

### Skill

`Skill/safari-browser/SKILL.md`, ajana temel komutları ve kuralları öğretir: kendi sekmesinde çalışmak, ekran görüntüsü yerine `read` kullanmak, gönderme, satın alma ya da silmeden önce sormak. Ayrıntılar (formlar, tarama, `js`, çerez ve depolama, taklit, kayıt) ajanın yalnızca gerektiğinde okuduğu `references/` dosyalarındadır. `make install` onu `~/.claude/skills` ve `~/.config/opencode/skills` içine bağlar.

Claude Code'da `~/.claude/settings.json` içindeki `permissions.allow` listesine `"Bash(safari:*)"` eklersen her komutta izin sorulmaz.

### Safari eklentisi (zorunlu)

Her komut eklentiden geçer; eklenti yoksa komutlar, nasıl açılacağını söyleyen bir hatayla durur. Bağlı olup olmadığını `safari status` gösterir.

Derlemek için Xcode gerekir:

1. Xcode > Settings > Accounts'ta bir Apple ID ekle (ücretsiz hesap yeterli).
2. `Extension/Safari MCP Bridge/Safari MCP Bridge.xcodeproj`'yi aç, iki hedef için de Signing & Capabilities altında Personal Team'ini seç.
3. Derle ve kur:
   ```bash
   Extension/build.sh --schedule
   ```
   `--schedule`, eklentiyi her hafta yeniden imzalayan bir görev ekler; ücretsiz hesap imzalarının süresi dolar.
4. Safari > Ayarlar > Uzantılar'da **Safari CLI Bridge**'i aç ve her web sitesinde izin ver. Gizli sekmeler için "Özel Dolaşımda İzin Ver"i de aç. Yeni bir izin ekleyen güncellemeden sonra (Kasım 2026'da çerezler ve `route` için ağ kuralları) Safari eklentiyi sen yeniden açana kadar kapatabilir; önceden açık sayfaları yenile.

Daemon ve eklenti `127.0.0.1` üzerinden (47391–47399 portları) konuşur ve `~/.config/safari-mcp/token` dosyasındaki anahtarla birbirini doğrular; başka sayfalar ya da yerel programlar bağlanamaz. Eklenti safari-mcp'nin kullandığıyla aynıdır; ikisi aynı anda kurulu olabilir. `route`, taklit yanıtları `127.0.0.1` üzerindeki ikinci bir dinleyiciden (47401–47409 portları), tahmin edilemeyen yollardan verir.

Safari eklentileri `file://` sayfalarına sokmaz, bu yüzden safari onları reddeder; klasörü HTTP ile sun (`python3 -m http.server`).

## İzinler

| İzin | Ne için | Gerekli mi |
|---|---|---|
| Safari eklentisi, her web sitesinde | Her şey | Gerekli |
| Ekran Kaydı | Ekranda olmayan sekmenin `shot`'ı | Yalnızca o zaman |
| Erişilebilirlik | `--os`, yerel iletişim kutuları, tam ekran görüntüsü kırpma, gizli pencere açma | İsteğe bağlı |

Bu izinler ajanı çalıştıran uygulamaya (terminaline) verilir. Otomasyon ve "Allow JavaScript from Apple Events" artık kullanılmaz.

## Kullanım

Ajana doğrudan söylemen yeterli:

- "Safari'de açık sekmelerimi listele."
- "Wikipedia'da Boğaziçi Köprüsü'nü ara, açılış yılını söyle."
- "Bu sayfadaki formu şu bilgilerle doldur ama gönderme."

## Komutlar

`safari help` hepsini listeler. `T` bir sekme kimliği (`t3`), `R` `read`'den gelen bir ref'tir (`e12`).

| Komut | İş |
|---|---|
| `tabs`, `open URL [--private\|--window]`, `T show`, `T close`, `close --agents` | Sekmeleri listeler, (arka planda ya da kendi penceresinde) açar, gösterir, kapatır; `--agents` ekranda olmayan bütün ajan sekmelerini kapatır |
| `T go URL\|back\|forward\|reload [--delay S]` | Yükler ve bekler |
| `T read`, `T text`, `T links` | Ref'li öğeler, markdown olarak sayfa, bağlantılar; `-q` ile arama (`-q '/regex/i'` de olur), `--diff` ile yalnızca değişen |
| `T table [--rows CSS] [--json]` | Bir tabloyu ya da kart listesini TSV/JSON olarak verir; her satırın bağlantısı ve `data-id`'si de eklenir; `--rows` verilmezse tekrar eden kartları kendisi bulur |
| `T crawl [--next METİN] [--pages N]` | Sayfalı bir listenin her sayfasında `table` çalıştırır, "Sonraki"yi izler; sonuçları birleştirir, tekrarları atar |
| `rate [SİTE [S\|off]]` | Site başına sayfa yüklemeleri arası saniye (`rate example.com 8-14`); kalıcıdır |
| `T click R`, `dblclick`, `hover`, `fill`, `type`, `select`, `key`, `scroll`, `wait`, `upload`, `drop`, `dialog` | Sayfada işlem yapar (`drop` dosyaları bir bırakma alanına bırakır) |
| `T locator R`, `T highlight R` | R için sayfa yüklemelerinden sonra da geçerli bir CSS seçici; senin ekranında R'nin çevresine çerçeve |
| `T js KOD [R]` | Sayfada JavaScript çalıştırır (async işlev gövdesi, 15 sn sınırı; `-` stdin'den okur); koddan sonra verilen öğe kodda `el` olur |
| `T shot [--full]` | Görünüm alanının, bir öğenin, bir bölgenin ya da bütün sayfanın JPEG'i; dosya yolunu yazar |
| `T resize G Y` | Görünüm alanı boyutu; yalnızca ajan sekmelerinden oluşan bir pencerede |
| `T route DESEN`, `T unroute` | Sekmenin fetch/XHR isteklerini taklit eder (`--status`, `--body`, `--resp-header`, `--delay`), `--block` ile engeller, `--redirect` ile yönlendirir ya da `--header` ile başlıklarını değiştirir. `--global` aynısını her tür istek için, bütün sekmelerde yapar; `--doc` sayfanın kendisini ekler |
| `T storage`, `T cookies` | localStorage/sessionStorage'ı ya da sitenin çerezlerini listeler, okur, yazar, siler (HttpOnly çerezler de) |
| `T state save\|load DOSYA` | Sitenin çerezlerini ve web depolamasını bir dosyaya (izin 0600) yazar ve geri yükler |
| `T check R`, `T uncheck R` | Onay kutusunu ya da radyo düğmesini ayarlar; tekrar çalıştırmak güvenlidir |
| `T pdf` | Sayfayı, DOM'unun anlık kopyasından arka planda üretilen sayfalı bir PDF olarak kaydeder |
| `T record`, `T record --stop` | Bir sekmede yaptıklarını kaydeder, tekrar oynatılacak `safari` komutları olarak yazar |
| `T logs` | Konsol ve ağ kayıtları; `--id` ile yanıt gövdesi |
| `downloads [--wait]` | Safari'nin listesinden son indirmeler; `--wait` bitmelerini bekler, sonra kaydedilen yolları yazar |

Sonuçlar stdout'a gider; hatalar stderr'e, çıkış kodu 1 ile (yanlış kullanımda 2). Uzun sonuçlar kırpılır (`--max N`, hepsi için `--max 0`); `… N more chars; --offset K` gibi notlar ve satır sayıları stderr'e gider, böylece yönlendirilen veri temiz kalır. `-o DOSYA`, `read`, `text`, `links`, `table` ve `js` sonucunun tamamını dosyaya yazar.

Nasıl davranır:

- **Ref'ler.** `read` her öğeye `e12` gibi bir ref verir, işlemler bunu kullanır. Ref'ler yalnızca o sayfa için geçerlidir.
- **Sekmeler.** Sekmeler `t3` gibi kalıcı kimlikler alır. Safari her işlemden önce sekmenin hâlâ beklenen sekme olduğunu doğrular; safari yanlış sekmede işlem yapmaz. Sekme kimliği verilmeyen komutlar son kullanılan sekmeye gider; yeni sekmeler arka planda açılır. `open --private` gizli pencere açar (sonraki gizli sekmeler ona eklenir); `tabs` bu sekmeleri `(private)` diye işaretler. `open` ile açılan sekmeler `(agent)` diye işaretlenir; 30 dakika boyunca hiçbir komut kullanmazsa daemon onu kapatır (senin pencerelerinden birinde görünen sekme ve `show` ile öne getirilen sekme hariç). Ortamdaki `SAFARI_TAB=t3`, sekme belirtmeyen komutlar için t3'ü kullandırır.
- **Zengin metin.** `select R "kelimeler"` bir alanda ya da editörde metni seçer; ardından `key cmd+b R` (ya da `cmd+i`, `cmd+u`) onu biçimlendirir. Bu, odak alamayan frame'lerdeki editörlerde de çalışır.
- **Sonuçlar.** İşlemler sayfa yüklenmesini bekler ve sayfa değişince `→ başlık | adres` bildirir. Yeni beliren metni, başarısız istekleri (4xx/5xx) ve değişen diğer alanları da yazar.
- **Girdi.** Tıklama ve yazma varsayılan olarak sayfa içi olaylardır: Safari arka planda kalır, imleç sende kalır. `--os`, sayfa içi olayları yok sayan siteler için gerçek fare/klavye olayı gönderir ve Safari'yi kısa süre öne getirir.
- **İletişim kutuları.** `alert` onaylanır; `confirm`/`prompt`, önceden `dialog` ya da `click --answer` ile yanıt verilmediyse reddedilir. Her biri sonuçta bildirilir. Yalnızca safari'nin çalıştığı sekmeler etkilenir; kendi gezinmende kutular normal çıkar.
- **Ekran görüntüsü.** Safari başka bir masaüstündeyse ya da tam ekrandaysa yaklaşık bir saniye öne getirilir, sonra önceki uygulamaya dönülür.
- **Bot doğrulamaları.** `open`, `go` ve `wait --load` doğrulama sayfalarını (Cloudflare "Just a moment…"/"Bir dakika lütfen", PerimeterX, captcha) tanır ve kendiliğinden geçmeleri için en çok 20 sn bekler; sonuç gerçek sayfayı anlatır. Geçmeyen bir doğrulama, sekmeyi adıyla anan bir hatadır: sekmeyi göster, çöz, sonra `wait --load`.
- **Hız sınırı.** `safari rate SİTE 8-14` (ya da `go --delay 8-14`) bir sitedeki sayfa yüklemelerini aralıklandırır. Daemon zaman dilimi dağıtır, her komut kendi dilimini kendisi bekler; böylece aynı sitedeki birkaç ajan sıraya girer ve daemon serbest kalır. Bir bot doğrulaması ya da 429/503 yanıtı o siteyi oturum boyunca yavaşlatır (kural yoksa 4-8 sn, varsa iki katı).

## Kaynak kullanımı

Tek bir Mac'te ölçüldü:

| | |
|---|---|
| Skill | yaklaşık 1.680 token, yalnızca tarayıcı işlerinde yüklenir; sekiz `references/` dosyası (her biri 400-850 token) yalnızca iş gerektirince okunur (MCP sürümü her oturumda yaklaşık 875 token araç şeması gönderiyordu, skill'i de ayrıca) |
| Varsayılan `read` | yaklaşık 500 token (Wikipedia ana sayfa), 1.100 (Hacker News) |
| Çağrı süresi | `read` 7–60 ms, işlemler 170–470 ms, `shot` 0,9–2,1 sn; komut başına yaklaşık 10 ms daha, daemon'u başlatan ilk komutta 0,2 sn |
| Bellek | Boşta 9 MB, kullanımdan sonra yaklaşık 34 MB |
| Boşta CPU | 0 |

Tek bir daemon bütün ajanlara ve oturumlara hizmet eder; 30 dakika boşta kalınca kapanır.

## Sınanma durumu

Sayfa motoru safari-mcp'de, Claude Haiku ajanlarının araçları yalnızca açıklamalarından kullanarak gerçek görevler yaptığı altı turda sınandı: Wikipedia, Hacker News, MDN, GitHub, DuckDuckGo, demo mağazalarda hesap açma, sepet ve ödeme (automationexercise, Toolshop/Angular, saucedemo/React, demowebshop), the-internet ve TodoMVC. Her turda bulunan hatalar düzeltildi; son turlarda bütün görevler, işlemler için `js` ya da `os: true`'ya başvurmadan doğru bitti ve en zor görevlerde çağrı sayısı yaklaşık yarıya indi. CLI ardından, yalnızca skill'i bilen ve tek bir daemon'u paylaşan sekiz paralel Claude Haiku ajanıyla bir turda sınandı: Wikipedia, Hacker News, MDN site içi arama, GitHub (sürüm, issue arama, dosya ağacı), ekran görüntülü DuckDuckGo, saucedemo ödeme akışı, the-internet bileşenleri ve TodoMVC. Sekizi de `--os` kullanmadan, 7–37 komutta doğru bitti. `js` yalnızca CLI'nin göstermediği metni okumak için gerekti: tam bir Hacker News yorumu, bir öznitelikte duran tarih yılı ve bir GitHub kod görünümü. Bunlardan ilk ikisi ardından düzeltildi: düzen tabloları ve `<article>` sonuç listeleri artık tam okunuyor, tek bir alanda `read --ref` bütün değeri gösteriyor. Sekiz zor görevlik ikinci tur (tarih seçicili, otomatik tamamlamalı ve React select'li demoqa formu; Toolshop/Angular sepeti; the-internet'te TinyMCE, iç içe frame'ler, yükleme, hover, sonsuz kaydırma ve shadow DOM; books.toscrape'te sayfalı tarama ve dosyaya yazma; beş makalelik Wikipedia karşılaştırması; automationexercise'da kayıt, sipariş ve hesap silme; GitHub'da sürüm notu, kaynak kod, birleştirilmiş PR ve katkıcılar; Hacker News ve dış makaleler), o sırada komutu olmayan sağ tık dışında doğru bitti. Ardından `click --right`, yalnızca simgeden oluşan butonlar için adlar (bir ajan "btn" diye listelenen bir butonla sepetten ürün silmişti), `open --id-only`, düz metin `js` sonuçları ve daha açıklayıcı `select` hataları eklendi. Üçüncü tur başka alanları kapsadı: aynı anda birden çok sekme, gizli pencere (oturum sızmadı), hata ayıklama (JS hataları, kırık görseller, 404/500, yanıt gövdeleri), Quill ve CodeMirror editörleri, slider ve sürükle-bırak, Türkçe siteler (karakter bozulmadı), ekran görüntüsünden okunan canvas içeriği ve hatalı kullanım (bilinmeyen kimlik ve ref, erişilemeyen adres, zaman aşımı, yanlış argüman). Ardından `drag`, yüklenemeyen gezinme ve `js` zaman aşımı için çıkış kodu 1, çakışan öğe argümanları için kullanım hatası ve daemon yeniden başlasa da korunan sekme kimlikleri eklendi. Biçimlendirme, sayfanın odak alamadığı başka kökenli bir frame'deki Quill'de başarısız olmuştu. Ardından alanlar ve editörler için `select R "metin"`, sayfa almazsa tarayıcının düzenleme komutlarına düşen biçimlendirme kısayolları, ve sonuçta seçimin ve biçim durumunun gösterilmesi eklendi. İndirmeler (`safari downloads`) ve unutulan ajan sekmelerinin kapatılması da aynı turdan çıktı.

Dördüncü tur, sahibinden.com'da yapılan gerçek bir tarama oturumunun ardından geldi ve `table`, `crawl`, `rate`, bot doğrulaması yönetimi ile temiz stdout'u (notlar stderr'e, `-o DOSYA`) ekledi. Ardından üç paralel Claude Haiku ajanı sahibinden.com'u sayfa başına 8-14 sn arayla taradı (3 sayfada 111 ilan, engel yok, tekrar yok), books.toscrape.com ve Wikipedia tablolarını okudu, yerel doğrulama ve hız sınırı sayfalarını sınadı. colspan/rowspan'li tablolarda kayan sütunlar ve kart listelerinde kısalan başlıklar bu turdan sonra düzeltildi. `table`, sayfa düzeni için kullanılan tabloları (Hacker News) hâlâ iyi okumuyor.

Beşinci tur, playwright-cli'den alınan özellikleri sınadı: `locator`, `highlight`, öğeyle `js`, `open --window` ve `resize`, `SAFARI_TAB`, `close --agents`, `route`, `storage`, `drop`, `record`, `shot --full`. Her biri önce yerel test sayfalarında (`fixture.html`, `route.html`, `drop.html`) ve Wikipedia'da elle denendi. Ardından yalnızca skill'i ve `references/` dosyalarını bilen dört Claude Haiku ajanı tek bir daemon üzerinde paralel çalıştı:
- the-internet'e, sayfa yeniden yüklendikten sonra `locator`'dan gelen seçicilerle, ref kullanmadan giriş;
- demo.playwright.dev/api-mocking'in meyve API'sini ve yerel `route.html`'i taklit etme, 500 döndürme ve engelleme;
- TodoMVC görevlerini localStorage üzerinden düzenleme, the-internet'in sürükle-bırak yükleme alanına dosya bırakma ve bir Wikipedia makalesinin tam sayfa görüntüsü;
- Bootstrap sitesi, kendi penceresinde 1280x800 ve 390x844 boyutlarında, `SAFARI_TAB` betikleriyle birlikte.

Beşinci bir ajan the-internet'te giriş ve çıkışı gerçek girdiyle (`--os`) kaydetti ve yeni bir sekmede tekrar oynattı. Bütün görevler 22–56 komutta bitti.

Bu turdan sonra düzeltilenler:
- `resize`, boyutu Safari'nin araç çubuğu oturmadan bildiriyordu (806 yerine 844).
- `shot --full`, kesilmiş bir sayfaya "whole page" diyordu.
- Üretilen ve kaydedilen seçiciler çıplak bir etiket (`button`) olabiliyordu.
- Formda Enter, gönder butonuna fazladan bir tıklama kaydediyordu.
- `go` boş bir sekmeden çalışmıyordu, bu yüzden tekrar oynatma oradan başlayamıyordu.

Safari'nin yerel menüsünde gerçek girdiyle bir `<select>` seçeneği seçilemedi; bu yüzden `<select>` değişikliklerinin kaydı sınanmadı.

Altıncı tur, playwright-cli'den alınan ikinci grubu (`check`/`uncheck`, regex `-q`, `cookies`, `state`, `pdf`) sınadı; skill bu turdan önce yaklaşık 1.450 token'lık bir çekirdeğe indirilmiş, ayrıntılar `references/` dosyalarına taşınmıştı. Beş Claude Haiku ajanı, her birine skill'in yolu verilerek, tek daemon üzerinde paralel çalıştı: yeni özellikler (fixture, Wikipedia, GitHub, TodoMVC); formlar ve akışlar (saucedemo ödeme, demoqa, uyarılar, dosya yükleme); tarama (yavaşlatmalı books.toscrape, Wikipedia tabloları, Hacker News); hata ayıklama ve taklit (loglar, kırık görseller, 404/500, `route`, `locator`, ekran görüntüleri); birkaç sekmede günlük araştırma (GitHub, MDN araması, DuckDuckGo, bir Türk haber sitesi, TinyMCE'de kalın yazı). Yanıtı 404 olan bir GitHub sayfası dışında bütün görevler 32-80 komutta bitti. Form ajanı hiçbir `references/` dosyasını açmadı; prompt'a yanıt verme, tarih seçiciler ve react-select açılır listelerinin yolunu deneyerek buldu. Bunun üzerine skill'deki görev listesi konu adları yerine durumlarla ("tarih seçicili, açılır listeli bir form…") yeniden yazıldı.

Yedinci turda dört ajana yalnızca görev ve "kullanıcının Safari'sini kullan" denildi; skill'in yolu, adı ya da references'tan söz edilmedi; siteler de daha önce kullanılmamış sitelerdi: alışılmadık girdiler (Selenium'un renk, aralık, datalist ve tarih alanlı formu; çerçeve içindeki jQuery UI tarih seçicisi; tuş basma, kaydırıcı, hover, sürükle-bırak), dinamik sayfalar (geç gelen içerik, sonsuz kaydırma, shadow DOM, sıralanabilir tablo, scrapethissite'ta sayfalı tarama ve AJAX taklidi), girişler ve oturumlar (deneme girişi, saucedemo oturumunu gizli pencereye taşıma, httpbin ile doğrulanan çerezler, bir MDN PDF'i), paralel sekmeler ve dayanıklılık (üç sekmeli betik, quotes.toscrape taraması, 390 ve 1280 px'te Bootstrap, hepsiburada'da arama, kasıtlı hatalar). Her ajan skill'i kendisi yükledi; dördünden üçü görevine uyan reference'ı okudu, dördüncüsü `safari help` ile yetindi. Gizli pencereye taşınan giriş dışında bütün görevler yaklaşık 60-80 komutta bitti.

Bu turlardan sonra düzeltilenler:
- Blok gövdeli arrow fonksiyonlu `js` (`map(r => { …; return x })`) `undefined` döndürüyordu: koddaki herhangi bir `return`, kodu işlev gövdesi saydırıyordu.
- Onay kutusu ya da radyo olmayan bir öğede `check` ve seçili bir radyoda `uncheck` "not changed" deyip 0 ile çıkıyordu; ikisi de artık nedenini yazıp 1 ile çıkar.
- Ulaşılamayan bir adreste `open` 0 ile çıkıp sekme kimliği veriyordu; artık 1 ile çıkar ve sekmeyi kapatır.
- `crawl`, aynı satırlara geri götüren bir "Next" bağlantısını (scrapethissite'ın ilk sayfası) sayfa sayıyordu; bu tür sayfalar artık atlanır.
- Gizli pencerede `cookies` ve `state load` normal pencerenin çerezlerine yazıyordu, bu yüzden taşınan giriş tutmuyordu; eklenti artık gizli sekmenin çerez deposunu kullanır.
- `drag --to` ref'in yanında CSS seçici de alır; "eşleşme yok" iletilerinde regex desenleri yazıldığı gibi görünür; skill `go reload` der (bir ajan `reload` denemişti).

Sekizinci tur (Kasım 2026), Apple Events altyapısının kaldırılmasının ve `route`'un yeniden yazılmasının ardından yapıldı. Her adım önce Safari 27.2'de `route.html`, `fixture.html`, example.com ve httpbin.org üzerinde elle denendi; CLAUDE.md'deki ağ kuralı tuhaflıkları böyle bulundu. Ardından Claude Haiku ajanları tek daemon üzerinde paralel çalıştı: bütün günlük komutların gerileme sınaması (hepsi geçti), `route` için iki tur özellik sınaması ve iki tur saldırgan sınama. İlk saldırgan tur, Safari'nin ağ kurallarını her sekmeye uyguladığını gösterdi; sekme başına route ile `--global` ayrımı bundan doğdu.

Bu turlardan sonra düzeltilenler:
- Düz taklitler https sayfalarında çalışmıyordu (karışık içerik); artık taklit sunucusuna gizli bir işarete bağlı bir ağ kuralı yönlendirmesiyle ulaşıyorlar.
- Boş desen her isteğe uyuyordu, satır sonu içeren bir başlık değeri iki başlık oluyordu; ikisi de, her şeye uyan bir `--global` desen de reddedilir.
- Başka bir porta geçişte ya da betikle yapılan gezinmede kurallar yeniden uygulanmıyordu; `#parça` içeren adresler ve kuraldan önce yüklenen iframe'ler kaçıyordu; yeniden kullanılan bir XHR başarısız diye kaydediliyordu.
- Kapanan bir daemon'un genel kuralları 5 sn sonra kaldırılır; böylece ölü bir taklit sunucusu kullanıcının sekmelerini bozamaz.

Dokuzuncu tur (Kasım 2026) safari'yi dört görevde playwright-cli ile karşılaştırdı; her araç ve görev için bir Claude Haiku ajanı çalıştı. İkisi de her soruyu doğru yanıtladı; safari TodoMVC'de (`type` bir öğe istiyordu) ve books.toscrape'te (`table` kart ızgarasını görmüyordu) daha çok komut harcadı. Bunun sonucunda `type` odaktaki alana yazar oldu, `fill` ve `type`'a `--submit` eklendi, `table` tekrar eden kartları kendisi bulur (sabitlemek için seçiciyi de verir) ve hücrelerden buton yazılarını atar. İki kez yeniden koşulduğunda TodoMVC 16 yerine 10–13, books.toscrape 10 yerine 5–9 komut sürdü.

Onuncu tur (Kasım 2026) görev turu değil, kodun baştan sona gözden geçirilmesiydi. Bu turda gerçek Safari'yi yerel test sayfalarıyla süren canlı bir regresyon betiği (134 kontrol: okuma, işlem, iletişim kutuları ve çerçeveler, `wait`, `js`, loglar, depolama, çerezler, `state`, `route` ve yaşam döngüsü, `challenge.html` ile `captcha.html`) ve saf fonksiyonlar için `safari --selftest` eklendi. İlk koşular üç gerçek hata buldu ve düzeltildi: üst sayfada verilen bir iletişim kutusu yanıtı alt çerçevelerde kurulu kalıyor, sonraki bir çerçeve `confirm`'ü kabul ediyordu; `fill`'den hemen sonraki `click` zamanlayıcının değişikliğini beklemeden dönüyordu; `js` bayat bir route kopyasını yerinde bırakıyordu. Aynı turda düz route'lara etiket ve 37 dakikalık kira eklendi (hiçbir daemon'un yenilemediği kopya istekleri değiştirmeyi bırakır) ve eklenti yeniden bağlandığında sekme kimlikleri sayfadaki handle ile korunur oldu.

Sınama tek bir Mac'te (macOS 27) yapıldı, geniş bir site yelpazesinde denenmedi.

## Sınırlar

- Kapalı shadow DOM okunmaz. En çok 8 iframe okunur.
- Bazı siteler sayfa içi olayları yok sayar; `hover` yalnızca okunabilen CSS `:hover` kurallarını taklit eder. Bu durumlarda `--os` kullan.
- `--os` tuşları klavye düzenini izler (karakter tuşları etkin düzende bulunur), böylece `cmd+i` Türkçe Q'da da AZERTY'de de doğru tuşa gider; `key A` büyük A yazar.
- Katı CSP'li sitelerde (GitHub, Gmail) eklenti `js`'i ayrı bir ortamda çalıştırır: DOM'u görür, sayfanın JavaScript değişkenlerini görmez.
- safari'nin henüz girmediği bir sitenin ilk yüklenişinde açılan iletişim kutuları Safari'nin kendisinindir ve çağrıları 20 sn bekletir (`dialog` ile, Erişilebilirlik üzerinden yanıtlanabilir).
- Ajanlar tek bir daemon'u paylaşır; birden fazla yeni sekme açıkken sekme kimliğini başa yazmalı (ya da `SAFARI_TAB` kullanmalı).
- Düz `route` yalnızca sekmenin kendi fetch/XHR isteklerini sayfanın içinde yakalar (taklit edilenler ağa hiç çıkmaz; Worker, `sendBeacon` ve `EventSource` kapsanmaz). Betikler, stiller, görseller, çerçeveler ve sayfalar `--global` ister: Safari'nin ağ kuralları sekme süzgecini yok sayar ve istek olayları hangi sekmenin istediğini güvenilir biçimde söylemez; bu yüzden kurallar `unroute`'a, yönlendiren sekme kapanana ya da daemon durana kadar kullanıcınınkiler dahil bütün sekmelerde geçerlidir. Düz route'lar da daemon ile biter (`safari stop`, yeni derleme için yeniden başlatma, 30 dakika komutsuz kalma): daemon çıkarken onları temizler, ondan haber alamayan sayfa en geç 37 dakikada bırakır ve sekmeye yapılan bir sonraki safari çağrısı artık arkasında durulmayanları hemen kaldırır. `--global` ile Safari yalnızca standart başlık adlarını değiştirir (özel `X-` adlarını değil), regex motorunda `|`, `{n}` ve lookahead yoktur, `--block` çakışan bir taklitten üstündür ve `--doc` sayfasının kökeni taklidinkidir (`127.0.0.1`), sitenin çerezleri yoktur. Worker, service worker ve WebSocket mesajları taklit edilmez; taklit edilen fetch'in `response.url`'i yerel taklit adresidir.
- `logs`, metin ve JSON yanıt gövdelerinin ilk 4000 karakterini tutar; akış yanıtlarında (`text/event-stream`, NDJSON) hiçbiri tutulmaz. Konsol nesneleri tam JSON olarak değil, kısa bir önizleme olarak gösterilir (3 düzey, 10 anahtar ya da öğe).
- `record` tek sekmede tek siteyi kapsar; zengin metin editörlerini ve parola değerlerini kaydetmez.
- `shot --full` sayfanın kendisini kaydırır; içteki bir kutuyu kaydıran sayfalarda yalnızca ilk ekran çıkar.
- `pdf`, sayfanın anlık kopyasını JavaScript kapalıyken yeniden dizer: kullanıcının girişini isteyen görseller, yüklemeden sonra betiklerin çizdiği içerik ve başka kaynaklı canvas'lar eksik çıkabilir.
- Safari'nin çerez deposunu adlandırmadığı bir gizli pencerede `cookies` yalnızca sayfanın okuyabildiği çerezleri görür (HttpOnly yok).
- Safari web uygulamaları (Dock'a Ekle) sürülmez. Her biri eklentinin kendi kopyasını çalıştırır, safari bu kopyaları kullanmaz; `safari status` onları yok sayılan olarak sayar.
- Data: adresleri (Tab Sleeper gibi eklentilerin uyuyan sekmeleri) eklentilerden gizlenir, bu yüzden `tabs` onları boş listeler.
- Bot doğrulamaları başlık ve işaretlemeleriyle tanınır; başkaları fark edilmeden geçer. Hız sınırı `go`, `open` ve `crawl` için geçerlidir; sayfa yükleyen tıklamalar için değil.
- `text` kipi bağlantı metinlerini ve veri tablosu hücrelerini kırpar (200 karakter, 60 satır); karmaşık tablolarda düzen bozulabilir. Sayfa düzeni için kullanılan tablolar metin olarak okunur.
- Her isteğin yanıt gövdesini okumak ve `--os` olmadan gerçek (güvenilir) girdi, Safari'nin Web Inspector protokolünü gerektirir; kendi Safari'nde bunu yalnızca Apple imzalı uygulamalar kullanabilir. Apple'ın `safaridriver --mcp`'si bunu sekmelerini ve çerezlerini görmeyen ayrı, temiz bir oturumda sunar.

## Geliştirme

```bash
make test                                                   # derleme, sayfa betiği sözdizimi, selftest, CLI ve daemon testi
make test-live                                              # gerçek Safari'de canlı sınamalar (eklenti açık; kendi arka plan sekmeleri)
(cd Tests && python3 -m http.server 8765 --bind 127.0.0.1)  # test sayfalarını sun
```

`make test` Safari izni gerektirmez. `make test-live` gerçek Safari'yi test sayfalarıyla sürer, eklenti bağlı değilse 77 ile çıkar ve kurulu eklenti route kirasından eskiyse o kontrolleri atlar. `safari --selftest` yalnızca saf fonksiyon kontrollerini çalıştırır.

Elle sınama için `http://127.0.0.1:8765/fixture.html`'i `safari open` ile aç (form, iletişim kutuları, gecikmeli öğe, tablo, fetch, iframe). `route.html` (fetch/XHR/Worker butonları; `route` taklit edene kadar eksik olan bir betik, stil dosyası ve görsel) ile `drop.html` (bir bırakma alanı) `route` ve `drop` içindir.

## Lisans

[MIT](LICENSE)
