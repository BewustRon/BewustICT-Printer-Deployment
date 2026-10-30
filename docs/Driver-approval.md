# Procedure fabrikantdriver goedkeuren

1. Download de actuele x64 Universal Driver uitsluitend vanaf de officiële fabrikantsite en controleer modelondersteuning en producteisen.
2. Controleer licentie of schriftelijke toestemming voor herdistributie. Als dit niet toegestaan of onzeker is, upload geen binair pakket naar GitHub; gebruik een geautoriseerde vendor-downloadbron als die een stabiele directe ZIP biedt.
3. Pak een eventuele vendor EXE alleen op een gecontroleerde beheerdersomgeving uit. Zet alle noodzakelijke INF/CAT/driverbestanden om in één ZIP. Voer de EXE niet uit op klantwerkplekken.
4. Verifieer op een Windows-pilotmachine de digitale CAT-handtekening, de werkelijke drivernaam en de werking op het specifieke model. Kijk of fysieke lades correct kunnen worden ingesteld.
5. Bepaal SHA256 van de **uiteindelijk te publiceren ZIP** met `Get-FileHash .\driver.zip -Algorithm SHA256`.
6. Publiceer het pakket uitsluitend op een toegestaan, voor de endpoint bereikbare HTTPS-bron. Gebruik GitHub Releases voor grotere pakketten alleen als herdistributie expliciet is toegestaan. Geen PAT op endpoints voor private GitHub-repo's.
7. Vul in `catalog/drivers.json`: `status=approved`, `driverName`, `downloadUrl`, `sha256`, `infRelativePath`, `catRelativePath`, `signerSubjectContains`.
8. Test eerst één printerqueue in Windows 11 in een gescheiden pilot. Daarna pas een update in de gedeelde NinjaOne-automation.

## Risico's

- RAW TCP/9100 werkt niet met alle modellen; een printer met uitsluitend IPP moet een aparte gecontroleerde route krijgen.
- Vendor Universal Drivers verschillen in taal: Brother Universal PCL is volgens Brother alleen zwart-wit. Een Canon/MFP of Epson kan meerdere beschikbare printertalen hebben.
- Een offline printer kan niet zijn hardwareafwerking, lades of verbinding bevestigen: test later fysiek.
- Na herinstallatie kan de door Windows geregistreerde drivernaam anders zijn dan de productnaam op de supportpagina; lees de INF/Windows-driverlijst.