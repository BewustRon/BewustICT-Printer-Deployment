# Bewust ICT - NinjaOne printerdeployment v1.2.1-PILOT

## Eén automation, één universele fabrikantdriver per merk

Het beoogde eindresultaat is een volledig door NinjaOne aangestuurde installatie: merk, printernaam, IP en afdrukinstellingen invoeren; het script downloadt en valideert indien nodig de **universele driver van de fabrikant**, installeert de driver en maakt de RAW TCP/9100-poort en Windows-printerqueue aan. **Geen modelafhankelijke driver- of scriptconfiguratie.** Dit is niet Microsoft Universal Print (cloud).

**Belangrijk: dit is een pilot, en de merkdekking is nog niet compleet.** Zet de automation niet automatisch tenantbreed aan.

## NinjaOne-script

Vervang voor een HP-, Kyocera- of Brother-pilot de volledige inhoud van de bestaande NinjaOne-automation door:

[`scripts/NinjaOne-Printer-Bootstrap-v1.2.1-PILOT.ps1`](../scripts/NinjaOne-Printer-Bootstrap-v1.2.1-PILOT.ps1)

De bootstrap is aan een specifieke commit en SHA256 gepind; wijzigingen aan losse `main`-scripts wijzigen de ingeplakte NinjaOne-automation niet. De bootstrap erft NinjaOne Script Variables als procesomgevingsvariabelen. Voer uit via **Windows PowerShell 5.1 x64**, **Run as SYSTEM**.

## NinjaOne Script Variables

| Label | Calculated name | Type | Waarden |
|---|---|---|---|
| Actie | `actie` | Dropdown | `Controleren`, `Installeren`, `Verwijderen`, `Offline testen`, `Test opruimen` |
| Printernaam | `printerNaam` | String | Vrij |
| Printer IP | `printerIpAdres` | IP address | Vrij |
| Merk | `printerMerk` | Dropdown | `HP`, `Epson`, `Canon`, `Kyocera`, `Ricoh`, `Brother` |
| Kleur | `kleurAfdrukken` | Dropdown | `Zwart-wit`, `Kleur` |
| Dubbelzijdig | `dubbelzijdigAfdrukken` | Dropdown | `Uit`, `Lange zijde`, `Korte zijde` |
| Papierformaat | `papierformaat` | Dropdown | `A4`, `A3`, `A5` |
| Papierlade | `papierlade` | Dropdown | `Automatisch`, `Cassette 1`, `Cassette 2`, `Cassette 3`, `Cassette 4` |
| Standaardprinter | `instellenAlsStandaardprinter` | Checkbox | Normaal uit |
| Drivernaam (optioneel) | `driverNaam` | String | **Leeg laten voor automatische driverinstallatie** |

Geen handmatige Parameters instellen en geen oude `bi*`-variabelen laten staan.

## Verplichte papierlade ook zonder printerverbinding (v1.2.0)

Het NinjaOne-veld `papierlade` gebruikt **logische lade-nummers**, niet de letterlijke Windows-drivertekst. `Cassette 2` betekent **fysieke lade 2** en wordt door de nieuwe helper afgezet tegen de **offline geadverteerde bronnen van de reeds geïnstalleerde fabrikantdriver**:

- HP Universal PCL 6: `Cassette 2` → `Tray 2` / `Lade 2` (offline op schone Windows GitHub-runner daadwerkelijk `Tray 2` met `RawKind=260`).
- Epson: `Cassette 2` → `Cassette 2`.
- Andere OEM-drivers: `Tray 1..4`, `Lade 1..4`, `Papierlade 1..4`, `Cassette 1..4` en `Paper Tray 1..4` worden **alleen bij exact één werkelijk gerapporteerde bron** als synoniemen behandeld.

De helper schrijft de **bij die driver geregistreerde RawKind** in de globale printer-DEVMODE via Windows-spooler-API's en leest de opgeslagen waarde terug. Er wordt **geen** printerdetectie, SNMP, WSD of netwerkaansluiting gebruikt. De printer hoeft dus niet op kantoor aanwezig te zijn. Er wordt **nooit** stilzwijgend teruggevallen op Automatisch selecteren of blind een ongedocumenteerd RAW-ID gekozen. Bij ontbrekende of meerdere passende ladebeschrijvingen eindigt de pilot met `TRAY_NOT_ADVERTISED_OFFLINE` / `TRAY_AMBIGUOUS`. De printerqueue kan dan al bestaan; pas de lademapping/capability gecontroleerd aan en voer `Installeren` opnieuw uit.

**Verificatiegrens:** deze controle bewijst dat de Windows-driver de gekozen lade als globale standaard accepteert. Het bewijst niet dat de daadwerkelijke printer die fysieke lade bezit of dat een applicatie- of gebruikersprofiel met eigen afdrukvoorkeuren niet anders print. Controleer bij de klant één fysieke afdruk.

## Kyocera: Windows MAX_PATH fix (v1.2.1)

De originele Kyocera KX Universal driver-ZIP is ~251 MB en bevat geneste
`MetaData/en-US/*.devicemetadata-ms` bestanden. De eerdere v1.2.0-versie
pakte deze uit onder het lange `C:\ProgramData\BewustICT\PrinterDeployment\DriverPackages\<volledige SHA256>\Expanded-staging-<GUID>` pad.
Op `PC-JOHNNYWEIJER` werd dat pad 275 tekens lang; Windows PowerShell 5.1 /
.NET Framework gooide daardoor `DirectoryNotFoundException` tijdens het uitpakken.

