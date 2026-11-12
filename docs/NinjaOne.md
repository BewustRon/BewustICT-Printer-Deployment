# Bewust ICT - NinjaOne printerdeployment v1.1.0-PILOT

## Eén automation, één universele fabrikantdriver per merk

Het beoogde eindresultaat is een volledig door NinjaOne aangestuurde installatie: merk, printernaam, IP en afdrukinstellingen invoeren; het script downloadt en valideert indien nodig de **universele driver van de fabrikant**, installeert de driver en maakt de RAW TCP/9100-poort en Windows-printerqueue aan. **Geen modelafhankelijke driver- of scriptconfiguratie.** Dit is niet Microsoft Universal Print (cloud).

**Belangrijk: dit is een pilot, en de merkdekking is nog niet compleet.** Zet de automation niet automatisch tenantbreed aan.

## NinjaOne-script

Vervang voor een HP-, Kyocera- of Brother-pilot de volledige inhoud van de bestaande NinjaOne-automation door:

[`scripts/NinjaOne-Printer-Bootstrap-v1.1.0-PILOT.ps1`](../scripts/NinjaOne-Printer-Bootstrap-v1.1.0-PILOT.ps1)

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
- **Belangrijk:** vanaf deze release gebruikt `catalog/drivers.json` schemaVersion 2. Oude v0.9/v1.0-launchers stoppen bij HP/Kyocera daarom veilig vóór installatie. Vervang de vastgepinde launcher door **v1.1.0-PILOT**.
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
