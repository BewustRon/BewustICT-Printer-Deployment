# Fabrikantdrivers: gecontroleerde bronnen (30 oktober 2026)

Dit is een bronnenlijst voor Windows x64. Geen van de zes drivers is al vrijgegeven voor automatische uitrol.

| Merk | Officiele kandidaat | Beperking |
|---|---|---|
| HP | [HP Universal Print Driver PCL6](https://support.hp.com/us-en/drivers/hp-universal-print-series-for-windows/model/3271558) | Actuele x64-versie, INF en licentie nog verifiëren |
| Epson | [Epson Universal Print Driver 2.122.00](https://epson.com/Support/Printers/All-In-Ones/WorkForce-Series/Epson-WorkForce-Enterprise-WF-C20600/s/SPT_C11CH86201?review-filter=Windows+11) - EUPD_x64_212200.exe | Geen publieke kopie zonder aparte herdistributietoestemming |
| Canon | [Generic Plus UFR II 3.50](https://www.canon.com.au/support/sims-content?cid=0241599B76C54099A5413864568FEFCE&ctype=dr&pid=7d8fb1cfb2254450a9f983d63fae334e) | Alleen voor geschikte UFR II-modellen; downloadvoorwaarden verbieden herdistributie |
| Kyocera | [KX Universal 8.7.0422](https://www.kyoceradocumentsolutions.eu/en/support/downloads.name-L2V1L2VuL3ByaW50ZXJzL0ZTOTUzMERO.html) - 239 MB ZIP | EULA, CAT, INF en SHA256 nog valideren |
| Ricoh | [Ricoh Device Software Manager](https://www.ricoh.com/products/device-software-manager), incl. PCL6 Universal | Standalone offline driverpakket nog niet vastgesteld |
| Brother | [Universal PCL](https://support.brother.com/g/b/faqend.aspx?c=nl&faqid=faq00002993_001&lang=nl&prod=dcp8110dn_eu_as); [BR-Script3](https://help.brother-usa.com/app/answers/detail/a_id/67181/) | PCL is alleen monochroom; BR-Script3 is afhankelijk van modelondersteuning |

## Juridische beveiliging
De [Epson US Software License Agreement](https://epson.com/SoftwareLicenseAgreement) beperkt herdistributie en het plaatsen op een publiek toegankelijke server. De [Canon-downloadvoorwaarden](https://my.canon/en/support/0101310501?model=imageCLASS+LBP613Cdw) verbieden distributie aan derden. Controleer steeds de pakketlicentie die daadwerkelijk van toepassing is. Daarom publiceren wij geen kopie van deze binaries in onze openbare GitHub-repository.

Voor andere merken is toestemming nog niet bevestigd. Ook daar geen binair pakket publiceren zonder toestemming.

## Procedure om een kandidaat goed te keuren
1. Kies een ondersteund printermodel, architectuur en printertaal (PCL, PS, UFR II, ESC/P-R).
2. Download door een bevoegde engineer vanaf de officiele fabrikantsite; controleer de bijgevoegde licentie.
3. Bepaal de SHA256 en valideer de echte CAT-handtekening, INF-pad en Windows-drivernaam.
4. Test zonder netwerkverbinding naar de printer het aanmaken van een TCP/IP-queue op een Windows-testwerkplek.
5. Verifieer later de fysieke uitvoer, kleur, duplex en juiste cassette.
6. Leg een geautoriseerde HTTPS-downloadlocatie en exact hashgepind ZIP-pakket vast. Het huidige installatiescript accepteert alleen ZIP met INF/CAT, geen vendor EXE.
7. Vul dan pas de actieve catalogusvelden in en wijzig status naar approved. De huidige catalogus blijft bewust pending.

## Epson WF-C20600 pilot
De Epson UPD x64 v2.122.00 is de eerste kandidaat. Download en installeer deze op één testwerkplek volgens de voorwaarden van Epson. Lees de exacte drivernaam uit met Get-PrinterDriver. Gebruik de bestaande centrale NinjaOne-automation met optioneel driverNaam als de driver al lokaal geinstalleerd is. De fysieke Cassette 1 en 2 moeten apart worden gecontroleerd. De voorbereiding van de TCP/IP-queue is offline mogelijk, maar een printopdracht werkt pas als de printer en de gekozen protocol/poort bereikbaar zijn.
