# safari-mcp

Claude Code'un Safari'yi sürmesini sağlayan yerel bir MCP sunucusu. Tek bir Swift ikili dosyası, bağımlılığı yok. Safari'yi senin açık oturumlarınla kullanır: isteğe bağlı **Safari MCP Bridge** eklentisi kuruluysa onun üzerinden, değilse Apple Events üzerinden.

Claude in Chrome yalnızca Chromium tarayıcılarda çalıştığı için yazıldı. Anthropic ile bağlantısı olmayan bağımsız bir projedir; resmi eklentinin kodunu, oturum token'ını ya da bulut köprüsünü kullanmaz.

## Ne zaman kullanılır

| | safari-mcp | Playwright |
|---|---|---|
| Tarayıcı | Senin açık Safari'n, kendi oturumlarınla | Kendi başlattığı ayrı tarayıcı |
| Girdi | Varsayılan sayfa içi olaylar; istenirse gerçek fare/klavye | Tarayıcı düzeyinde gerçek olaylar |
| İletişim kutusu, dosya yükleme | Var | Var |
| iframe | Eklentiyle var | Var |
| Ağ müdahalesi | Yok | Var |
| Platform | macOS 14+ | macOS, Windows, Linux |

Giriş yapmış olduğun sitelerde okuma, arama, form doldurma ve gezinme gibi günlük işler için uygundur. Web uygulaması testi, CI ve tekrarlanabilir otomasyon için Playwright daha doğru araçtır.

## Kurulum

macOS 14 ya da üstü gerekir. Xcode gerekmez; Command Line Tools yeterlidir.

```bash
git clone https://github.com/sadopc/safari-mcp.git
```

```bash
cd safari-mcp && swift build -c release
```

```bash
claude mcp add --scope user safari -- "$PWD/.build/release/safari-mcp"
```

Kayıt ikilinin tam yolunu saklar; klasörü taşırsan komutu yeniden çalıştır. Yeniden derledikten sonra açık Claude Code oturumları eski sürümü çalıştırmaya devam eder; yeni sürüm yeni oturumda geçerli olur.

### Claude Code skill'i (önerilen)

`Skill/safari-browser/SKILL.md`, Claude'a bu araçları nasıl kullanacağını anlatır:
- kendi sekmesinde çalışmak ve işi bitince kapatmak;
- ekran görüntüsü yerine `read` kullanmak, işlemlerden sonra `diff` ile yalnızca değişeni okumak;
- form doldurmak, iletişim kutularını ve iframe ref'lerini doğru kullanmak;
- sonuçlu işlemlerden (gönderme, satın alma, silme) önce sormak.

Her oturumda yalnızca skill'in adı ve kısa açıklaması yüklenir, içeriği Safari'yle ilgili bir iş gelince okunur. Kurmak için:

```bash
ln -s "$PWD/Skill/safari-browser" ~/.claude/skills/safari-browser
```

### Safari eklentisi (önerilen)

Eklenti kuruluysa sunucu Apple Events kullanmaz, bu yüzden Otomasyon ve "Allow JavaScript from Apple Events" izinleri gerekmez. Ayrıca iframe içeriklerini okur, HTTP durum kodunu (404 gibi) bildirir, ağ kaydını sayfa açıldığı andan itibaren tutar ve ekran görüntüsünü Ekran Kaydı izni olmadan alır. Eklenti bağlı değilken sunucu Apple Events'e geri döner.

Eklentiyi kurmak için Xcode gerekir (Command Line Tools yetmez):

1. Xcode > Settings > Accounts bölümünde bir Apple ID ekle (ücretsiz hesap yeterli).
2. `Extension/Safari MCP Bridge/Safari MCP Bridge.xcodeproj` projesini Xcode'da aç. İki hedef için de Signing & Capabilities altında Team olarak kendi Personal Team'ini seç ve kaydet.
3. Derle ve kur. `--schedule` her pazartesi 11:00'de eklentiyi yeniden derleyip imzalayan bir arka plan görevi kurar, çünkü ücretsiz hesap imzalarının süresi dolar:
   ```bash
   Extension/build.sh --schedule
   ```
