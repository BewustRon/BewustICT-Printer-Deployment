# NinjaOne variabelen - Bewust ICT v0.6.0 PILOT

De waarde in de kolom **Calculated name** moet exact aansluiten op de naam die NinjaOne aan het script doorgeeft. Verwijder oude `bi*` variabelen en de drie-profielenvariabelen uit v0.3.0. Geen losse PowerShell Parameters instellen. Uitvoeren als **SYSTEM / Windows PowerShell 64-bit**.

| Zichtbare naam | Calculated name | Type | Opties of voorbeeld |
|---|---|---|---|
| Actie | `actie` | Dropdown | `Controleren` (default), `Installeren`, `Verwijderen`, `Offline testen`, `Test opruimen` |
| Printer naam | `printerNaam` | Tekst | `Blanco Kleur` |
| Printer IP adres | `printerIpAdres` | IP Address | `192.168.53.50` |
| Printer merk | `printerMerk` | Dropdown | `HP`, `Epson`, `Canon`, `Kyocera`, `Ricoh`, `Brother` |
| Driver naam (optioneel) | `driverNaam` | Tekst | exact naam die `Get-PrinterDriver` toont; alleen voor reeds geïnstalleerde drivers |
| Driver catalogus URL (optioneel) | `driverCatalogusUrl` | Tekst | optioneel; centrale GitHub-catalogus is al in het script ingesteld |
| Kleur afdrukken | `kleurAfdrukken` | Dropdown | `Zwart-wit` (default), `Kleur` |
| Dubbelzijdig afdrukken | `dubbelzijdigAfdrukken` | Dropdown | `Uit` (default), `Lange zijde`, `Korte zijde` |
| Papierformaat | `papierformaat` | Dropdown | `A4` (default), `A3`, `A5` |
| Papierlade | `papierlade` | Dropdown | `Automatisch` (default), `Cassette 1`, `Cassette 2`, `Cassette 3`, `Cassette 4` |
| Instellen als standaardprinter | `instellenAlsStandaardprinter` | Checkbox | uit (default) of aan |

Bij Installeren: gebruik `driverNaam` **of** een goedgekeurd merkrecord uit de automatisch ingestelde centrale catalogus. Zonder een van beide stopt de installatie bewust voordat er een queue wordt aangepast. De checkbox zet de standaardprinter bij de volgende gebruikersaanmelding; uitgevinkt wijzigt de bestaande voorkeur niet.

De drivercatalogus is voorlopig volledig `pending`. De URL **is al in het script ingevuld**: `https://raw.githubusercontent.com/BewustRon/BewustICT-Printer-Deployment/main/catalog/drivers.json`. Laat de optionele NinjaOne-variabele `driverCatalogusUrl` leeg, of maak die helemaal niet aan.

## Epson pilot

1. Installeer de officieel gedownloade en gecontroleerde Epson UPD op de testwerkplek, bijvoorbeeld met PnPUtil en Add-PrinterDriver volgens fabrikantdocumentatie.
2. Lees de **exacte** Windows-drivernaam met `Get-PrinterDriver | Select-Object Name`.
3. Vul die naam in bij `Driver naam (optioneel)`; selecteer `Epson`; gebruik de 3 queue-instellingen uit de README.
4. Test de cassetteconfiguratie op fysieke output; alleen Windows-configuratie is onvoldoende bewijs.
## Offline testen vanaf je eigen PC - zonder Epson
Dezelfde automation kan de **echte Windows Standard TCP/IP-poort + Add-Printer-code** testen zonder Epson-driver of Epson-netwerk. Kies bij Actie \`Offline testen\`. Andere NinjaOne-velden worden genegeerd; je hoeft niets in te vullen.

Het script gebruikt **192.0.2.50** (gereserveerd test-IP) en maakt drie queues aan:
- \`BIC TEST - Blanco Kleur\`
- \`BIC TEST - Blanco Zwart Wit\`
- \`BIC TEST - CMR\`

Dit is alleen een **queue/poort-installatietest** met een reeds aanwezige ingebouwde Windows-driver (Generic / Text Only, Microsoft PCL6 Class Driver of Microsoft PS Class Driver). Er wordt geen fabrikantdriver gedownload of gesimuleerd. Als de ingebouwde driver niet beschikbaar is, wordt de test afgebroken met een duidelijke melding.

Verwacht in de NinjaOne-uitvoer de regel \`OFFLINE_TEST_OK: 3/3\`. Controleer desgewenst de drie namen onder Windows **Printers en scanners**. Een tweede run is veilig (idempotent). Dit **bewijst niet** dat de Epson UPD, kleur, duplex, Cassette 1/2 of de fysieke afdruk werkt.

Opruimen: kies \`Test opruimen\`; alleen testqueues met onze unieke marker worden verwijderd. De bestaande standaardprinter blijft onaangeroerd.

Voor een proef zonder nieuwe NinjaOne-variabelen is er ook een korte, afzonderlijke NinjaOne PowerShell-runner in \`scripts/Run-OfflineTest-NinjaOne.ps1\` beschikbaar.
