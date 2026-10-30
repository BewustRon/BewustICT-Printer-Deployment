# Bewust ICT - Centrale Printerdeployment (v0.5.1-PILOT)

**Repository:** https://github.com/BewustRon/BewustICT-Printer-Deployment

**Drivercatalogus:** https://raw.githubusercontent.com/BewustRon/BewustICT-Printer-Deployment/main/catalog/drivers.json

Eén NinjaOne-automation voor HP, Epson, Canon, Kyocera, Ricoh en Brother, met een per merk goed te keuren universele driver. Printers mogen tijdens **installatie offline zijn**: Windows krijgt een Standard TCP/IP-poort (RAW/9100) en een printerqueue. De eerste fysieke afdruk moet na oplevering apart worden gecontroleerd.

## Huidige status

- **PILOT**, niet in productie gevalideerd.
- `scripts/Deploy-BewustICTPrinter.ps1` bevat de implementatie.
- `catalog/drivers.json` heeft voor alle zes merken nog `status: pending`: er zijn bewust **geen ongeverifieerde downloadlinks, SHA256's of driverbestanden** toegevoegd.
- De catalogus-URL is standaard rechtstreeks in het script opgenomen, maar alle zes merkrecords staan nog op `pending`. Automatische installatie zonder lokaal beschikbare driver stopt terecht.
- Geen onbekende software uitvoeren; alleen ZIP met de driverbestanden (INF/CAT) en een goedgekeurde SHA256 + CAT-handtekening.
- Een *reeds geïnstalleerde* driver kan voor de technische Windows-pilot worden geselecteerd via het optionele NinjaOne-veld `driverNaam`.
- De scriptcode is statisch gecontroleerd, maar niet uitgevoerd op Windows/NinjaOne.

## Waarom geen driverbestanden in deze repository?

- Voor herdistributie van de fabrikantdriver is een expliciet toegestane gebruiksvorm nodig. Een officiële downloadpagina is geen herdistributierecht.
- GitHub heeft bestandsgroottelimieten voor gewone repo-objecten; Kyocera's KX Universal pakket is rond 239 MB. Grote toegestane ZIP-pakketten horen bijvoorbeeld bij Releases of een ander beheerd distributieplatform.
- **Private GitHub-repositories zijn niet anoniem downloadbaar vanaf klant-pc's.** We geven geen GitHub-PAT of machine-accounttoken aan iedere klantwerkplek. Als de broncode privé blijft, moet de goedgekeurde catalogus en driverdownload via een afzonderlijk voor endpoints bereikbaar HTTPS-distributiekanaal worden gepubliceerd. Vermijd privé-toegangstokens in NinjaOne scriptvariabelen die op endpoints terechtkomen.

## Pilot Epson WF-C20600

Voer na offline driver-prestaging de automation drie maal uit:

| Naam | IP | Kleur | Duplex | Papier | Lade |
|---|---|---|---|---|---|
| Blanco Kleur | 192.168.53.50 | Kleur | Uit | A4 | Cassette 2 |
| Blanco Zwart Wit | 192.168.53.50 | Zwart-wit | Uit | A4 | Cassette 2 |
| CMR | 192.168.53.50 | Zwart-wit | Uit | A4 | Cassette 1 |

**Beperking:** de fysieke cassette wordt alleen ingesteld als de printerdriver de exacte naam `Cassette 1`, `Cassette 2`, enz. ondubbelzinnig adverteert in PrintCapabilities. Anders stopt het script met een foutmelding nadat de queue mogelijk al is aangemaakt. Geen gok op `Tray1`.

## Opzetten

1. De repository `BewustRon/BewustICT-Printer-Deployment` en het script met centrale catalogus-URL zijn gepubliceerd.
2. De catalogus is zonder GitHub-token bereikbaar, maar er zijn nog geen goedgekeurde driverdownloadpakketten.
3. Controleer per vendor: modelcompatibiliteit, Windows x64, driverpagina, exacte INF-naam, ondertekende CAT, SHA256, en distributierecht. Markeer het driverrecord pas als `approved` na praktijkproef.
4. Maak NinjaOne-variabelen volgens `docs/NinjaOne.md` aan. Draai als `SYSTEM` in Windows PowerShell 64-bit.
5. Test eerst `Controleren` of `Installeren` op één werkplek, verifieer queue, configuratie, testafdruk, cassette en defaultprinter na nieuwe logon.

## Verificatie en fouten

Logs: `C:\ProgramData\BewustICT\PrinterDeployment\Logs\`.
PrintCapabilities-diag: `C:\ProgramData\BewustICT\PrinterDeployment\Diagnostics\`.

- Een ZIP met andere SHA256 wordt **geweigerd**.
- Een INF zonder een geldige ondertekende CAT wordt **geweigerd**.
- Een queue die niet door dit TCP-script is gemarkeerd wordt **niet aangepast of verwijderd**.
- Het script verwijdert bij `Verwijderen` alleen de beheerde queue. Drivers en gedeelde poorten blijven staan.
- Bestaande v0.4.0 IPP-queues met gelijknamige queue worden niet automatisch overgenomen; maak eerst een migratieplan zodat de afdrukroute niet ongemerkt verandert.

## Microsoft-documentatie

- `Add-PrinterPort`: https://learn.microsoft.com/en-us/powershell/module/printmanagement/add-printerport
- `Add-PrinterDriver`: https://learn.microsoft.com/en-us/powershell/module/printmanagement/add-printerdriver
- `pnputil`: https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax

## Versiebeheer

Nieuwe driverpakketten uitsluitend na review en een gecontroleerde pilot. Beheer `status=approved` en exacte SHA256 als change. Geen automatische vendor-updates zonder controle.
## Herkomst en security

De catalogus op `main` is een veranderlijke bron. Changes aan drivergoedkeuringen moeten via review lopen. Clients accepteren alleen downloadpakketten waarvan de volledige ZIP SHA256 overeenkomt met het catalogusrecord en de CAT-handtekening geldig is. Catalogusvalidatie en PowerShell-parser draaien via GitHub Actions; dit zijn statische controles, geen Windows 11-printerpilot.
