#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - Universele TCP/IP printerdeployment via NinjaOne.
.DESCRIPTION
  Maakt een Windows-printerqueue aan met een Standard TCP/IP-poort, ook als de
  printer nog niet bereikbaar is. Gebruikt een exact vooraf geinstalleerde
  driver, een goedgekeurd INF-driverpakket uit een HTTPS-drivercatalogus of
  voor de Epson-pilot de officiele SHA256-gepinde Epson Universal Print Driver
  v2.122.00 rechtstreeks vanaf de fabrikantsite.

  OFFLINE TEST: Actie='Offline testen' maakt drie veilige BIC TEST-queues aan
  op het gereserveerde IP 192.0.2.50 met een Windows-testdriver.
  Actie='Test opruimen' verwijdert alleen die gemarkeerde testqueues.

  PILOT: Windows GitHub Actions test op Epson UPD, queueconfiguratie en ladekeuze
  is geslaagd. NinjaOne uitrol en fysieke afdrukken zijn nog niet bewezen.
  Niet breed inzetten voordat modelcompatibiliteit en printtest zijn gedaan.

  Veiligheidsgrenzen:
  - Geen IPP-discovery, geen ping vereist voor installatie.
  - Download alleen HTTPS + een vooraf vastgelegde SHA256 + geldige CAT-signatuur.
  - Epson SFX EXE wordt alleen als ZIP/archief uitgepakt, nooit uitgevoerd.
  - Overige merken: alleen vooraf goedgekeurde ZIP met INF/CAT.
  - Verwijderen en wijzigen alleen voor door dit script gemarkeerde queues.
  - Een afwijkende papierlade wordt nooit aangenomen zonder bevestiging.
  - Deze versie gebruikt RAW TCP/9100; check dat de printer dit ondersteunt.
