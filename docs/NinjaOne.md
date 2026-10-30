# NinjaOne printerautomation - v0.8.0 PILOT

**Gebruik een enkele NinjaOne PowerShell automation.** Plak de launcher uit [scripts/NinjaOne-Printer-Bootstrap.ps1](../scripts/NinjaOne-Printer-Bootstrap.ps1) in het scriptveld. De launcher downloadt de vastgepinde, SHA256-gecontroleerde centrale PowerShell-code. Voer uit onder **Windows PowerShell 5.1 x64**, **Run as System**. Niet automatisch op alle klanten uitrollen voor de pilot is afgerond.

## Script variables in NinjaOne

De **Calculated name** moet exact overeenkomen met onderstaande kolom. Verwijder de oude variabelen `biPrinterName`, `biPrinterIP`, `biColorMode`, `biDuplexMode`, `biPaperSize`, `biPaperTray`, `biAction`, `biSetDefaultPrinter` voordat je deze automation test. De variabelen worden als omgevingsvariabelen doorgegeven; de centrale code leest ze uit.

| Label | Calculated name | Type | Instellingen |
|---|---|---|---|
| Actie | `actie` | Dropdown | `Controleren`, `Installeren`, `Verwijderen`, `Offline testen`, `Test opruimen` |
| Printer naam | `printerNaam` | String/Text | Vrij invulveld |
| Printer IP adres | `printerIpAdres` | IP address | Vrij invulveld |
| Printer merk | `printerMerk` | Dropdown | `HP`, `Epson`, `Canon`, `Kyocera`, `Ricoh`, `Brother` |
| Kleur afdrukken | `kleurAfdrukken` | Dropdown | `Zwart-wit`, `Kleur` |
| Dubbelzijdig afdrukken | `dubbelzijdigAfdrukken` | Dropdown | `Uit`, `Lange zijde`, `Korte zijde` |
| Papierformaat | `papierformaat` | Dropdown | `A4`, `A3`, `A5` |
| Papierlade | `papierlade` | Dropdown | `Automatisch`, `Cassette 1`, `Cassette 2`, `Cassette 3`, `Cassette 4` |
| Standaardprinter | `instellenAlsStandaardprinter` | Checkbox | Standaard uit |
| Driver naam (optioneel) | `driverNaam` | String/Text | Leeg voor automatische Epson-driverinstallatie; alleen invullen bij al lokaal geinstalleerde driver |

**Geen Parameters invullen.** `driverCatalogusUrl` hoeft niet als variabele te worden aangemaakt: de centrale code kent de GitHub-URL.

## Eerste test vanaf eigen pc met NinjaOne

- **Actie:** Installeren
- **Printer naam:** `BIC NINJA PILOT - Blanco Kleur`
- **Printer IP adres:** `192.0.2.50` (gereserveerd testadres; hoeft niet bereikbaar te zijn)
- **Printer merk:** Epson
- **Kleur afdrukken:** Kleur
- **Dubbelzijdig afdrukken:** Uit
- **Papierformaat:** A4
- **Papierlade:** Cassette 2
- **Standaardprinter:** uit
- **Driver naam:** leeg

Selecteer het **eigen testapparaat**, niet een klantorganisatie, en voer de automation **handmatig** uit. Succes is `NINJAONE_PRINTER_AUTOMATION_OK` en een nieuwe queue met de juiste Epson-driver en Cassette 2. De eerder gemaakte BIC V08-printers blijven ongemoeid.

Elke printerqueue vergt een eigen run met ingevulde variabelen; de Epson-klantpilot heeft drie queues, maar er is slechts **een script**.

## Werking en beperkingen

- Epson Universal Print Driver v2.122.00 wordt, indien ontbrekend, direct van `ftp.epson.com` opgehaald en gecontroleerd op SHA256 en Authenticode. Epson is offline getest op Windows GitHub Actions en op de eigen engineer-pc.
- Printerqueues worden via Standard TCP/IP met RAW 9100 aangemaakt zonder ping of discovery.
- Papierlade wordt via een vastgepinde helper op de Windows-spooler geconfigureerd en opnieuw gecontroleerd.
- Voor HP, Canon, Kyocera, Ricoh, Brother staat de drivercatalogus nog op `pending`; zonder al vooraf geinstalleerde geschikte driver stopt het script.
- Dit is een **PILOT**: printermodelcompatibiliteit, daadwerkelijke fysieke afdruk en uitrol via NinjaOne zijn nog te bevestigen. Automatische standaardprinter via gebruikersaanmelding is ook nog niet gevalideerd in de pilot.
- Opslaan van het uitrolscript als lokale NinjaOne-automation maakt de scriptversie vast. Nieuwe commits naar GitHub wijzigen de bestaande launcher niet automatisch.

## Uitgebreide bewijzen

- [Integratietest op GitHub (volledig Epson, 3 queues)](https://github.com/BewustRon/BewustICT-Printer-Deployment/actions/runs/41069887307)
- De eigen Windows PowerShell-run bevestigde `CASSETTE_CONFIRMED` en `SUCCESS` voor de 3 Epson-queues.