4. Safari > Ayarlar > Uzantılar'da **Safari MCP Bridge**'i aç ve "Her Web Sitesinde İzin Ver"i seç.

Uygulama `~/Applications/Safari MCP Bridge.app` konumuna kurulur. Sunucu ile eklenti `127.0.0.1` üzerinde 47391-47399 portlarından konuşur; her Claude Code oturumu kendi portunu alır. İki taraf da `~/.config/safari-mcp/token` dosyasındaki anahtarla birbirini doğrular. Bu yüzden başka bir web sayfası ya da yerel program araya giremez.

Safari eklentilere `file://` sayfalarında izin vermez; yerel dosyalarda sunucu Apple Events'e geri döner.

## İzinler

| İzin | Ne için | Eklentiyle | Eklentisiz |
|---|---|---|---|
| Safari > Ayarlar > Uzantılar > Safari MCP Bridge, her web sitesinde | Her şey | Gerekli | — |
| Safari'yi denetleme (Otomasyon) | Her şey | Gerekmez | Gerekli, ilk kullanımda sorulur |
| Safari > Ayarlar > Geliştirici > "Allow JavaScript from Apple Events" | `tabs` dışındaki bütün araçlar | Gerekmez | Gerekli |
| Ekran Kaydı | `screenshot` | Yalnızca sekme ekranda değilken | Gerekli |
| Erişilebilirlik | `act` içinde `os: true`; yerel iletişim kutuları; ekran görüntüsünün tam kırpılması | İsteğe bağlı | İsteğe bağlı |

Geliştirici sekmesi görünmüyorsa önce Ayarlar > Gelişmiş > "Web geliştiricileri için özellikleri göster" seçeneğini aç.

"Allow JavaScript from Apple Events" ayarı, Safari'yi denetleme izni olan her uygulamanın sayfalarda JavaScript çalıştırmasına izin verir. İzinler sunucuyu başlatan uygulamaya (Claude ya da terminal) yazılır.

## Kullanım

Kurulumdan sonra Claude Code'a doğrudan iş söylemek yeterlidir:

- "Safari'de açık sekmelerimi listele."
- "Wikipedia'da Boğaziçi Köprüsü'nü ara, açılış yılını söyle."
- "Şu sayfadaki formu şu bilgilerle doldur ama gönderme."

## Araçlar

| Araç | İş |
|---|---|
| `tabs` | Sekmeleri listeler, açar, kapatır, seçer |
| `navigate` | URL'ye gider ya da `back` / `forward` / `reload`; yüklenmeyi bekler |
| `read` | Sayfayı okur: etkileşimli öğeler (varsayılan), `all`, `text` (markdown), `links`; `query` ile öğe arar ya da metni ve bağlantıları süzer; `diff` yalnızca değişeni döner |
| `act` | `click`, `dblclick`, `hover`, `type`, `fill` (`fields` ile çok alan), `select`, `key`, `scroll`, `wait`, `upload`, `dialog` |
| `js` | Sayfada JavaScript çalıştırır (async işlev gövdesi, `return` ile değer döner, 15 sn sınırı) |
| `screenshot` | Görünüm alanının, bir öğenin ya da bölgenin JPEG görüntüsü |
| `logs` | Konsol ve ağ kayıtları; `level`, yalnızca yeniler (`new`), `id` ile yanıt gövdesi |
| `batch` | Birden çok çağrıyı tek turda çalıştırır |

`read` her öğeye `e12` gibi bir ref verir; `act` bu ref'le ya da `x,y` ile çalışır. Aynı sayfada bir öğe ref'ini korur; başka sayfaya geçince ref'ler geçersiz olur. `diff: true` aynı kipteki önceki okumadan bu yana eklenen (`+`), değişen (`~`) ve kaybolan (`-`) satırları döner.

