#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - Epson UPD v2.122.00 OFFLINE PILOT voor NinjaOne/Windows.
.DESCRIPTION
  Downloadt de originele SEIKO EPSON driver van ftp.epson.com via HTTPS;
  controleert vaste SHA256, digitale handtekeningen, INF-hash en CAT;
  pakt PE/ZIP uit met ingebouwde .NET (geen 7-Zip);
  registreert de driver met PnPUtil en Add-PrinterDriver;
  maakt optioneel drie BIC EPSON PILOT TCP/IP-printers aan zonder ping/discovery.

  PILOT: Alleen voor 1 werkplek. Niet automatisch uitrollen bij klanten.
  Papierlades worden gerapporteerd maar nog niet aangepast; eerst valideren.
  Bestaande printers en standaardprinter worden NIET gewijzigd.
.PARAMETER Actie
  Installeren: driver en 3 testqueues.
  DriverOnly: alleen driver registratie (voor CI).
  Verwijderen: uitsluitend 3 gemarkeerde testqueues verwijderen.
.PARAMETER PrinterIpAdres
  Voorbeeldprinters op 192.168.53.50; er wordt niet naar dit IP verbonden.
#>
[CmdletBinding()]
param(
    [ValidateSet('Installeren','DriverOnly','Verwijderen')]
    [string]$Actie = 'Installeren',
    [string]$PrinterIpAdres = '192.168.53.50'
)
$ErrorActionPreference = 'Stop'
$Version = '0.7.0-PILOT'
$VendorUrl = 'https://ftp.epson.com/drivers/EUPD_x64_212200.exe'
$VendorSha256 = '3CC1C313ADFAB74F957E2AF63FF2FA87279169E3A043365EB0AF6024D420663B'
$InfSha256 = 'C4AE14C42E42147288B143F36E1EE10DF003656C6363AB9A17C0D6F6A0592F2D'
$RelativeInf = 'Universal_Print_Driver_x64_212200\E_JFB0DE.INF'
$RelativeCat = 'Universal_Print_Driver_x64_212200\e_jfb0de.cat'
$DriverName = 'EPSON Universal Print Driver'
$Root = Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\EpsonPilot'
$PackagePath = Join-Path $Root 'EUPD_x64_212200.exe'
$ExtractPath = Join-Path $Root 'Extracted'
$LogDir = Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\Logs'
$Marker = 'BewustICT-EPSON-PILOT|0.7.0'
$QueueNames = @(
    'BIC EPSON PILOT - Blanco Kleur',
    'BIC EPSON PILOT - Blanco Zwart Wit',
    'BIC EPSON PILOT - CMR'
)

