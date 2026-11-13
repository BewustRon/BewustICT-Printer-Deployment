#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - Universele TCP/IP printerdeployment via NinjaOne.
.DESCRIPTION
  Maakt een Windows-printerqueue aan met een Standard TCP/IP-poort, ook als de
  printer nog niet bereikbaar is. Gebruikt een exact vooraf geinstalleerde
  driver, een goedgekeurd INF-driverpakket uit een HTTPS-drivercatalogus of
  voor Epson de officiele Epson Universal Print Driver v2.122.00;
  voor Brother de officiele Mono Universal Printer (PCL) via een vastgepinde
  en gecontroleerde Brother installer-helper.

  OFFLINE TEST: Actie='Offline testen' maakt drie veilige BIC TEST-queues aan
  op het gereserveerde IP 192.0.2.50 met een Windows-testdriver.
  Actie='Test opruimen' verwijdert alleen die gemarkeerde testqueues.

  PILOT: Epson is offline geverifieerd in CI en op engineer-pc.
  Brother is offline geverifieerd op een Windows CI-runner. Centrale
  integratie en fysieke Brother-print moeten nog worden geverifieerd.
  Niet breed inzetten voordat modelcompatibiliteit en printtest zijn gedaan.

  Veiligheidsgrenzen:
  - Geen IPP-discovery, geen ping vereist voor installatie.
  - Download alleen HTTPS + een vooraf vastgelegde SHA256 + geldige CAT-signatuur.
  - Epson SFX wordt als ZIP/archief uitgepakt, niet uitgevoerd.
  - Brother Enhanced Generic PCL SFX is unpacked with SHA256-pinned
    portable 7-Zip. Andere merken blijven fail-closed.
  - Verwijderen en wijzigen alleen voor door dit script gemarkeerde queues.
  - Een afwijkende papierlade wordt nooit aangenomen zonder bevestiging.
  - Uses RAW TCP/9100; printer must support the selected PCL / print path.
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
$Version = '1.3.0-PILOT'
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
# The HP UPD's public PrintTicket "Color=True" is only a job default. The
# actual HP device type is a *per-queue* installable option, exposed through
# the supported Windows Get/Set-PrinterProperty PrintManagement cmdlets.
# On an offline HP UPD PCL6 install this defaults to AUTODEVICE, which presents
# as "Kleur: Nee" in Print Management even if the print default is Color=True.
# Do not modify raw printer registry data, signed CFG files, or shared driver
# configuration. Update *only* the specified Bewust ICT managed HP queue.
function Ensure-HpUPDColorDevice {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$DriverName,
        [Parameter(Mandatory=$true)][bool]$RequireColor
    )
    if (-not $RequireColor) { return }
    if ($DriverName -ne 'HP Universal Printing PCL 6') {
        throw "HP kleurcapaciteit kan niet veilig worden afgedwongen met onbekende driver '$DriverName'."
    }
    $Queue = Get-PrinterSafe -Name $Name
    if (-not $Queue -or -not ([string]$Queue.Comment).StartsWith('BewustICT-TCP|HP',[StringComparison]::OrdinalIgnoreCase)) {
        throw "HP kleurconfiguratie geweigerd voor niet-beheerde printer '$Name'."
    }
    $PropertyName = 'Config:DynamicRender'
    $BeforeProperty = Get-PrinterProperty -PrinterName $Name -PropertyName $PropertyName -ErrorAction Stop
    $BeforeValue = [string]$BeforeProperty.Value
    if ($BeforeValue -notin @('AUTODEVICE','COLORDEVICE','MONODEVICE')) {
        throw "HP UPD geeft onbekend apparaat-type '$BeforeValue' terug. Geen wijziging uitgevoerd."
    }
    if ($BeforeValue -ne 'COLORDEVICE') {
        Write-Log "HP apparaat-type aanpassen voor '$Name': $BeforeValue -> COLORDEVICE, zonder printerdetectie."
        Set-PrinterProperty -PrinterName $Name -PropertyName $PropertyName -Value 'COLORDEVICE' -ErrorAction Stop
    }
    # Use the spooler's native DC_COLORDEVICE capability, not only
    # System.Drawing.PrinterSettings.SupportsColor (which may be true even
    # when HP's Device Type still says Auto and Print Management says No).
    if (-not ('BewustICT.HpColorDeviceNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace BewustICT {
    public static class HpColorDeviceNative {
        [DllImport("winspool.drv", EntryPoint="DeviceCapabilitiesW", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern int DeviceCapabilities(string name, string port, short capability,
            IntPtr output, IntPtr devmode);
    }
}
'@ -ErrorAction Stop
    }
    $AfterValue = [string](Get-PrinterProperty -PrinterName $Name -PropertyName $PropertyName -ErrorAction Stop).Value
    $ActualQueue = Get-PrinterSafe -Name $Name
    $ColorCapability = [BewustICT.HpColorDeviceNative]::DeviceCapabilities(
        $ActualQueue.Name, $ActualQueue.PortName, [Int16]32, [IntPtr]::Zero, [IntPtr]::Zero)
    if ($AfterValue -ne 'COLORDEVICE' -or $ColorCapability -ne 1) {
        throw "HP_KLEURCAPACITEIT_NIET_INGESCHAKELD: '$Name'; apparaat-type=$AfterValue; WinSpool DC_COLORDEVICE=$ColorCapability."
    }
    Write-Log "HP_COLOR_DEVICE_VERIFIED: '$Name'; Apparaattype=$AfterValue; DC_COLORDEVICE=$ColorCapability. Alleen deze printerqueue aangepast."
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


# Brother Enhanced Generic PCL5e: no discovery wizard or per-user target selection.
# Signed official vendor download and exact, immutable helper script hash.
function Install-BrotherGenericPCL {
    $Name='Brother PCL5e Driver'
    if(Get-PrinterDriver -Name $Name -ErrorAction SilentlyContinue) {
        Write-Log "Brother Enhanced Generic PCL5e '$Name' is already registered."
        return $Name
    }
    $Pin='a2e5f73c3c3e55d019840b654793e6c5e24cd6b2'
    $Hash='5E2CFF3BDE50D0F5FA6B965FB1F35D2A2AEEDE69F8D494E4694804B51D058C58'
    $Url="https://raw.githubusercontent.com/BewustRon/BewustICT-Printer-Deployment/$Pin/scripts/Install-BrotherGenericPCL.ps1"
    [void](Test-Https -Url $Url)
    $Dir=Join-Path $PkgDir 'Brother-EnhancedGeneric-PCL5e-1.09'
    New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop | Out-Null
    $Helper=Join-Path $Dir 'Install-BrotherGenericPCL-Pinned.ps1'
    if(-not (Test-Path -LiteralPath $Helper -PathType Leaf)) {
        Write-Log "Download Brother generic driver helper (pinned $Pin)."
        Invoke-WebRequest -Uri $Url -OutFile $Helper -UseBasicParsing -TimeoutSec 90 -ErrorAction Stop
    }
    $ActualHash=(Get-FileHash -LiteralPath $Helper -Algorithm SHA256 -ErrorAction Stop).Hash
    if($ActualHash -ne $Hash) {
        Remove-Item -LiteralPath $Helper -Force -ErrorAction SilentlyContinue
        throw "Brother generic helper integrity failed: $ActualHash"
    }
    Write-Log 'Install Brother Enhanced Generic PCL5e; does not select network devices interactively.'
    $PowerShell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $Output=& $PowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Helper 2>&1
    $Exit=$LASTEXITCODE
    foreach($Line in @($Output)) { Write-Log ('BROTHER_GENERIC: '+[string]$Line) }
    if($Exit -ne 0){throw "Brother generic PCL5e installer failed, exit=$Exit"}
    if(-not (@($Output|ForEach-Object {[string]$_}) -match '^BROTHER_GENERIC_DRIVER_OK$')) {
        throw 'Brother generic PCL5e helper did not report verified completion.'
    }
    $Installed=Get-PrinterDriver -Name $Name -ErrorAction Stop
    if($Installed.Name -ne $Name) {throw "Brother generic PCL5e was not registered in Windows."}
    Write-Log "BROTHER_GENERIC_INSTALLED: $Name"
    return $Name
}

function Install-ApprovedDriver {
    param([string]$Brand,[string]$CatalogUrl)
    if ([string]::IsNullOrWhiteSpace($CatalogUrl)) {
        throw "Voor merk '$Brand' is geen goedgekeurde drivercatalogus ingesteld."
    }
    [void](Test-Https -Url $CatalogUrl)
    Write-Log "Haal drivercatalogus op via HTTPS: $CatalogUrl"
    $Catalog = Invoke-RestMethod -Uri $CatalogUrl -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    if ([int]$Catalog.schemaVersion -ne 2) { throw 'Niet-ondersteunde catalogusversie.' }
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
    $PublisherThumbprint = [string]$Cfg.signerThumbprint
    $InfRelative = [string]$Cfg.infRelativePath
    $CatRelative = [string]$Cfg.catRelativePath
    if ([string]::IsNullOrWhiteSpace($Name) -or $Hash -notmatch '^[A-Fa-f0-9]{64}$' -or
        $PublisherThumbprint -notmatch '^[A-Fa-f0-9]{40}$' -or
        -not $InfRelative -or -not $CatRelative -or -not $PublisherSubstring -or
        $Url -notmatch '\.zip($|\?)') {
        throw "Onvolledig goedgekeurd driverrecord voor '$Brand' (inclusief gepinde uitgevercertificaat-fingerprint)."
    }
    [void](Test-Https -Url $Url)
    $ExistingDriver = Get-PrinterDriver -Name $Name -ErrorAction SilentlyContinue
    if ($ExistingDriver) {
        Write-Log "Driver '$Name' is al lokaal geinstalleerd; hergebruik zonder nieuwe cert trust."
        return $Name
    }
    $Dir = Join-Path $PkgDir $Hash.ToLowerInvariant()
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $ZipFile = Join-Path $Dir 'driver.zip'
    # WinPS 5.1 Invoke-WebRequest is extremely slow for Kyocera's 251 MB ZIP on
    # Windows runners. Native inbox curl.exe streams directly to disk and uses
    # HTTPS-only redirects. A per-run temp file prevents truncated cache reuse.
    if (Test-Path -LiteralPath $ZipFile -PathType Leaf) {
        $CachedHash = (Get-FileHash -LiteralPath $ZipFile -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($CachedHash -ne $Hash) {
            Write-Log "Drivercache SHA256 ongeldig voor '$Brand'; verwijder beschadigde cache."
            Remove-Item -LiteralPath $ZipFile -Force -ErrorAction Stop
        }
    }
    if (-not (Test-Path -LiteralPath $ZipFile -PathType Leaf)) {
        Write-Log "Download goedgekeurde driver voor '$Brand' vanaf officiele fabrikant."
        $DownloadTemp = Join-Path $Dir ('vendor-download-' + [guid]::NewGuid().ToString('N') + '.zip')
        $DownloadStart = Get-Date
        try {
            $CurlExe = Join-Path $env:WINDIR 'System32\curl.exe'
            if (Test-Path -LiteralPath $CurlExe -PathType Leaf) {
                Write-Log 'Gebruik Windows curl.exe (HTTPS-only, streaming naar disk).'
                $CurlOutput = & $CurlExe '--fail' '--silent' '--show-error' '--location' '--proto' '=https' '--proto-redir' '=https' '--connect-timeout' '20' '--max-time' '300' '--retry' '2' '--retry-delay' '2' '--output' $DownloadTemp $Url 2>&1
                $CurlExit = $LASTEXITCODE
                if ($CurlExit -ne 0) {
                    throw "Windows curl.exe download voor '$Brand' mislukt, exitcode=${CurlExit}: $($CurlOutput -join ' ')"
                }
            } else {
                Write-Log 'Windows curl.exe niet beschikbaar, fallback Invoke-WebRequest.'
                Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $DownloadTemp -TimeoutSec 300 -ErrorAction Stop
            }
            $ReceivedHash = (Get-FileHash -LiteralPath $DownloadTemp -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($ReceivedHash -ne $Hash) {
                throw "Fabrikantdriver download voor '$Brand' heeft onjuiste SHA256: $ReceivedHash."
            }
            Move-Item -LiteralPath $DownloadTemp -Destination $ZipFile -Force -ErrorAction Stop
            $Seconds=[int]((Get-Date)-$DownloadStart).TotalSeconds
            Write-Log "Download '$Brand' voltooid in $Seconds seconden, SHA256 geverifieerd."
        } finally {
            if (Test-Path -LiteralPath $DownloadTemp -PathType Leaf) {
                Remove-Item -LiteralPath $DownloadTemp -Force -ErrorAction SilentlyContinue
            }
        }
    }
    $ActualHash = (Get-FileHash -LiteralPath $ZipFile -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($ActualHash -ne $Hash) {
        Remove-Item -LiteralPath $ZipFile -Force -ErrorAction SilentlyContinue
        throw "SHA256-verificatie mislukt voor '$Brand'!"
    }
    # Keep the verified OEM ZIP and diagnostic logs in the existing package cache,
    # but extract under a SHORT, SYSTEM-managed path. Kyocera's ZIP includes nested
    # device metadata: the old SHA256 + GUID staging path exceeded Win32 MAX_PATH
    # (275 characters on PC-JOHNNYWEIJER) and .NET Framework ZipFile failed.
    # A 96-bit SHA256 prefix isolates package work folders; the full 256-bit hash
    # is still checked both on the ZIP and in the completed extraction marker.
    $WorkParent = Join-Path $env:ProgramData 'BICPD'
    $WorkRoot = Join-Path $WorkParent ($Hash.Substring(0,24).ToLowerInvariant())
    New-Item -ItemType Directory -Path $WorkRoot -Force -ErrorAction Stop | Out-Null
    $Extracted = Join-Path $WorkRoot 'Expanded'
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
    # .NET ZIP extraction is much faster than Expand-Archive for the ~251 MB
    # Kyocera OEM package. Stage transactionally so a failed prior extraction
    # cannot be mistaken for a valid cache hit on the next NinjaOne run.
    $Marker = Join-Path $Extracted '.bic-expanded-sha256'
    $ExtractionValid = (Test-Path -LiteralPath $Marker -PathType Leaf) -and
        ((Get-Content -LiteralPath $Marker -Raw -ErrorAction SilentlyContinue).Trim() -eq $Hash)
    if (-not $ExtractionValid) {
        $StageDir = Join-Path $WorkRoot ('S-' + [guid]::NewGuid().ToString('N'))
        Write-Log "Pak '$Brand' uit in verkort stagingpad ($($StageDir.Length) tekens) om Windows MAX_PATH te vermijden."
        try {
            [IO.Compression.ZipFile]::ExtractToDirectory($ZipFile, $StageDir)
            $StageInf = Get-SafeChildPath -Base $StageDir -Relative $InfRelative
            $StageCat = Get-SafeChildPath -Base $StageDir -Relative $CatRelative
            if (-not (Test-Path -LiteralPath $StageInf -PathType Leaf) -or
                -not (Test-Path -LiteralPath $StageCat -PathType Leaf)) {
                throw "Uitgepakt archief voor '$Brand' mist de geselecteerde INF/CAT."
            }
            [IO.File]::WriteAllText((Join-Path $StageDir '.bic-expanded-sha256'),$Hash,[Text.Encoding]::ASCII)
            if (Test-Path -LiteralPath $Extracted) {
                Remove-Item -LiteralPath $Extracted -Recurse -Force -ErrorAction Stop
            }
            Move-Item -LiteralPath $StageDir -Destination $Extracted -ErrorAction Stop
            Write-Log "Goedgekeurd ZIP-pakket '$Brand' uitgepakt met .NET ZipFile."
        } finally {
            if (Test-Path -LiteralPath $StageDir) {
                Remove-Item -LiteralPath $StageDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    $InfPath = Get-SafeChildPath -Base $Extracted -Relative $InfRelative
    $CatPath = Get-SafeChildPath -Base $Extracted -Relative $CatRelative
    if (-not (Test-Path -LiteralPath $InfPath -PathType Leaf) -or -not (Test-Path -LiteralPath $CatPath -PathType Leaf)) {
        throw "Het uitgepakte driverpakket mist INF/CAT voor '$Brand'."
    }
    $Signature = Get-AuthenticodeSignature -LiteralPath $CatPath -ErrorAction Stop
    if ($Signature.Status -ne 'Valid') {
        throw "Ongeldige digitale handtekening op '$CatPath': $($Signature.Status)."
    }
    $Signer = $Signature.SignerCertificate
    if (-not $Signer -or $Signer.Subject -notlike ('*' + $PublisherSubstring + '*') -or
        $Signer.Thumbprint -ne $PublisherThumbprint) {
        throw "Afwijkend fabrikantscertificaat voor '$Brand'. Verwachte thumbprint: $PublisherThumbprint."
    }
    if ($Signer.NotAfter -le (Get-Date)) {
        throw "Ondertekeningscertificaat van '$Brand' is verlopen ($($Signer.NotAfter)). Catalogue update vereist."
    }
    Write-Log "CAT ondertekening geldig: $($Signer.Subject); SHA1-certificaat-thumbprint=$($Signer.Thumbprint)"
    if ($Signer.NotAfter -lt (Get-Date).AddDays(45)) {
        Write-Log "WAARSCHUWING: uitgevercertificaat '$Brand' vervalt binnen 45 dagen: $($Signer.NotAfter)."
    }

    # Modern OEM printer drivers are Authenticode signed but no longer necessarily
    # Microsoft WHQL signed. Windows SetupAPI otherwise opens an interactive
    # unknown-publisher dialog. Trust ONLY the exact pinned leaf certificate.
    # NEVER modify the Root or CA stores and NEVER lower driver security policies.
    $NewPublisherTrust = $false
    $TrustedPublisherStore = New-Object Security.Cryptography.X509Certificates.X509Store('TrustedPublisher','LocalMachine')
    $TrustedPublisherStore.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    try {
        $Present = $TrustedPublisherStore.Certificates.Find(
            [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
            $PublisherThumbprint, $false)
        if ($Present.Count -eq 0) {
            $TrustedPublisherStore.Add($Signer)
            $NewPublisherTrust = $true
            Write-Log "Exact gecontroleerde OEM-signer '$Brand' toegevoegd aan LocalMachine\\TrustedPublisher. Niet aan Root."
        } else {
            Write-Log "OEM-signer '$Brand' is al aanwezig in LocalMachine\\TrustedPublisher."
        }
    } finally {
        $TrustedPublisherStore.Close()
    }
    try {
        $PnpUtil = Join-Path $env:WINDIR 'System32\pnputil.exe'
        $StdOut = Join-Path $Dir 'pnputil.stdout.log'
        $StdErr = Join-Path $Dir 'pnputil.stderr.log'
        $PnpProcess = Start-Process -FilePath $PnpUtil -ArgumentList ('/add-driver "' + $InfPath + '"') -PassThru -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr -WindowStyle Hidden -ErrorAction Stop
        if (-not $PnpProcess.WaitForExit(180000)) {
            try { Stop-Process -Id $PnpProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
            throw "PnPUtil-timeout voor '$Brand' na 180 seconden; Windows-driverstage mogelijk geblokkeerd."
        }
        $PnpProcess.Refresh()
        foreach ($Line in @(Get-Content -LiteralPath $StdOut -ErrorAction SilentlyContinue)) {
            Write-Log ('PNPUTIL: ' + [string]$Line)
        }
        foreach ($Line in @(Get-Content -LiteralPath $StdErr -ErrorAction SilentlyContinue)) {
            Write-Log ('PNPUTIL/ERROR: ' + [string]$Line)
        }
        # Some Windows PowerShell/Start-Process combinations do not surface
        # an ExitCode. The final driver registration is always verified.
        if ([string]$PnpProcess.ExitCode -match '^-?\d+$' -and [int]$PnpProcess.ExitCode -ne 0) {
            throw "PnPUtil mislukte voor '$Brand' met exitcode $($PnpProcess.ExitCode)."
        }
        Add-PrinterDriver -Name $Name -ErrorAction Stop
        $Registered = Get-PrinterDriver -Name $Name -ErrorAction Stop
        if (-not $Registered -or $Registered.Name -ne $Name) {
            throw "Windows-driver '$Name' is niet aanwezig na installatie."
        }
        Write-Log "Goedgekeurde universele fabrikantdriver '$Name' toegevoegd aan Windows."
    } catch {
        # Revert trust only when we added it and the actual driver was not installed.
        # Do not remove certificates already trusted before this deployment.
        if ($NewPublisherTrust -and -not (Get-PrinterDriver -Name $Name -ErrorAction SilentlyContinue)) {
            try {
                $Rollback = New-Object Security.Cryptography.X509Certificates.X509Store('TrustedPublisher','LocalMachine')
                $Rollback.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                try {
                    $Imported = $Rollback.Certificates.Find(
                        [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
                        $PublisherThumbprint, $false)
                    foreach($CertToRemove in @($Imported)) { $Rollback.Remove($CertToRemove) }
                } finally { $Rollback.Close() }
                Write-Log "TrustedPublisher-import voor '$Brand' teruggedraaid na mislukte driverinstallatie."
            } catch {
                Write-Log "WAARSCHUWING: rollback TrustedPublisher $Brand is mislukt: $($_.Exception.Message)"
            }
        }
        throw
    }
    return $Name
}
# Ladekeuze via een generieke, op de Windows-spooler gevalideerde DEVMODE helper.
# Pinned tray helper resolves physical-numbered tray aliases from the actual offline driver (HP Tray/Lade, Epson Cassette); never guesses IDs.
function Set-CassetteStrict {
    param([string]$Name,[int]$Number)
    if ($Number -lt 1 -or $Number -gt 4) { throw "Ongeldig cassettenummer '$Number'." }
    $TrayName = 'Cassette {0}' -f $Number
    $Pin = '911fd30174cce20bda1e7f515aaabd5ffd33eb06'
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
$LogTray = "Cassette $Number"
    Write-Log "TRAY_STRICT_CONFIRMED: '$Name' = '$TrayName' als globale Windows-printerstandaard; fysiek afdrukken blijft te testen."
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
    # De geteste Brother Universal PCL-driver is monochroom. Specifieke
    # Brother-papierladen zijn voor dit model nog niet gemapt.
    if ($PrinterMerk -eq 'Brother' -and [string]::IsNullOrWhiteSpace($DriverNaam)) {
        if ($KleurAfdrukken -ne 'Zwart-wit') { throw 'Brother Enhanced Generic PCL5e ondersteunt alleen zwart-wit.' }
        if ($Papierlade -ne 'Automatisch') { throw 'Brother PCL5e-lades zijn nog niet gevalideerd. Gebruik Automatisch.' }
    }
    $ResolvedDriverName = $DriverNaam.Trim()
    if ($ResolvedDriverName) {
        if (-not (Get-PrinterDriver -Name $ResolvedDriverName -ErrorAction SilentlyContinue)) {
            throw "Opgegeven driver '$ResolvedDriverName' is niet aanwezig. Voor automatische download: keur de merkdriver goed in de centrale catalogus en laat driverNaam leeg."
        }
        Write-Log "Gebruik reeds geinstalleerde driver '$ResolvedDriverName'."
    } elseif ($PrinterMerk -eq 'Epson') {
        $ResolvedDriverName = Install-EpsonVendorUPD
    } elseif ($PrinterMerk -eq 'Brother') {
        $ResolvedDriverName = Install-BrotherGenericPCL
    } else {
        $ResolvedDriverName = Install-ApprovedDriver -Brand $PrinterMerk -CatalogUrl $DriverCatalogusUrl
    }
    $PortName = 'BIC_TCP_{0}_9100' -f $PrinterIpAdres
    [void](Ensure-TcpPrinterPort -Name $PortName -IpAddress $PrinterIpAdres)
    $ExpectedMarker = "$MarkerPrefix$PrinterMerk"
    [void](Ensure-ManagedPrinterQueue -Name $PrinterNaam -Driver $ResolvedDriverName -PortName $PortName -Comment $ExpectedMarker -AllowedMarker $MarkerPrefix)
    if ($PrinterMerk -eq 'HP') {
        Ensure-HpUPDColorDevice -Name $PrinterNaam -DriverName $ResolvedDriverName -RequireColor ([bool]$Color)
    }
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