`text` kipi ana içeriği markdown olarak verir: başlıklar, listeler, tablolar ve kod blokları korunur, bağlantılar `metin[3]` biçiminde yazılır ve her parçanın sonunda o parçadaki bağlantıların adresleri listelenir. `query` ile birlikte yalnızca sorguya en uygun bloklar (BM25) döner. `links` kipi bağlantıları ref'leri ve adresleriyle sayfa sırasında listeler.

## Bekleme, formlar, dosyalar

- `act wait`: `text`, `ref` ya da `selector` görünene kadar bekler (`gone: true` ile kaybolana kadar; `timeout` saniye, varsayılan 10, en çok 30). Gezinme sırasında da bekler.
- `act fill` + `fields: {"e4": "Ada", "e6": true}`: birden çok alanı tek çağrıda doldurur; açılır listede seçeneği seçer, onay kutularını `true`/`false` ile ayarlar.
- `act upload`: `text` ile verilen yerel dosyaları (virgülle ayrılmış, toplam en çok 10 MB) dosya alanına koyar.

## İletişim kutuları

Sayfadaki `alert`, `confirm` ve `prompt` sunucunun sayfaya yerleştirdiği betik tarafından yanıtlanır, böylece Safari takılmaz. `alert` onaylanır; `confirm` ve `prompt` varsayılan olarak reddedilir. Bir sonraki kutuyu onaylatmak için önce `act dialog` ile `text: "accept"` (ya da `prompt` için yanıt metni) verilir. Yanıtlanan her kutu sonuçta `⚠ dialog confirm "…" → dismissed` gibi bir satırla bildirilir.

Kutular yalnızca sunucunun çalıştığı sekmelerde yanıtlanır; senin kendi gezinmende Safari'nin kutuları değişmeden çıkar. Eklentiyle bu yanıtlama sayfa yüklenirken ve iframe'lerde de çalışır; çerçeveden gelen kutular `(frame)` ile işaretlenir.

Eklentisiz modda, betik yerleşmeden önce açılan kutular Safari'de yerel olarak görünür ve çağrılar 20 saniye sonra zaman aşımına uğrar. Bu durumda `act dialog` kutuyu Erişilebilirlik üzerinden yanıtlar; sekme arka plandaysa onu kısa süre öne alır, sonra önceki sekmeye döner.