Vanaf **v1.2.1-PILOT** blijft de originele ZIP SHA256-gecontroleerd in de
bestaande drivercache, maar wordt de inhoud transactioneel uitgepakt onder
`C:\ProgramData\BICPD\<eerste 24 hex van SHA256>\Expanded`.
Hierdoor blijven OEM-submappen kort genoeg en wordt een afgebroken uitpakactie
niet als geslaagd gecachet. Het **volledige** SHA256 en de CAT-handtekening +
pinned uitgevercertificaat worden nog steeds gecontroleerd.

**Gebruik de nieuwe volledige v1.2.1-bootstrap uit NinjaOne.** De oude
launcher v1.2.0 is gepind op een oudere centrale commit en wordt niet automatisch
bijgewerkt als de GitHub-branch `main` verandert.

De papierlade- en kleurinstellingen zijn niet gewijzigd; als een lade offline
niet door de fabrikantdriver wordt gepubliceerd, blijft de verplichte lademapping
fail-closed. Dit is een afzonderlijke beperking van bijvoorbeeld HP Lade 3.
Fysieke testafdruk op de klantlocatie blijft vereist.

## Huidige driverstatus

| Merk | Automatische driverinstallatie | Driver / opmerking |
|---|---|---|
| Epson | Pilot getest | `EPSON Universal Print Driver` 2.122.00 |
| Brother | Windows CI geslaagd, fysieke pilot open | **`Brother PCL5e Driver`**; Brother Enhanced Generic PCL 1.09 van officiële Brother-site. **Geen apparaat-selectiewizard**; uitsluitend monochroom en PCL5e-compatibele printers |
| HP | Windows CI geslaagd, fysieke pilot open | **`HP Universal Printing PCL 6`** v8.2.0; fabrikantcertificaat exact gepind |
| Kyocera | Windows CI geslaagd, fysieke pilot open | **`Kyocera Generic color KX`** v8.7.0422; fabrikantcertificaat exact gepind |
| Canon | Nog niet vrijgegeven | Catalogus `pending` |
| Ricoh | Nog niet vrijgegeven | Catalogus `pending` |

De oude `Brother Mono Universal Printer (PCL)` is **niet** geschikt voor deze zero-touch aanpak: na de Windows-installatie vereist deze driver een handmatige apparaatkeuze. De v1.1.0-route gebruikt de andere officiële **Enhanced Generic PCL5e**. De installatieroute valideert SHA256 en digitale handtekeningen van de download en CAT, gebruikt een vastgepinde extractor en raakt alleen door dit script gemarkeerde queues aan.

## HP/Kyocera v1.1 - beveiliging, compatibiliteit en pilot

- **Volledig automatisch**: één universele OEM-driver per merk, zonder printermodel en zonder handmatige driverinstallatie.
- **Belangrijk:** vanaf deze release gebruikt `catalog/drivers.json` schemaVersion 2. Oude v0.9/v1.0-launchers stoppen bij HP/Kyocera daarom veilig vóór installatie. Vervang de vastgepinde launcher door **v1.2.1-PILOT**.
- De fabrikantdownload wordt via SHA256 en de CAT-ondertekening gevalideerd. Het script controleert ook de *exacte* fingerprint en voegt zo nodig uitsluitend het overeenkomstige certificaat toe aan `LocalMachine\TrustedPublisher`, nooit aan Root. **Dit verleent het OEM-signercertificaat machinebrede uitgeversvertrouwensrechten**. Bij mislukte driverstaging wordt een nieuw toegevoegde trust zo mogelijk teruggedraaid.
- **Certificaatrotatie:** Kyocera's gecontroleerde signingcertificaat verloopt op **8 december 2026**; HP's op **19 april 2027**. Update het gecertificeerde OEM-pakket vóór die datum.
- **Pilot:** kies `Installeren`, `printerMerk=HP` of `Kyocera`, vul naam/IP en afdrukinstellingen in, laat `driverNaam` leeg. Controleer na `NINJAONE_PRINTER_AUTOMATION_OK` met `Get-Printer -Name '<printer>'` de driver, poort en een echte fysieke afdruk. Geen model-specifieke code; printertaal en RAW TCP/9100 moeten wel ondersteund zijn.
- Zie [HP/Kyocera beveiligingsontwerp en testbewijs](HP-Kyocera-Universal-Printer-PILOT.md). Windows Protected Print Mode en andere beveiligingspolicies worden niet afgezwakt.

## Pilotstappen voor Brother

1. Controleer dat de printer RAW TCP/9100 en PCL5e ondersteunt, en de werkplek TCP/9100 kan bereiken.
2. Run de bijgewerkte NinjaOne-automation handmatig met `Actie=Installeren`, `printerMerk=Brother`, de gewenste `printerNaam` en `printerIpAdres`; zet `kleurAfdrukken=Zwart-wit`, `papierlade=Automatisch` en `driverNaam` **leeg**.
3. Controleer `NINJAONE_PRINTER_AUTOMATION_OK`; vervolgens `Get-Printer -Name '<printer>' | Format-List Name,DriverName,PortName,Comment`.
4. De verwachte driver is `Brother PCL5e Driver`, de poort heet `BIC_TCP_<IP>_9100`. Bij een bestaande, door v0.9 gemarkeerde queue kan opnieuw `Installeren` de driver bijwerken zonder de queue-naam te veranderen.
5. **Verifieer een echte afdruk bij de klant.** Succes in Windows CI bewijst driverregistratie, poort en queue, niet dat iedere Brother-printer fysiek afdrukt.

## Logs

`C:\ProgramData\BewustICT\PrinterDeployment\Logs\`. `PILOT` is expliciet onderdeel van de scriptversie; pas na een geslaagde pilot breed uitrollen.
