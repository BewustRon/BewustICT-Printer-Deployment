# HP en Kyocera - zero-touch universal printerpilot (v1.1.0)

**Eén universele driver per merk; geen printermodellen of handmatige driverpreinstallatie.** Deze aanpak is bedoeld voor het bestaande NinjaOne-script `PILOT - Bewust ICT Printer toevoegen v1.0`. NinjaOne-velden blijven hetzelfde: merk, IP, naam, kleur/duplex, A4, papierlade, standaardprinter. `driverNaam` blijft leeg.

## Geteste drivers (Windows x64)

| Merk | Windows-drivernnaam | Fabrikantpakket | SHA256 / beveiliging |
|---|---|---|---|
| HP | `HP Universal Printing PCL 6` | `upd-pcl6-win11-x64-8.2.0.26819.zip` rechtstreeks van `ftp.hp.com` | Vastgepinde pakket-SHA256, HP CAT, HP-certificaat `BE845AAF486FD9F15D2C71BEED66E8AE21429EEA` |
| Kyocera | `Kyocera Generic color KX` | `KX_Universal_Printer_Driver_zip.download.zip` rechtstreeks van `www.kyoceradocumentsolutions.eu` | Vastgepinde pakket-SHA256, KX x64 CAT, KYOCERA-certificaat `AA2098F3E70AC791261FF95930AE4C981B28C0D3` |

Beide zijn op **12 november 2026** op een schone Windows GitHub Actions runner gecontroleerd: pakket en CAT digitaal geldig, uitgaand van het exacte certificaat; staging naar Windows Driver Store met `pnputil`, `Add-PrinterDriver` en installatie van een offline TCP-IP-printerqueue via RAW 9100. **Echte fysieke afdrukken zijn nog niet bevestigd.**

## Waarom Windows vroeger bleef hangen

De 2026-fabrikantdrivers zijn authentiek ondertekend, maar het Windows **Trusted Publishers**-archief bevat hun individuele ondertekeningscertificaten niet. SetupAPI geeft dan `0x800b0109` en `0xe0000242` en probeert een interactief toestemmingsvenster te tonen. In NinjaOne `SYSTEM` kan niemand dat venster beantwoorden. Microsoft beschrijft dit in [Troubleshooting Driver Signing Installation](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/troubleshooting-driver-signing-installation) en [Trusted Publishers Certificate Store](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/trusted-publishers-certificate-store).

## Automatische installatie met beveiligingsgrenzen

1. Download via HTTPS vanaf de originele fabrikant; controleer exact het SHA256 van het complete pakket uit de catalogus.
2. Controleer ZIP-bestandspaden, de uitpaklimiet, INF en CAT, Windows Authenticode-status, uitgeversnaam én de exacte gepinde certificaatvingerafdruk.
3. Controleer of de fabrikant als uitgever vertrouwd is; voeg **uitsluitend het exacte gepinde leaf-certificaat** toe aan `LocalMachine\TrustedPublisher` als dat ontbreekt. Nooit aan Root, nooit signatuurbeleid verlagen. Dit verandert wel de machinebrede trust: **andere software/driverpakketten die met dezelfde OEM-signingcertificaat zijn ondertekend kunnen hierdoor zonder de initiële publisherbevestiging worden geïnstalleerd**. Daarom gebeurt dit alleen in de expliciet geteste en goedgekeurde pilotcatalogus.
4. Stage de INF met een maximale proceslooptijd van 180 seconden; registreer de exacte universele driver en verifieer die met `Get-PrinterDriver`.
5. Voeg de TCP/IP-printerqueue toe en stel de via NinjaOne gekozen afdrukopties in. Wanneer staging faalt en de trust net werd toegevoegd, probeert het script deze cert-import terug te draaien.

**Belangrijk:** de catalogus krijgt **schemaVersion 2**. Bestaande v0.9 en v1.0 bootstrap-commits ondersteunen alleen schemaVersion 1 en stoppen daardoor bij HP/Kyocera veilig vóór de nieuwe driverinstallatieroute. Een nieuwe *vastgepinde* NinjaOne-bootstrap v1.1 is vereist voordat HP/Kyocera geïnstalleerd kunnen worden.

## Certificaatrotatie

- Kyocera leaf-certificaat uit gecontroleerd pakket vervalt **8 december 2026**. De KX-pakket- en certificaatpin moeten voor die datum opnieuw onderzocht worden.
- HP leaf-certificaat vervalt **19 april 2027**.
- Bij gewijzigde leveranciercertificaten of downloadbestanden blijft de installatie **fail-closed** tot de SHA256 en signer-pins opnieuw door CI zijn goedgekeurd.

## Restbeperkingen

Geen individuele printermodelselectie. De gekozen driver vereist wel dat de daadwerkelijke printer de bijbehorende printertaal/poort ondersteunt. Kleuren/duplex/printopties en de fysieke testpagina moeten bij de klant gecontroleerd worden. Windows Protected Print Mode en printdriverbeveiligingsbeleid worden door dit script niet uitgeschakeld.

Deze pilot vervangt geen brede certificaatdistributie via Intune of Group Policy. De gekozen certificaatvertrouwenswijziging moet voor productie expliciet door Bewust ICT worden geaccepteerd.