Sayfayı değiştiren çağrılar (`act`, `navigate`, yönlendiren `js`) yeni sayfanın yüklenmesini bekler ve sonucu `→ başlık | adres` olarak bildirir. Bir tıklama ya da tuş hiçbir şeyi değiştirmediyse sonuçta `(no change on the page yet)` yazar. Sayfa yerinde değiştiyse yeni görünen satırlar `· new text: …` ile, bu sırada sunucunun 4xx/5xx ile yanıtladığı istekler `· failed: n7 POST 400 /api/carts` ile eklenir (yanıtsız kalan istekler, çoğu iptal edilmiş analitik çağrısı olduğu için yalnızca `logs`'ta görünür). `act wait` aranan metin zaten sayfadaysa bunu `already present` diye söyler.

## Sekmeler

Sekme kimlikleri `t3` biçimindedir ve sekme açık kaldıkça değişmez; sen sekme açıp kapatsan ya da taşısan da aynı sekmeyi gösterir. Safari her çağrıda, işlemi yapmadan önce o konumdaki sekmenin beklenen sekme olduğunu doğrular; tutmuyorsa sunucu sekmeyi yeniden bulur ya da hata döner. Yanlış sekmede işlem yapmaz.

Sekme verilmeyen çağrılar son kullanılan sekmede çalışır. O sekme kapanırsa sunucu başka bir sekmeye geçmez, sekme kimliği ister. Hiç sekme kullanılmamışsa ilk çağrı öndeki pencerenin görünen sekmesini kullanır.

Sunucunun açtığı sekmeler arka planda açılır.

## Tıklama ve yazma

Varsayılan yol sayfa içi olaylardır: Safari arka planda kalır, imleç sende kalır.

Sayfa içi tuş olayları tarayıcının kendi davranışını tetiklemediği için, sayfa olayı kendisi işlemediyse sunucu alanlardaki düzenleme tuşlarını kendisi uygular: `cmd+a`, `Backspace`, `Delete`, ok tuşları, `Home`/`End` (`shift` ile seçim), tek karakter ve çok satırlı alanlarda `Enter`. Sonuç alanın yeni değerini gösterir; kaydırıcılarda (`role="slider"` ve `input[type=range]`) tuşun ardından değer `key ArrowLeft ="99"` gibi yazılır. Hedefsiz tuşlar, son hedef alınan iframe'e gider. `type` metni her zaman sona ekler.

`hover`, sayfanın CSS `:hover` kurallarını bir sınıfla kopyalayıp öğeye ve atalarına uygular; böylece üzerine gelince açılan menüler `os: true` olmadan açılır. Başka sitelerden yüklenen stil sayfalarının kuralları okunamaz; sonuç bunu söyler.

Bir işlem sayfanın kendi isteklerini başlatırsa (sepete ekleme, adres arama) sunucu bunların bitmesini en çok 2 saniye bekler. Sayfa hemen tepki vermezse 1,2 saniye daha bakar; geç beliren metin de sonuca girer. Sonuç, işlemin hedefi dışında değişen form alanlarını `· also changed: e4 textbox "Sokak" ="…"` diye bildirir.

`os: true` gerçek fare ve klavye olayı gönderir. Sayfa içi olayları yok sayan siteler ve stilini başka siteden alan `:hover` menüleri için gerekir. Erişilebilirlik izni ister, Safari'yi öne getirir ve çalışırken imleci kullanır; tıklamadan sonra imleci eski yerine koyar, `hover` sonrasında öğenin üzerinde bırakır. Çağrı başına yaklaşık bir saniye sürer.

## Ekran görüntüsü

Eklentiyle, sekme görünür durumdaysa görüntüyü eklenti alır; Ekran Kaydı izni gerekmez.

macOS yalnızca o an görünen masaüstündeki pencereleri çizer. Safari başka bir masaüstündeyse ya da tam ekrandaysa sunucu onu yaklaşık bir saniyeliğine öne getirir, görüntüyü alır ve önceki uygulamaya döner. Safari görünür durumdaysa geçiş olmaz.

Yakalama ayrı, kısa ömürlü bir yardımcı süreçte yapılır; 6 saniyede bitmezse sonlandırılır.

## Kaynak kullanımı

Tek bir Mac'te ölçülen değerler:

| | |
|---|---|
| Araç şemaları | Yaklaşık 875 token |
| Varsayılan `read` çıktısı | Wikipedia ana sayfasında yaklaşık 500, Hacker News'te yaklaşık 1.100 token |
| Çağrı süresi | `read` 7-60 ms, `js` 20-45 ms, `act` 170-470 ms, `screenshot` 0,9-2,1 sn |
| Bellek | Safari kullanılmadan 9 MB, kullanıldıktan sonra yaklaşık 34 MB |
| Boşta CPU | 0 |
| İkili dosya | Yaklaşık 360 KB |

Açık her Claude Code oturumu kendi `safari-mcp` sürecini çalıştırır; Etkinlik Monitörü'nde birden fazla görünmesi olağandır ve süreç, oturum kapanınca çıkar.

Eski derlemelerde boşta bekleyen süreç, başka bir uygulamaya geçildikten kısa süre sonra Etkinlik Monitörü'nde "Yanıt Vermiyor" olarak görünürdü. Bu yalnızca bir etiketti, araç çağrıları çalışmaya devam ediyordu. Güncel sürümde düzeltildi; hâlâ görüyorsan yeniden derle ve Claude Code oturumlarını yeniden başlat.

## Sınanma durumu

Sunucu, küçük bir modelin (Claude Haiku) araçları yalnızca açıklamalarından kullanarak gerçek sitelerde görev yaptığı beş turla sınandı: Wikipedia, Hacker News, MDN, GitHub, DuckDuckGo, W3Schools, httpbin formları ve TodoMVC (React ve Vue). Son regresyon turunda sayfayı değiştiren 28 çağrının hepsinde bildirilen sayfa ile ardından okunan sayfa aynıydı.

Bu, bir günde ve tek bir makinede yapılmış bir sınamadır; geniş bir site yelpazesinde denenmedi.

Markdown, `links`, `diff`, `wait`, `fill fields`, `upload`, iletişim kutuları ve ağ gövdeleri sonradan eklendi; bunlar `Tests/fixture.html` üzerinde ve Wikipedia ile Hacker News'te elle sınandı, model turlarına girmedi.

24 Ekim 2026'da 15 Haiku ajanıyla bir tur daha yapıldı. Ajanlar paralel çalıştı ve sunucu eklentisiz (Apple Events) moddaydı. Okuma görevlerinin yanında hesap açma, sepet ve ödeme adımları da denendi: automationexercise, Toolshop (Angular), saucedemo (React), demowebshop ve the-internet. Cevaplar doğruydu, ama zor sayfalarda çağrıların yaklaşık dörtte biri `js`'e kaçtı ve şu sorunlar bulunup düzeltildi:
- `batch` üst seviyedeki `tab`'ı yok sayıyordu.
- Arka plandaki sekmede odak olayları oluşmadığı için Angular formları değeri almıyordu.
- SPA geçişleri bildirilmiyordu.
- `select` sonucu doğrulanmıyordu.
- `logs id` gövde döndürmüyordu.
- `wait` süresinin birimi belirsizdi.
- `read` atladığı iframe'leri ve ekran dışındaki kontrolleri söylemiyordu.
- Slot'a yerleşen shadow DOM metni `all` kipinde görünmüyordu.

En zor 5 görev düzeltmelerden sonra Haiku ile tekrarlandı. İletişim kutuları, Angular formu, SPA geçişleri ve `select` doğrulaması doğru çalıştı. Diyalog/iframe görevi 49 yerine 30 çağrıda bitti. Diğer görevlerde çağrı sayısı pek düşmedi, çünkü ajanlar sonuçları `js` ile ayrıca doğruluyor. Bu turda bulunan bir odak hatası (sayfanın `mousedown` içinde odağı kendisinin taşıması, örneğin kaydırıcılar) da düzeltildi.

Aynı görevler üçüncü kez, bu sefer eklenti modunda koşturuldu. Çağrı sayıları diyalog/iframe görevinde 49 → 30 → 21, the-internet'te 85 → 84 → 66, Toolshop'ta (kayıt, fiyat filtresi, sepet) 170 → 178 → 89 oldu. Bu turda bulunanlar da düzeltildi:
- düzenleme tuşları (`cmd+a`, `Backspace`, `End`) alanlarda hiçbir şey yapmıyordu ve `type` düzenlenebilir alanlarda metni başa ekliyordu;
- sunucunun reddettiği istekler (400) tıklama sonucunda görünmüyordu;
- iframe'den açılan iletişim kutusu bir sonraki çağrıda bildiriliyordu;
- `wait`, zaten sayfada olan metni yeni gelmiş gibi bildiriyordu;
- diyalog cevabının biçimi (`answer:test`) yanlış anlaşılabiliyordu.

Bu düzeltmeler `Tests/fixture.html` ve the-internet'in TinyMCE sayfasında elle sınandı.

Dördüncü tur yine eklenti modunda koşturuldu. Üç görevin hepsi doğru bitti; diyalog ve iframe görevi bu sefer istem yanıtı, 404 isteği ve düzenlenebilir alan adımlarını da içeriyordu (27 çağrı). Düzenleme tuşları, `· failed:` satırı ve çerçeve diyalogları ilk denemede çalıştı. Bu turda bulunanlar da düzeltildi:
- eklentiyle TinyMCE'nin `srcdoc` çerçevesi hiç okunmuyordu ve bununla ilgili bir not da çıkmıyordu;
- `· failed:` satırı, her tıklamada iptal edilen bir analitik isteğini gösteriyordu;
- eleman silinince kısalan satır `· new text` olarak bildiriliyordu;
- `Left` gibi kısa tuş adları tanınmıyordu.

Bu turdan kalan üç sorun da sonradan giderildi ve elle sınandı:
- `role="menuitem"` taşıyan ve içinde bağlantı olan öğelerin (Toolshop hesap menüsü) bağlantıları `read`'de görünmüyordu;
- sayfa bir alanı değiştirince başka alanları da değiştirdiğinde (Toolshop adres araması) sonuç bunu söylemiyordu;
- CSS `:hover` menüleri yalnızca `os: true` ile açılıyordu (the-internet `/hovers` artık sayfa içi olaylarla açılıyor).

Beşinci turda (eklenti modu) üç görevin hepsi doğru bitti ve hiçbir ajan tıklamak, yazmak ya da doldurmak için `js` veya `os: true` kullanmadı; `js` yalnızca okuma ve doğrulama için çağrıldı. the-internet 62 çağrıda (önceki turlarda 85, 84, 66, 74), Toolshop 69 çağrıda (170, 178, 89, 97) bitti; hover, TinyMCE, adres otomatik doldurma ve hesap menüsünden çıkış sayfa içi olaylarla çalıştı. Bu turda `href`'i olmayan menü bağlantılarının `read`'de metin olarak görünmesi düzeltildi. Sonradan şunlar da giderildi: kaydırıcı tuşlarında anlamsız `new text` satırları yerine değerin gösterilmemesi, bir saniye sonra beliren metnin "no change" diye bildirilmesi ve etiketsiz onay kutularının ortak bir adla listelenmesi.

Eklenti yolu da sonradan eklendi ve elle sınandı:
- Aynı test sayfası üzerinde, iframe'le birlikte, eklenti modunda sınandı.
- Wikipedia'da 404 durum kodunun bildirildiği ve GitHub'ın katı CSP'sinde `js`'in çalıştığı görüldü.
- Aynı anda iki sunucu süreciyle sınandı.
- Eklenti yeniden imzalanıp kurulduktan sonra kendiliğinden yeniden bağlandı.
- Ücretsiz Apple ID ile imzalanan eklenti, Safari kapatılıp açıldıktan sonra "Allow unsigned extensions" açılmadan etkin kaldı ve kendiliğinden bağlandı (macOS 27, tek Mac).

## Sınırlar

- Eklentisiz modda, bir sekme bu oturumun dışında başka bir siteye giderse ve aynı anda pencerede sekme açılıp kapanırsa sunucu o sekmeyi kaybedebilir. Bu durumda hata döner; `tabs` ile yeni kimlik alınır. Eklentiyle sekmeler Safari'nin kendi kimlikleriyle izlenir.
- Bazı siteler sayfa içi olayları yok sayar; `:hover` taklidi yalnızca okunabilen stil sayfalarında ve CSS ile yapılan menülerde çalışır (fare konumunu JavaScript ile izleyen menüler fare olaylarına bakar). Bu durumlarda `os: true` gerekir. `os: true` sekmeyi kısa süre öne getirir, hedefin üstünü başka bir eleman kaplıyorsa tıklamaz, işten sonra kullanıcının görünür sekmesini ve öndeki uygulamayı geri getirir.
- `tab` verilmeyen çağrılar son kullanılan sekmeye gider. Aynı sunucuyu paylaşan birden çok ajan bu sekmeyi birbirinden devralabilir. Bu yüzden `tabs new` ile açılmış birden fazla sekme açıkken `tab` verilmeyen çağrılar reddedilir; her çağrıda `tab` verilmelidir.
- Erişilebilirlik izni yokken ekran görüntüsü kırpması, kenar çubuğunun solda, araç çubuğunun üstte olduğunu ve sayfa yakınlaştırmasının %100 olduğunu varsayar.
- Eklentisiz modda konsol ve ağ kayıtları sunucunun sayfaya ilk girdiği andan sonrasını kapsar ve ilk ağ çağrısı o ana kadar yüklenmiş kaynakları durum kodu olmadan listeler. Eklentiyle kayıt sayfa açıldığı anda başlar. İki durumda da ağ listesi resim, betik ve stil dosyalarını `pattern` verilmedikçe göstermez. Yanıt gövdeleri yalnızca fetch/XHR'ın metin ve JSON yanıtları için, son 50 istekte ve ilk 4 KB'ye kadar tutulur.
- Kapalı shadow DOM okunmaz. iframe içerikleri ilk 8 çerçeveye kadar `f1e5` gibi ref'lerle okunur. Eklentisiz modda yalnızca aynı kökenli ve sayfa CSP'si `eval`'a izin veren çerçeveler okunabilir (örneğin TinyMCE editörü); okunamayanlar `read` çıktısında ayrıca belirtilir. Safari eklentinin `srcdoc`/`about:blank` çerçevelerine betik sokmasına izin vermez; eklentiyle bu çerçevelere de üst belge üzerinden, eklentisiz moddaki yolla ulaşılır, ama bu çerçevelerde iletişim kutuları yanıtlanmaz ve konsol kaydı tutulmaz.
- Eklenti, Safari'nin katı CSP uygulayan sitelerinde (GitHub, Gmail) `js` kodunu sayfanın kendi ortamında çalıştıramaz; kod eklentinin ortamında çalışır, DOM'a erişir ama sayfanın JavaScript değişkenlerini göremez. Sonuçta bu not olarak belirtilir.
- Eklenti kurulmadan önce açılmış sayfalarda konsol kaydı ve iletişim kutusu yanıtlama, sayfa yenilenene kadar çalışmaz.
- Eklentisiz modda, betik yerleşmeden önce ya da bir iframe'den açılan iletişim kutuları çağrıları 20 saniye bekletir; `act dialog` bunları yalnızca Erişilebilirlik izniyle yanıtlayabilir. Eklentiyle de, sunucunun henüz girmediği başka bir siteye geçilirken sayfa yüklenirken açılan kutular için aynı durum geçerlidir.
- HTTP durum kodu (404 gibi) yalnızca eklentiyle bildirilir; Safari bunu sayfaya vermez. Safari'nin hiç açamadığı adresler her iki modda da hata döner.
- `text` kipi bağlantı metinlerini ve tablo hücrelerini kırpar; çok sütunlu ya da iç içe tablolu sayfalarda düzen kaybolabilir.
- Yukarıdaki sınırların çoğu (gerçek girdi olayları, CSP, iframe, tüm ağ trafiği, iletişim kutuları) Playwright'ın kullandığı Web Inspector protokolüyle aşılabilirdi, ama kullanıcının açık Safari'sinde bu protokole yalnızca Apple'ın kendi imzaladığı uygulamalar bağlanabilir: `webinspectord` başka bir sürecin bağlantısını "did not have entitlement" diyerek reddeder (macOS 27'de sınandı). Bu erişimi Apple'ın `safaridriver --mcp` sunucusu sunar, ama ayrı ve temiz bir otomasyon oturumunda: kullanıcının sekmelerini ve çerezlerini görmez. Oturum açmış olmayı gerektirmeyen test ve otomasyon işleri için o daha uygundur; "Allow remote automation" ayarının açık olmasını ister.

## Test

```bash
Tests/smoke.sh
```

Protokol düzeyinde bir duman testidir; Safari izni gerektirmez. Şema boyutunun 900 token altında kaldığını da denetler.

`Tests/fixture.html` elle sınama için yerel bir sayfadır: form, iletişim kutusu düğmeleri, gecikmeli öğe, tablo ve fetch içerir. `tabs new` ile `file://` adresinden açılır.

## Lisans

[MIT](LICENSE)