#>
[CmdletBinding()]
param(
    [string]$Actie = 'Controleren',
    [string]$PrinterNaam = '',
    [string]$PrinterIpAdres = '',
    [string]$PrinterMerk = '',
    [string]$DriverNaam = '',
    [string]$DriverCatalogusUrl = 'https://raw.githubusercontent.com/BewustRon/BewustICT-Printer-Deployment/main/catalog/drivers.json',
    [string]$KleurAfdrukken = 'Zwart-wit',
    [string]$DubbelzijdigAfdrukken = 'Uit',
    [string]$Papierformaat = 'A4',
    [string]$Papierlade = 'Automatisch',
    [string]$InstellenAlsStandaardprinter = 'false'
)
$ErrorActionPreference = 'Stop'
$Version = '0.8.0-PILOT'
$Root = Join-Path $env:ProgramData 'BewustICT\PrinterDeployment'
$LogDir = Join-Path $Root 'Logs'
$PkgDir = Join-Path $Root 'DriverPackages'
$DiagnosticsDir = Join-Path $Root 'Diagnostics'
@($LogDir,$PkgDir,$DiagnosticsDir) | ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
$LogFile = Join-Path $LogDir ('TCP-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
$MarkerPrefix = 'BewustICT-TCP|'

function Write-Log {
    param([string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $Line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    Write-Host $Line
    Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value $Line
}
function Read-NinjaValue {
    param([string[]]$Names,[string]$Fallback)
    $Hit = @()
    foreach ($Name in $Names) {
        $Value = [Environment]::GetEnvironmentVariable($Name,'Process')
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            $Hit += [pscustomobject]@{ Name=$Name; Value=$Value.Trim() }
        }
    }
    if ($Hit.Count -gt 1) {
        $Unique = @($Hit | ForEach-Object {$_.Value} | Sort-Object -Unique)
        if ($Unique.Count -gt 1) {
            throw "Tegenstrijdige NinjaOne-variabelen voor $($Names[0]); verwijder oude variabelen."
        }
    }
    if ($Hit.Count -gt 0) { return [string]$Hit[0].Value }
    return $Fallback
}
function Get-Checkbox {
    param([string]$Value)
    switch ($Value.Trim().ToLowerInvariant()) {
        { $_ -in @('true','1','ja','yes','on') } { return $true }
        { $_ -in @('false','0','nee','no','off','') } { return $false }
        default { throw "Ongeldige checkboxwaarde '$Value'." }
    }
}
function Test-Https {
    param([string]$Url)
    $Uri = $null
    if (-not [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$Uri) -or $Uri.Scheme -ne 'https' -or $Uri.UserInfo) {
        throw "Alleen HTTPS zonder in de URL opgenomen inloggegevens is toegestaan: '$Url'."
    }
    return $Uri
}
function Get-PrinterSafe { param([string]$Name) Get-Printer -Name $Name -ErrorAction SilentlyContinue }
function Get-ConfigRetry {
    param([string]$Name)
    for ($Attempt=1;$Attempt -le 5;$Attempt++) {
        try { return Get-PrintConfiguration -PrinterName $Name -ErrorAction Stop }
        catch { if ($Attempt -eq 5) { throw }; Start-Sleep -Seconds 2 }
    }
}

# Dezelfde offline Windows-queuefuncties worden voor pilot en productie gebruikt.
function Ensure-TcpPrinterPort {
    param([string]$Name,[string]$IpAddress)
    $ExistingPort = Get-PrinterPort -Name $Name -ErrorAction SilentlyContinue
    if (-not $ExistingPort) {
        Add-PrinterPort -Name $Name -PrinterHostAddress $IpAddress -PortNumber 9100 -ErrorAction Stop
        Write-Log "Windows Standard TCP/IP-poort '$Name' aangemaakt, zonder netwerkverzoek."
        $ExistingPort = Get-PrinterPort -Name $Name -ErrorAction Stop
    }
    if ([string]$ExistingPort.PrinterHostAddress -ne $IpAddress) {
        throw "Poort '$Name' verwijst naar '$($ExistingPort.PrinterHostAddress)', verwacht '$IpAddress'."
    }
    if ($null -ne $ExistingPort.PortNumber -and [string]$ExistingPort.PortNumber -and [int]$ExistingPort.PortNumber -ne 9100) {
        throw "Poort '$Name' gebruikt niet TCP/9100."
    }
    return $ExistingPort
}
function Ensure-ManagedPrinterQueue {
    param(
        [string]$Name,[string]$Driver,[string]$PortName,
        [string]$Comment,[string]$AllowedMarker
    )
    $Current = Get-PrinterSafe -Name $Name
    if ($Current) {
        if (-not ([string]$Current.Comment).StartsWith($AllowedMarker,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Queue '$Name' bestaat al en is niet door deze automation gemarkeerd. Geen wijziging uitgevoerd."
        }
        if ($Current.DriverName -ne $Driver) {
            Set-Printer -Name $Name -DriverName $Driver -ErrorAction Stop
            Write-Log "Driver bijgewerkt voor '$Name'."
        }
        if ($Current.PortName -ne $PortName) {
            Set-Printer -Name $Name -PortName $PortName -ErrorAction Stop
            Write-Log "TCP/IP-poort bijgewerkt voor '$Name'."
        }
        if ([string]$Current.Comment -ne $Comment) {
            Set-Printer -Name $Name -Comment $Comment -ErrorAction Stop
        }
    }
    else {
        Add-Printer -Name $Name -DriverName $Driver -PortName $PortName -Comment $Comment -ErrorAction Stop
        Write-Log "Queue '$Name' toegevoegd zonder printerdetectie."
    }
    $Actual = Get-PrinterSafe -Name $Name
    if (-not $Actual -or $Actual.DriverName -ne $Driver -or $Actual.PortName -ne $PortName -or
        [string]$Actual.Comment -ne $Comment) {
        throw "Verificatie mislukt voor printerqueue '$Name'."
    }
    return $Actual
}
function Invoke-OfflineQueueTest {
    param([switch]$Cleanup)
    # 192.0.2.0/24 is TEST-NET-1 (RFC 5737), geen klant- of printer-IP.
    $TestIp = '192.0.2.50'
    $TestPort = 'BIC_TCP_192.0.2.50_9100'
    $TestMarker = 'BewustICT-TCP-TEST|192.0.2.50'
    $TestMarkerPrefix = 'BewustICT-TCP-TEST|'
    $Queues = @(
        'BIC TEST - Blanco Kleur',
        'BIC TEST - Blanco Zwart Wit',
        'BIC TEST - CMR'
    )
    $Svc = Get-Service -Name Spooler -ErrorAction Stop
    if ($Svc.Status -ne 'Running') {
        throw "Windows Print Spooler draait niet (status=$($Svc.Status)); de automation wijzigt de serviceconfiguratie niet."
    }
    # Controleer eerst conflicten: raak GEEN bestaande, niet-beheerde queue aan.
    foreach ($Name in $Queues) {
        $Current = Get-PrinterSafe -Name $Name
        if ($Current -and [string]$Current.Comment -ne $TestMarker) {
            throw "TEST GESTOPT: '$Name' bestaat maar heeft niet de verwachte testmarker. Geen wijzigingen uitgevoerd."
        }
    }
    if ($Cleanup) {
        foreach ($Name in $Queues) {
            if (Get-PrinterSafe -Name $Name) {
                Remove-Printer -Name $Name -ErrorAction Stop
                if (Get-PrinterSafe -Name $Name) { throw "Testqueue '$Name' is niet verwijderd." }
                Write-Log "Testqueue '$Name' verwijderd."
            }
        }
        $Port = Get-PrinterPort -Name $TestPort -ErrorAction SilentlyContinue
        if ($Port) {
            $InUse = @(Get-Printer | Where-Object { $_.PortName -eq $TestPort })
            if ($InUse.Count -eq 0) {
                Remove-PrinterPort -Name $TestPort -ErrorAction Stop
                Write-Log "Ongebruikte testpoort '$TestPort' verwijderd."
            }
            else { Write-Log "Testpoort in gebruik door andere queue: behouden." 'WARN' }
        }
        Write-Log 'OFFLINE_TEST_CLEANUP_OK: de drie gemarkeerde testqueues zijn afwezig.'
        return
    }
    $DriverCandidates = @('Generic / Text Only','Microsoft PCL6 Class Driver','Microsoft PS Class Driver')
    $ChosenDriver = $null
    foreach ($Candidate in $DriverCandidates) {
        $InstalledDriver = Get-PrinterDriver -Name $Candidate -ErrorAction SilentlyContinue
        if ($InstalledDriver) { $ChosenDriver = [string]$InstalledDriver.Name; break }
    }
    if (-not $ChosenDriver) {
        try {
            Add-PrinterDriver -Name 'Generic / Text Only' -ErrorAction Stop
        }
        catch {
            Write-Log ("Windows kon de ingebouwde Generic / Text Only driver niet laden: " + $_.Exception.Message) 'WARN'
        }
        $InstalledDriver = Get-PrinterDriver -Name 'Generic / Text Only' -ErrorAction SilentlyContinue
        if ($InstalledDriver) { $ChosenDriver = [string]$InstalledDriver.Name }
    }
    if (-not $ChosenDriver) {
        $Available = @(Get-PrinterDriver | Select-Object -First 12 -ExpandProperty Name) -join ', '
        throw "Geen bruikbare ingebouwde testdriver aanwezig. Beschikbare drivers: $Available. Stop zonder een queue aan te maken."
    }
    Write-Log "OFFLINE TEST: Windows-driver '$ChosenDriver', test-IP=$TestIp, 3 queues. Geen Epson-driver, kleur- of cassettevalidatie."
    [void](Ensure-TcpPrinterPort -Name $TestPort -IpAddress $TestIp)
    foreach ($Name in $Queues) {
        [void](Ensure-ManagedPrinterQueue -Name $Name -Driver $ChosenDriver -PortName $TestPort -Comment $TestMarker -AllowedMarker $TestMarkerPrefix)
        Write-Log "OFFLINE_TEST_QUEUE_OK: '$Name' bestaat op '$TestPort'."
    }
    if (@(Get-Printer | Where-Object { $_.PortName -eq $TestPort -and $_.Comment -eq $TestMarker }).Count -lt 3) {
        throw 'Controle mislukt: minder dan drie gemarkeerde testprinters aangemaakt.'
    }
    Write-Log 'OFFLINE_TEST_OK: 3/3 testqueues aanwezig ZONDER bereikbare Epson. Dit test geen werkelijke kleur, duplex, papierlade of afdrukken.'
}

function Get-SafeChildPath {
    param([string]$Base,[string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative)) {
        throw 'Driverpad ontbreekt of is absoluut.'
    }
    $FullBase = [IO.Path]::GetFullPath($Base).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $FullPath = [IO.Path]::GetFullPath((Join-Path $Base $Relative))
    if (-not $FullPath.StartsWith($FullBase,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Onveilig relatief driverpad '$Relative'."
    }
    return $FullPath
}

# Epson v2.122.00: fabrikant direct, zonder herpublicatie en zonder fysieke printer.
# Pilot: compatibiliteit met concreet Epson-model moet voor productie worden getoetst.
function Install-EpsonVendorUPD {
    $Name = 'EPSON Universal Print Driver'
    $Existing = Get-PrinterDriver -Name $Name -ErrorAction SilentlyContinue
    if ($Existing) {
        Write-Log "Epson UPD is al in Windows aanwezig: '$Name'. Bestaande driverversie wordt niet vervangen in pilot."
        return $Name
    }
    $Url = 'https://ftp.epson.com/drivers/EUPD_x64_212200.exe'
    $Hash = '3CC1C313ADFAB74F957E2AF63FF2FA87279169E3A043365EB0AF6024D420663B'
    $InfHash = 'C4AE14C42E42147288B143F36E1EE10DF003656C6363AB9A17C0D6F6A0592F2D'
    $PackageDirectory = Join-Path $PkgDir 'Epson-UPD-2.122.00'
    $Exe = Join-Path $PackageDirectory 'EUPD_x64_212200.exe'
    $Extract = Join-Path $PackageDirectory 'Extracted'
    New-Item -Path $PackageDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
        [void](Test-Https -Url $Url)
        Write-Log 'Download Epson Universal Print Driver 2.122.00 vanaf officiële Epson-server.'
        Invoke-WebRequest -Uri $Url -OutFile $Exe -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
    }
    $ActualHash = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($ActualHash -ne $Hash) { throw "Epson UPD SHA256 mismatch: ontvangen $ActualHash." }
    $Signature = Get-AuthenticodeSignature -LiteralPath $Exe -ErrorAction Stop
    if ($Signature.Status -ne 'Valid' -or [string]$Signature.SignerCertificate.Subject -notmatch 'SEIKO EPSON CORPORATION') {
        throw 'Epson UPD heeft geen geldige originele Authenticode-handtekening.'
    }
    Write-Log 'Epson UPD: SHA256 en fabrikant-signatuur gevalideerd; archief wordt uitgepakt.'
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $Archive = [IO.Compression.ZipFile]::OpenRead($Exe)
    try {
        [long]$Bytes = 0
        foreach ($Entry in $Archive.Entries) {
            if ($Entry.FullName) {
                [void](Get-SafeChildPath -Base $Extract -Relative $Entry.FullName)
            }
            $Bytes += [long]$Entry.Length
            if ($Bytes -gt 1073741824) { throw 'Epson SFX bevat te veel uitgepakte data (>1 GiB).' }
        }
    } finally { $Archive.Dispose() }
    if (Test-Path -LiteralPath $Extract) {
        Remove-Item -LiteralPath $Extract -Recurse -Force -ErrorAction Stop
    }
    [IO.Compression.ZipFile]::ExtractToDirectory($Exe,$Extract)
    $InfPath = Join-Path $Extract 'Universal_Print_Driver_x64_212200\E_JFB0DE.INF'
    $CatPath = Join-Path $Extract 'Universal_Print_Driver_x64_212200\e_jfb0de.cat'
    if (-not (Test-Path -LiteralPath $InfPath -PathType Leaf) -or -not (Test-Path -LiteralPath $CatPath -PathType Leaf)) {
        throw 'Epson driver INF/CAT ontbreken in het gevalideerde pakket.'
    }
    $InfHashActual = (Get-FileHash -LiteralPath $InfPath -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($InfHashActual -ne $InfHash) { throw "Epson INF hash mismatch: ontvangen $InfHashActual." }
    $CatSignature = Get-AuthenticodeSignature -LiteralPath $CatPath -ErrorAction Stop
    if ($CatSignature.Status -ne 'Valid' -or [string]$CatSignature.SignerCertificate.Subject -notmatch 'Microsoft Windows Hardware Compatibility Publisher') {
        throw 'Epson CAT heeft geen geldige Windows WHCP-handtekening.'
    }
    $PnpUtil = Join-Path $env:WINDIR 'System32\pnputil.exe'
    $PnpResult = & $PnpUtil '/add-driver' $InfPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "PnPUtil /add-driver mislukt: $($PnpResult -join ' ')" }
    Add-PrinterDriver -Name $Name -ErrorAction Stop
    $Installed = Get-PrinterDriver -Name $Name -ErrorAction Stop
    if (-not $Installed -or $Installed.Name -ne $Name) { throw 'Epson UPD niet in Windows geregistreerd.' }
    Write-Log "EPSON_UPD_DRIVER_OK: '$Name' geregistreerd, zonder printerdetectie."
    return $Name
}

function Install-ApprovedDriver {
    param([string]$Brand,[string]$CatalogUrl)
    if ([string]::IsNullOrWhiteSpace($CatalogUrl)) {
        throw "Voor merk '$Brand' is geen goedgekeurde drivercatalogus ingesteld. Vul 'driverCatalogusUrl' in of geef de exacte naam van een reeds geinstalleerde driver op via 'driverNaam'."
    }
    [void](Test-Https -Url $CatalogUrl)
    Write-Log "Haal drivercatalogus op via HTTPS: $CatalogUrl"
    $Catalog = Invoke-RestMethod -Uri $CatalogUrl -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    if ([int]$Catalog.schemaVersion -ne 1) { throw 'Niet-ondersteunde catalogusversie.' }
    $Entries = $Catalog.drivers
    if (-not $Entries) { throw 'Drivercatalogus bevat geen drivers.' }
    $Entry = $Entries.PSObject.Properties[$Brand]
    if (-not $Entry) { throw "Onbekend merk '$Brand' in drivercatalogus." }
    $Cfg = $Entry.Value
    if ($Cfg.status -ne 'approved') { throw "Driver voor merk '$Brand' heeft status '$($Cfg.status)' (niet goedgekeurd)." }
    $Name = [string]$Cfg.driverName
    $Url = [string]$Cfg.downloadUrl
    $Hash = [string]$Cfg.sha256
    $PublisherSubstring = [string]$Cfg.signerSubjectContains
    $InfRelative = [string]$Cfg.infRelativePath
    $CatRelative = [string]$Cfg.catRelativePath
    if ([string]::IsNullOrWhiteSpace($Name) -or $Hash -notmatch '^[a-fA-F0-9]{64}$' -or
        -not $InfRelative -or -not $CatRelative -or -not $PublisherSubstring -or $Url -notmatch '\.zip($|\?)') {
        throw "Onvolledig goedgekeurd driverrecord voor '$Brand'."
    }
    [void](Test-Https -Url $Url)
    if (Get-PrinterDriver -Name $Name -ErrorAction SilentlyContinue) {
        Write-Log "Driver '$Name' is al lokaal geinstalleerd."
        return $Name
    }
    $Dir = Join-Path $PkgDir $Hash.ToLowerInvariant()
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $ZipFile = Join-Path $Dir 'driver.zip'
    if (-not (Test-Path -LiteralPath $ZipFile)) {
        Write-Log "Download goedgekeurde driver voor '$Brand'."
        Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $ZipFile -TimeoutSec 300 -ErrorAction Stop
    }
    $ActualHash = (Get-FileHash -LiteralPath $ZipFile -Algorithm SHA256).Hash
    if ($ActualHash -ne $Hash) {
        Remove-Item -LiteralPath $ZipFile -Force -ErrorAction SilentlyContinue
        throw "SHA256-verificatie mislukt voor '$Brand'!"
    }
    $Extracted = Join-Path $Dir 'Expanded'
    # Verify archive names and uncompressed size before extracting (path traversal / zip bombs).
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $Archive = [IO.Compression.ZipFile]::OpenRead($ZipFile)
    try {
        [long]$TotalBytes = 0
        foreach ($FileEntry in $Archive.Entries) {
            if (-not [string]::IsNullOrWhiteSpace($FileEntry.FullName)) {
                [void](Get-SafeChildPath -Base $Extracted -Relative $FileEntry.FullName)
            }
            $TotalBytes += [long]$FileEntry.Length
            if ($TotalBytes -gt 2147483648) { throw 'Driver-ZIP bevat meer dan 2 GiB uitgepakte data.' }
        }
    }
    finally { $Archive.Dispose() }
    if (-not (Test-Path -LiteralPath $Extracted)) {
        Expand-Archive -LiteralPath $ZipFile -DestinationPath $Extracted -ErrorAction Stop
    }
    $InfPath = Get-SafeChildPath -Base $Extracted -Relative $InfRelative
    $CatPath = Get-SafeChildPath -Base $Extracted -Relative $CatRelative
    if (-not (Test-Path -LiteralPath $InfPath) -or -not (Test-Path -LiteralPath $CatPath)) {
        throw "Het uitgepakte driverpakket mist INF/CAT voor '$Brand'."
    }
    $Signature = Get-AuthenticodeSignature -LiteralPath $CatPath -ErrorAction Stop
    if ($Signature.Status -ne 'Valid') { throw "Ongeldige digitale handtekening op '$CatPath': $($Signature.Status)." }
    if ([string]$Signature.SignerCertificate.Subject -notlike ('*' + $PublisherSubstring + '*')) {
        throw "Onverwachte driveruitgever voor '$Brand': $($Signature.SignerCertificate.Subject)."
    }
    Write-Log "CAT-signatuur geldig, uitgever: $($Signature.SignerCertificate.Subject)"
    $PnpUtil = Join-Path $env:WINDIR 'System32\pnputil.exe'
    $PnpOutput = & $PnpUtil '/add-driver' $InfPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "PnPUtil mislukt (exit=$LASTEXITCODE): $($PnpOutput -join ' ')" }
    Add-PrinterDriver -Name $Name -ErrorAction Stop
    if (-not (Get-PrinterDriver -Name $Name -ErrorAction SilentlyContinue)) {
        throw "De verwachte Windows-driver '$Name' is niet aanwezig na installatie. Controleer de INF-ModelName."
    }
    Write-Log "Goedgekeurde driver '$Name' toegevoegd aan Windows."
    return $Name
}
# Ladekeuze via een generieke, op de Windows-spooler gevalideerde DEVMODE helper.
# GitHub helper is vastgepind op de commit die in CI succesvol Cassette 1/2 schreef.
function Set-CassetteStrict {
    param([string]$Name,[int]$Number)
    if ($Number -lt 1 -or $Number -gt 4) { throw "Ongeldig cassettenummer '$Number'." }
    $TrayName = 'Cassette {0}' -f $Number
    $Pin = '787eb04801725623691d65d9963b5bb80bf2f55b'
    $Url = 'https://raw.githubusercontent.com/BewustRon/BewustICT-Printer-Deployment/{0}/scripts/Set-BewustICTPrinterTray.ps1' -f $Pin
    [void](Test-Https -Url $Url)
    $Tools = Join-Path $Root 'Tools'
    New-Item -Path $Tools -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $ToolFile = Join-Path $Tools ('Set-BewustICTPrinterTray-{0}.ps1' -f $Pin.Substring(0,12))
    if (-not (Test-Path -LiteralPath $ToolFile -PathType Leaf)) {
        Write-Log "Ophalen van op commit $Pin vastgepinde generieke papierlade-helper."
        Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $ToolFile -TimeoutSec 90 -ErrorAction Stop
    }
    $PowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($Action in @('Instellen','Controleren')) {
        $Output = & $PowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ToolFile -PrinterNaam $Name -Papierlade $TrayName -Actie $Action 2>&1
        $Code = $LASTEXITCODE
        foreach ($Line in @($Output)) {
            Write-Log ("TRAY/{0}: {1}" -f $Action,([string]$Line))
        }
        if ($Code -ne 0) { throw "Papierlade $TrayName kon niet door de spooler worden $Action voor '$Name' (exit $Code)." }
    }
    Write-Log "CASSETTE_CONFIRMED: '$Name' = '$TrayName' als globale Windows-printerstandaard; fysiek afdrukken blijft te testen."
}

# Per-user standaardprinter: beheerde taak, geen HKCU-aanpassing vanuit SYSTEM.
$TaskName = 'BewustICT - Printer Default (TCP)'
$TaskDir = Join-Path $Root 'UserDefaultTCP'
$TaskConfig = Join-Path $TaskDir 'PrinterName.txt'
$TaskCode = Join-Path $TaskDir 'Apply-Default.ps1'
function Set-TaskDirectoryPermissions {
    New-Item -Path $TaskDir -ItemType Directory -Force | Out-Null
    $Acl = Get-Acl -LiteralPath $TaskDir
    $Acl.SetAccessRuleProtection($true,$false)
    foreach ($Rule in @($Acl.Access)) { $Acl.RemoveAccessRuleSpecific($Rule) }
    $Inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $Propagate = [Security.AccessControl.PropagationFlags]::None
    $Allow = [Security.AccessControl.AccessControlType]::Allow
    foreach ($Pair in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-32-545','ReadAndExecute'))) {
        $Sid = [Security.Principal.SecurityIdentifier]::new($Pair[0])
        $Access = [Security.AccessControl.FileSystemAccessRule]::new($Sid,[Security.AccessControl.FileSystemRights]$Pair[1],$Inherit,$Propagate,$Allow)
        $Acl.AddAccessRule($Access)
    }
    Set-Acl -LiteralPath $TaskDir -AclObject $Acl -ErrorAction Stop
}
function Enable-DefaultPrinterAtLogon {
    param([string]$Name)
    Set-TaskDirectoryPermissions
    $Helper = @'
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Config = Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\UserDefaultTCP\PrinterName.txt'
$LogFolder = Join-Path $env:LOCALAPPDATA 'BewustICT\PrinterDeployment'
New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
$LogFile = Join-Path $LogFolder 'DefaultPrinterTCP.log'
try {
    $Name = (Get-Content -LiteralPath $Config -Raw -Encoding UTF8).Trim()
    if (-not (Get-Printer -Name $Name -ErrorAction SilentlyContinue)) { throw "Printer '$Name' ontbreekt." }
    New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name LegacyDefaultPrinterMode -Value 1 -PropertyType DWord -Force | Out-Null
    $Wsh = New-Object -ComObject WScript.Network
    $Wsh.SetDefaultPrinter($Name)
    Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value "SUCCESS: $Name"
} catch {
    Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value "ERROR: $($_.Exception.Message)"
    exit 1
}
'@
    [IO.File]::WriteAllText($TaskCode,$Helper,[Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($TaskConfig,$Name,[Text.Encoding]::UTF8)
    Import-Module ScheduledTasks -ErrorAction Stop
    $Exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $Action = New-ScheduledTaskAction -Execute $Exe -Argument ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $TaskCode)
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Force -ErrorAction Stop | Out-Null
    Write-Log "Standaardprinter '$Name' wordt bij volgende gebruikersaanmelding ingesteld."
}
function Disable-DefaultPrinterIfMatching {
    param([string]$Name)
    if (-not (Test-Path -LiteralPath $TaskConfig)) { return }
    $Current = (Get-Content -LiteralPath $TaskConfig -Raw -Encoding UTF8).Trim()
    if ($Current -ne $Name) { return }
    Import-Module ScheduledTasks -ErrorAction Stop
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    }
    Remove-Item -LiteralPath $TaskConfig -Force -ErrorAction Stop
}

try {
    $Actie = Read-NinjaValue @('actie') $Actie
    $PrinterNaam = Read-NinjaValue @('printerNaam') $PrinterNaam
    $PrinterIpAdres = Read-NinjaValue @('printerIpAdres','printerIPAdres') $PrinterIpAdres
    $PrinterMerk = Read-NinjaValue @('printerMerk') $PrinterMerk
    $DriverNaam = Read-NinjaValue @('driverNaam') $DriverNaam
    $DriverCatalogusUrl = Read-NinjaValue @('driverCatalogusUrl') $DriverCatalogusUrl
    $KleurAfdrukken = Read-NinjaValue @('kleurAfdrukken') $KleurAfdrukken
    $DubbelzijdigAfdrukken = Read-NinjaValue @('dubbelzijdigAfdrukken') $DubbelzijdigAfdrukken
    $Papierformaat = Read-NinjaValue @('papierformaat') $Papierformaat
    $Papierlade = Read-NinjaValue @('papierlade') $Papierlade
    $Checkbox = Read-NinjaValue @('instellenAlsStandaardprinter') $InstellenAlsStandaardprinter
    $UseDefault = Get-Checkbox $Checkbox
    $Mode = switch ($Actie) {
        {$_ -in @('Installeren','Install')} {'Install'}
        {$_ -in @('Controleren','Inspect')} {'Inspect'}
        {$_ -in @('Verwijderen','Remove')} {'Remove'}
        {$_ -in @('Offline testen','OfflineTest')} {'OfflineTest'}
        {$_ -in @('Test opruimen','OfflineCleanup')} {'OfflineCleanup'}
        default { throw "Ongeldige actie '$Actie'." }
    }
    # Offline test negeert andere NinjaOne-velden en raakt geen productiequeue aan.
    if ($Mode -in @('OfflineTest','OfflineCleanup')) {
        if (-not [Environment]::Is64BitProcess) { throw 'Windows PowerShell 64-bit is verplicht.' }
        $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $Admin = New-Object Security.Principal.WindowsPrincipal($Identity)
        if (-not $Admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Run as SYSTEM of Administrator is vereist.'
        }
        Import-Module PrintManagement -ErrorAction Stop
        Write-Log "Bewust ICT printerdeployment $Version - $Mode"
        Invoke-OfflineQueueTest -Cleanup:($Mode -eq 'OfflineCleanup')
        exit 0
    }
    if ([string]::IsNullOrWhiteSpace($PrinterNaam) -or $PrinterNaam.Length -gt 180 -or $PrinterNaam -match '[\r\n\*\?\[\]]') {
        throw 'Vul een geldige printernaam in (maximaal 180 tekens).'
    }
    if (-not [Environment]::Is64BitProcess) { throw 'Windows PowerShell 64-bit is verplicht.' }
    $Who = [Security.Principal.WindowsIdentity]::GetCurrent()
    $P = New-Object Security.Principal.WindowsPrincipal($Who)
    if (-not $P.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as SYSTEM of Administrator is vereist.' }
    Import-Module PrintManagement -ErrorAction Stop
    Write-Log "Bewust ICT TCP printerdeployment $Version. Actie=$Mode, naam='$PrinterNaam', merk='$PrinterMerk', IP='$PrinterIpAdres'."

    $Existing = Get-PrinterSafe $PrinterNaam
    if ($Mode -eq 'Inspect') {
        if (-not $Existing) { throw "Printer '$PrinterNaam' bestaat niet." }
        $Cfg = Get-ConfigRetry $PrinterNaam
        Write-Log "Queue: Driver='$($Existing.DriverName)' Port='$($Existing.PortName)' Comment='$($Existing.Comment)' Color=$($Cfg.Color) Duplex=$($Cfg.DuplexingMode) Paper=$($Cfg.PaperSize)."
        exit 0
    }
    if ($Mode -eq 'Remove') {
        if ($Existing) {
            if (-not ([string]$Existing.Comment).StartsWith($MarkerPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Printer is niet door deze TCP-automation beheerd; verwijderen geweigerd.' }
            Remove-Printer -Name $PrinterNaam -ErrorAction Stop
            Write-Log 'Beheerde printerqueue verwijderd (poort/driver behouden).'
        }
        Disable-DefaultPrinterIfMatching $PrinterNaam
        exit 0
    }
    $Parsed = $null
    if (-not [Net.IPAddress]::TryParse($PrinterIpAdres,[ref]$Parsed) -or $Parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Ongeldig IPv4-adres '$PrinterIpAdres'."
    }
    if ($PrinterMerk -notin @('HP','Epson','Canon','Kyocera','Ricoh','Brother')) { throw "Onbekend merk '$PrinterMerk'." }
    if ($Papierformaat -notin @('A4','A3','A5')) { throw "Ongeldig papierformaat '$Papierformaat'." }
    $Color = switch ($KleurAfdrukken) { 'Kleur' {$true}; 'Zwart-wit' {$false}; default { throw "Ongeldige kleurinstelling '$KleurAfdrukken'." } }
    $Duplex = switch ($DubbelzijdigAfdrukken) {
        'Uit' {'OneSided'}
        'Lange zijde' {'TwoSidedLongEdge'}
        'Korte zijde' {'TwoSidedShortEdge'}
        default { throw "Ongeldige duplexinstelling '$DubbelzijdigAfdrukken'." }
    }
    $CassetteNumber = switch ($Papierlade) {
        'Automatisch' {0}
        'Cassette 1' {1}
        'Cassette 2' {2}
        'Cassette 3' {3}
        'Cassette 4' {4}
        default { throw "Ongeldige papierlade '$Papierlade'." }
    }
    $ResolvedDriverName = $DriverNaam.Trim()
    if ($ResolvedDriverName) {
        if (-not (Get-PrinterDriver -Name $ResolvedDriverName -ErrorAction SilentlyContinue)) {
            throw "Opgegeven driver '$ResolvedDriverName' is niet aanwezig. Voor automatische download: keur de merkdriver goed in de centrale catalogus en laat driverNaam leeg."
        }
        Write-Log "Gebruik reeds geinstalleerde driver '$ResolvedDriverName'."
    } elseif ($PrinterMerk -eq 'Epson') {
        $ResolvedDriverName = Install-EpsonVendorUPD
    } else {
        $ResolvedDriverName = Install-ApprovedDriver -Brand $PrinterMerk -CatalogUrl $DriverCatalogusUrl
    }
    $PortName = 'BIC_TCP_{0}_9100' -f $PrinterIpAdres
    [void](Ensure-TcpPrinterPort -Name $PortName -IpAddress $PrinterIpAdres)
    $ExpectedMarker = "$MarkerPrefix$PrinterMerk"
    [void](Ensure-ManagedPrinterQueue -Name $PrinterNaam -Driver $ResolvedDriverName -PortName $PortName -Comment $ExpectedMarker -AllowedMarker $MarkerPrefix)
    $Before = Get-ConfigRetry $PrinterNaam
    if ($Before.Color -ne $Color -or [string]$Before.DuplexingMode -ne $Duplex -or [string]$Before.PaperSize -ne $Papierformaat) {
        Set-PrintConfiguration -PrinterName $PrinterNaam -Color ([bool]$Color) -DuplexingMode $Duplex -PaperSize $Papierformaat -ErrorAction Stop
    }
    if ($CassetteNumber -gt 0) { Set-CassetteStrict -Name $PrinterNaam -Number $CassetteNumber }
    $After = Get-ConfigRetry $PrinterNaam
    if ($After.Color -ne $Color -or [string]$After.DuplexingMode -ne $Duplex -or [string]$After.PaperSize -ne $Papierformaat) {
        throw 'Een of meer standaardinstellingen werden niet door Windows behouden.'
    }
    if ($UseDefault) { Enable-DefaultPrinterAtLogon $PrinterNaam }
    Write-Log "SUCCESS: printer '$PrinterNaam' is voorbereid voor $PrinterIpAdres. Fysieke afdrukcontrole na aansluiten printer blijft vereist."
    exit 0
} catch {
    Write-Log ('FAILED: '+$_.Exception.Message) 'ERROR'
    Write-Log "Logbestand: $LogFile" 'ERROR'
    exit 1
}