function Write-Log {
    param([string]$Text,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $entry = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Text
    Write-Host $entry
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $entry -Encoding UTF8 }
}
function Assert-Elevated {
    if (-not [Environment]::Is64BitProcess) { throw '64-bit Windows PowerShell vereist.' }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run as SYSTEM of Administrator vereist.'
    }
}
function Assert-Spooler {
    $svc = Get-Service -Name Spooler -ErrorAction Stop
    if ($svc.Status -ne 'Running') {
        throw "Print Spooler is niet gestart (status $($svc.Status)); deze test wijzigt de service niet."
    }
}
function Check-HexHash {
    param([string]$File,[string]$Expected,[string]$Subject)
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "$Subject ontbreekt: $File" }
    $actual = (Get-FileHash -LiteralPath $File -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($actual -ne $Expected) { throw "SHA256 afwijkend voor $Subject! Got $actual; expected $Expected." }
    Write-Log "$Subject SHA256 OK: $actual"
}
function Check-Authenticode {
    param([string]$Path,[string]$SubjectPattern,[string]$Label)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    $subject = [string]$signature.SignerCertificate.Subject
    if ($signature.Status -ne 'Valid' -or $subject -notmatch $SubjectPattern) {
        throw "Handtekening ongeldig voor ${Label}: $($signature.Status); subject='$subject'."
    }
    Write-Log "$Label authenticode OK: $subject"
}
function Ensure-Driver {
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        Write-Log "Download officiële Epson-driver: $VendorUrl"
        Invoke-WebRequest -Uri $VendorUrl -OutFile $PackagePath -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
    }
    # Geen uitvoeren van vendor EXE; alleen openen als ondertekende ZIP/SFX.
    Check-HexHash -File $PackagePath -Expected $VendorSha256 -Subject 'Epson installatiepakket'
    Check-Authenticode -Path $PackagePath -SubjectPattern 'SEIKO EPSON CORPORATION' -Label 'Epson EXE'

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $zip = [IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        [long]$totalLength = 0
        $base = [IO.Path]::GetFullPath($ExtractPath).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
        foreach ($entry in $zip.Entries) {
            if (-not $entry.FullName) { continue }
            $entryPath = [IO.Path]::GetFullPath((Join-Path $ExtractPath $entry.FullName))
            if (-not $entryPath.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) {
                throw "Onveilig pad in Epson-archief: $($entry.FullName)"
            }
            $totalLength += [long]$entry.Length
            if ($totalLength -gt 1073741824) { throw 'Epson pakket groter dan 1 GiB ongecomprimeerd.' }
        }
    } finally { $zip.Dispose() }

    if (Test-Path -LiteralPath $ExtractPath) { Remove-Item -LiteralPath $ExtractPath -Recurse -Force }
    [IO.Compression.ZipFile]::ExtractToDirectory($PackagePath,$ExtractPath)
    Write-Log 'Epson PE/ZIP uitgepakt met Windows .NET (geen extra software nodig).'
    $Inf = Join-Path $ExtractPath $RelativeInf
    $Cat = Join-Path $ExtractPath $RelativeCat
    Check-HexHash -File $Inf -Expected $InfSha256 -Subject 'Epson driver INF'
    if (-not (Test-Path -LiteralPath $Cat -PathType Leaf)) { throw 'Bijbehorende Epson CAT ontbreekt.' }
    Check-Authenticode -Path $Cat -SubjectPattern 'Microsoft Windows Hardware Compatibility Publisher' -Label 'Microsoft WHCP CAT'

    Import-Module PrintManagement -ErrorAction Stop
    Assert-Spooler
    $Current = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
    if ($Current) {
        Write-Log "Drivernaam '$DriverName' is al in Windows geregistreerd. Exacte driver-versie controleren bij vervolgstap." 'WARN'
    } else {
        $Pnp = Join-Path $env:WINDIR 'System32\pnputil.exe'
        Write-Log "PnPUtil: stage INF '$RelativeInf' zonder fysieke printer."
        $PnpOutput = & $Pnp '/add-driver' $Inf 2>&1
        foreach($line in @($PnpOutput)) { Write-Log ("PnPUtil: " + [string]$line) }
        if ($LASTEXITCODE -ne 0) {
            throw "PnPUtil /add-driver faalde met exitcode $LASTEXITCODE."
        }
        Write-Log "Windows printerdriver toevoegen: $DriverName"
        Add-PrinterDriver -Name $DriverName -ErrorAction Stop
    }
    $Current = Get-PrinterDriver -Name $DriverName -ErrorAction Stop
    if (-not $Current -or $Current.Name -ne $DriverName) { throw 'Epson-driver niet aantoonbaar geregistreerd.' }
    Write-Log "EPSON_DRIVER_OK: $($Current.Name) / environment=$($Current.PrinterEnvironment)"
}
function Get-PrinterByName {
    param([string]$Name)
    Get-Printer -Name $Name -ErrorAction SilentlyContinue
}
function Remove-PilotPrinters {
    $previous = @(Get-Printer -ErrorAction Stop)
    foreach ($Name in $QueueNames) {
        $Current = Get-PrinterByName -Name $Name
        if (-not $Current) { continue }
        if ([string]$Current.Comment -ne $Marker) {
            throw "Niet-gemarkeerde printer '$Name' gevonden. Automatisch verwijderen geweigerd."
        }
    }
    foreach ($Name in $QueueNames) {
        $Current = Get-PrinterByName -Name $Name
        if ($Current) {
            Remove-Printer -Name $Name -ErrorAction Stop
            Write-Log "Pilotqueue verwijderd: $Name"
        }
    }
    Write-Log 'EPSON_PILOT_CLEANUP_OK: gemarkeerde queues verwijderd; fabrikantdriver behouden.'
}
function Create-PilotPrinters {
    param([string]$Ip)
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Ip,[ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Ongeldig IPv4-adres: '$Ip'."
    }
    $PortName = 'BIC_EPSON_PILOT_{0}_9100' -f $Ip
    foreach ($Name in $QueueNames) {
        $current = Get-PrinterByName -Name $Name
        if ($current -and [string]$current.Comment -ne $Marker) {
            throw "Naamconflict met niet-gemarkeerde queue '$Name'. Geen wijziging toegestaan."
        }
    }
    $port = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    if (-not $port) {
        Add-PrinterPort -Name $PortName -PrinterHostAddress $Ip -PortNumber 9100 -ErrorAction Stop
        Write-Log "TCP/IP-poort gemaakt voor $Ip zonder ping of WSD/IPP discovery."
        $port = Get-PrinterPort -Name $PortName -ErrorAction Stop
    }
    if ([string]$port.PrinterHostAddress -ne $Ip) {
        throw "Bestaat al met afwijkend adres: $PortName."
    }
    $results = @(
        @{Name=$QueueNames[0]; Color=$true},
        @{Name=$QueueNames[1]; Color=$false},
        @{Name=$QueueNames[2]; Color=$false}
    )
    foreach ($item in $results) {
        $current = Get-PrinterByName -Name $item.Name
        if (-not $current) {
            Add-Printer -Name $item.Name -DriverName $DriverName -PortName $PortName -Comment $Marker -ErrorAction Stop
            Write-Log "Printerqueue toegevoegd: $($item.Name)"
        } else {
            if ($current.DriverName -ne $DriverName -or $current.PortName -ne $PortName) {
                throw "Reeds bestaande gemarkeerde pilotqueue '$($item.Name)' heeft andere driver of poort; geen wijziging."
            }
        }
        # Zet alleen standaardinstellingen die de gedownloade driver ondersteunt.
        try {
            Set-PrintConfiguration -PrinterName $item.Name -Color ([bool]$item.Color) -DuplexingMode OneSided -PaperSize A4 -ErrorAction Stop
            $cfg = Get-PrintConfiguration -PrinterName $item.Name -ErrorAction Stop
            if ([bool]$cfg.Color -ne [bool]$item.Color -or [string]$cfg.DuplexingMode -ne 'OneSided' -or
                [string]$cfg.PaperSize -ne 'A4') {
                Write-Log "CONFIG_PENDING: driver heeft kleur/duplex/A4 niet allemaal behouden voor '$($item.Name)'." 'WARN'
            } else {
                Write-Log "CONFIG_OK: '$($item.Name)' kleur=$($cfg.Color), duplex=$($cfg.DuplexingMode), papier=$($cfg.PaperSize)."
            }
        } catch {
            Write-Log "CONFIG_PENDING: '$($item.Name)': $($_.Exception.Message)" 'WARN'
        }
        $actual = Get-PrinterByName -Name $item.Name
        if (-not $actual -or $actual.DriverName -ne $DriverName -or $actual.PortName -ne $PortName -or
            [string]$actual.Comment -ne $Marker) {
            throw "Queue-verificatie mislukt: '$($item.Name)'."
        }
        Write-Log "EPSON_QUEUE_OK: $($item.Name)"
    }
    Write-Log 'EPSON_OFFLINE_QUEUES_OK: 3/3 met echte Epson-driver en onbereikbare printer.'
    Write-Log 'TRAY_PENDING: Cassette 1/2 nog niet ingesteld of fysiek geverifieerd; dit komt na driverpilot.' 'WARN'
}

try {
    Assert-Elevated
    New-Item -Path $Root -ItemType Directory -Force | Out-Null
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    $script:LogFile = Join-Path $LogDir ('EpsonPilot-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log')
    Write-Log "Bewust ICT Epson UPD OFFLINE $Version - Actie=$Actie - IP=$PrinterIpAdres"
    if ($Actie -eq 'Verwijderen') {
        Import-Module PrintManagement -ErrorAction Stop
        Remove-PilotPrinters
        exit 0
    }
    Ensure-Driver
    if ($Actie -eq 'DriverOnly') { Write-Log 'EPSON_DRIVER_ONLY_OK'; exit 0 }
    Create-PilotPrinters -Ip $PrinterIpAdres
    exit 0
} catch {
    Write-Log ("FAILED: " + $_.Exception.Message) 'ERROR'
    Write-Log ("Logbestand: " + $script:LogFile) 'ERROR'
    exit 1
}
