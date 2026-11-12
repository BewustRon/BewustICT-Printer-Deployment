# Bewust ICT - NinjaOne printerdeployment v1.0.0-PILOT

## Eén automation, één universele fabrikantdriver per merk

Het beoogde eindresultaat is een volledig door NinjaOne aangestuurde installatie: merk, printernaam, IP en afdrukinstellingen invoeren; het script downloadt en valideert indien nodig de **universele driver van de fabrikant**, installeert de driver en maakt de RAW TCP/9100-poort en Windows-printerqueue aan. **Geen modelafhankelijke driver- of scriptconfiguratie.** Dit is niet Microsoft Universal Print (cloud).

**Belangrijk: dit is een pilot, en de merkdekking is nog niet compleet.** Zet de automation niet automatisch tenantbreed aan.

## NinjaOne-script

Vervang voor een Brother-pilot de volledige inhoud van de bestaande NinjaOne-automation door:

[`scripts/NinjaOne-Printer-Bootstrap-v1.0.0-PILOT.ps1`](../scripts/NinjaOne-Printer-Bootstrap-v1.0.0-PILOT.ps1)

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
| HP | Nog niet vrijgegeven | HP Universal Print Driver PCL6; catalogus `pending` |
| Kyocera | Nog niet vrijgegeven | Kyocera KX Universal; catalogus `pending` |
| Canon | Nog niet vrijgegeven | Catalogus `pending` |
| Ricoh | Nog niet vrijgegeven | Catalogus `pending` |

De oude `Brother Mono Universal Printer (PCL)` is **niet** geschikt voor deze zero-touch aanpak: na de Windows-installatie vereist deze driver een handmatige apparaatkeuze. De v1.0.0-route gebruikt de andere officiële **Enhanced Generic PCL5e**. De installatieroute valideert SHA256 en digitale handtekeningen van de download en CAT, gebruikt een vastgepinde extractor en raakt alleen door dit script gemarkeerde queues aan.

## Pilotstappen voor Brother

1. Controleer dat de printer RAW TCP/9100 en PCL5e ondersteunt, en de werkplek TCP/9100 kan bereiken.
2. Run de bijgewerkte NinjaOne-automation handmatig met `Actie=Installeren`, `printerMerk=Brother`, de gewenste `printerNaam` en `printerIpAdres`; zet `kleurAfdrukken=Zwart-wit`, `papierlade=Automatisch` en `driverNaam` **leeg**.
3. Controleer `NINJAONE_PRINTER_AUTOMATION_OK`; vervolgens `Get-Printer -Name '<printer>' | Format-List Name,DriverName,PortName,Comment`.
4. De verwachte driver is `Brother PCL5e Driver`, de poort heet `BIC_TCP_<IP>_9100`. Bij een bestaande, door v0.9 gemarkeerde queue kan opnieuw `Installeren` de driver bijwerken zonder de queue-naam te veranderen.
5. **Verifieer een echte afdruk bij de klant.** Succes in Windows CI bewijst driverregistratie, poort en queue, niet dat iedere Brother-printer fysiek afdrukt.

## Logs

`C:\ProgramData\BewustICT\PrinterDeployment\Logs\`. `PILOT` is expliciet onderdeel van de scriptversie; pas na een geslaagde pilot breed uitrollen.
