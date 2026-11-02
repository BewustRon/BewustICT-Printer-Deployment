#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - Brother Mono Universal Printer (PCL) v1.10.1.0 offline pilot.
.DESCRIPTION
  Original signed Brother package directly from download.brother.com.
  Verify fixed SHA256, valid Brother EXE signature, Microsoft WHCP CAT and INF hash.
  Extract SFX as ZIP without launching Brother's installer.
  Register via pnputil and Add-PrinterDriver, then optionally create a TCP/9100
  printer queue on TEST-NET-1, without contacting a physical printer.
.NOTES
  READ CAREFULLY: pilot only, Windows PowerShell 5.1 x64 admin/SYSTEM;
  do not deploy broadly until Brother DCP-L5500DN on-site printing is tested.
  Never copies vendor driver binaries to GitHub.
#>
[CmdletBinding()]
param(
    [ValidateSet('DriverOnly','Installeren')][string]$Actie='DriverOnly',
    [string]$PrinterNaam='BIC BROTHER PILOT - DCP-L5500DN',
    [string]$PrinterIpAdres='192.0.2.50'
)
$ErrorActionPreference='Stop'
$Url='https://download.brother.com/welcome/dlf107285/UNIV-PCL-01101.EXE'
$Hash='BA40F5EFE1D1D3896139BC31BC28B4A3F2E75C76684987239019DB6A68D6977D'
$InfHash='EF0277FF8789E21B89EBFA7C40E4E0AAAB37CC5963FF4F9145D5AF7F43D927D5'
$InfRelative='PCL\PCL\64\BRUPCB0A.INF'
$CatRelative='PCL\PCL\64\BRUPCB0A.cat'
$Driver='Brother Mono Universal Printer (PCL)'
$Root=Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\BrotherPilot'
$Exe=Join-Path $Root 'UNIV-PCL-01101.EXE'
$Extract=Join-Path $Root 'Extracted'

function Check-Sha256([string]$Path,[string]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {throw "MISSING $Label at $Path"}
    $Actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($Actual -ne $Expected) {throw "HASH_MISMATCH $Label expected=$Expected actual=$Actual"}
    Write-Host ("SHA256_OK {0}={1}" -f $Label,$Actual)
}
function Check-Signature([string]$Path,[string]$ExpectedSigner,[string]$Label) {
    $s=Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    $subject=[string]$s.SignerCertificate.Subject
    if ($s.Status -ne 'Valid' -or $subject -notmatch $ExpectedSigner) {
        throw "INVALID_SIGNER $Label status=$($s.Status) signer=$subject"
    }
    Write-Host ("SIGNATURE_OK {0} {1}" -f $Label,$subject)
}
try {
    if (-not [Environment]::Is64BitProcess) {throw 'Windows PowerShell x64 required.'}
    $who=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($who)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'Administrator or SYSTEM required.'}
    New-Item -ItemType Directory -Path $Root -Force -ErrorAction Stop | Out-Null
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
        Write-Host ("DOWNLOAD_BROTHER_ORIGINAL=" + $Url)
        Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $Exe -TimeoutSec 240 -ErrorAction Stop
    }
    Check-Sha256 -Path $Exe -Expected $Hash -Label 'Brother EXE'
    Check-Signature -Path $Exe -ExpectedSigner 'Brother Industries' -Label 'Brother EXE'

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    # Brother SFX: ZipFile.ExtractToDirectory kan een afwijkende EOCD/telling
    # afwijzen. Lees de reeds geverifieerde SFX slechts eenmaal en extraheer
    # daarna de zichtbare entries individueel, met pad- en volumelimieten.
    $zip=[IO.Compression.ZipFile]::OpenRead($Exe)
    try {
        [long]$unzipped=0
        $entries=@($zip.Entries)
        Write-Host ("BROTHER_ZIP_ENTRIES={0}" -f $entries.Count)
        if ($entries.Count -lt 1 -or $entries.Count -gt 10000) {throw 'UNEXPECTED_ZIP_ENTRY_COUNT'}
        $base=[IO.Path]::GetFullPath($Extract).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
        foreach ($entry in $entries) {
            if (-not $entry.FullName) {continue}
            $relative=$entry.FullName.Replace('/','\')
            $dest=[IO.Path]::GetFullPath((Join-Path $Extract $relative))
            if (-not $dest.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) {
                throw "ZIP_SLIP_PROTECTION_TRIGGERED $($entry.FullName)"
            }
            $unzipped += [long]$entry.Length
            if ($unzipped -gt 512MB) {throw "UNCOMPRESSED_SIZE_TOO_LARGE $unzipped"}
        }
        if (Test-Path -LiteralPath $Extract) {
            Remove-Item -LiteralPath $Extract -Recurse -Force -ErrorAction Stop
        }
        [void][IO.Directory]::CreateDirectory($Extract)
        $filesWritten=0
        foreach ($entry in $entries) {
            $relative=$entry.FullName.Replace('/','\')
            $dest=[IO.Path]::GetFullPath((Join-Path $Extract $relative))
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                [void][IO.Directory]::CreateDirectory($dest)
                continue
            }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
            $inputStream=$null
            $outputStream=$null
            try {
                $inputStream=$entry.Open()
                $outputStream=[IO.File]::Open($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
                $inputStream.CopyTo($outputStream)
            } finally {
                if ($null -ne $outputStream) {$outputStream.Dispose()}
                if ($null -ne $inputStream) {$inputStream.Dispose()}
            }
            $filesWritten++
            if ($filesWritten -le 4) {Write-Host ("EXTRACTED_ENTRY="+$relative)}
        }
        Write-Host ("BROTHER_MANAGED_EXTRACTION_COMPLETE files={0}" -f $filesWritten)
    } finally {$zip.Dispose()}

    $Inf=Join-Path $Extract $InfRelative
    $Cat=Join-Path $Extract $CatRelative
    Check-Sha256 -Path $Inf -Expected $InfHash -Label 'Brother x64 INF'
    Check-Signature -Path $Cat -ExpectedSigner 'Microsoft Windows Hardware Compatibility Publisher' -Label 'Brother x64 CAT'

    Import-Module PrintManagement -ErrorAction Stop
    $svc=Get-Service Spooler -ErrorAction Stop
    if ($svc.Status -ne 'Running') {throw "SPOOLER_NOT_RUNNING status=$($svc.Status)"}
    if (-not (Get-PrinterDriver -Name $Driver -ErrorAction SilentlyContinue)) {
        $pnp=Join-Path $env:WINDIR 'System32\pnputil.exe'
        Write-Host 'BROTHER_PNPUTIL_STAGE_START'
        $pnpOutput=& $pnp '/add-driver' $Inf 2>&1
        $exit=$LASTEXITCODE
        foreach ($line in @($pnpOutput)) {Write-Host ("PNPUTIL: "+[string]$line)}
        if ($exit -ne 0) {throw "BROTHER_PNPUTIL_FAILURE exit=$exit"}
        Add-PrinterDriver -Name $Driver -ErrorAction Stop
    }
    $registered=Get-PrinterDriver -Name $Driver -ErrorAction Stop
    if ($registered.Name -ne $Driver) {throw 'BROTHER_DRIVER_MISMATCH'}
    Write-Host ("BROTHER_DRIVER_REGISTERED={0};ENV={1}" -f $registered.Name,$registered.PrinterEnvironment)
    if ($Actie -eq 'DriverOnly') {
        Write-Host 'BROTHER_DRIVER_ONLY_OK'
        exit 0
    }

    $ip=$null
    if (-not [Net.IPAddress]::TryParse($PrinterIpAdres,[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'Invalid IPv4 address.'
    }
    $portName='BIC_BROTHER_PILOT_{0}_9100' -f $PrinterIpAdres
    $marker='BewustICT-BROTHER-PILOT|1.10.1.0'
    $existing=Get-Printer -Name $PrinterNaam -ErrorAction SilentlyContinue
    if ($existing -and [string]$existing.Comment -ne $marker) {throw 'PRINTER_NAME_COLLISION_UNMANAGED'}
    $port=Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue
    if (-not $port) {
        Add-PrinterPort -Name $portName -PrinterHostAddress $PrinterIpAdres -PortNumber 9100 -ErrorAction Stop
        $port=Get-PrinterPort -Name $portName -ErrorAction Stop
    }
    if ([string]$port.PrinterHostAddress -ne $PrinterIpAdres) {throw 'PORT_HOST_MISMATCH'}
    if (-not $existing) {
        Add-Printer -Name $PrinterNaam -DriverName $Driver -PortName $portName -Comment $marker -ErrorAction Stop
    } elseif ($existing.DriverName -ne $Driver -or $existing.PortName -ne $portName) {
        throw 'EXISTING_PRINTER_DIFFERENT_DRIVER_OR_PORT'
    }
    $queue=Get-Printer -Name $PrinterNaam -ErrorAction Stop
    if ($queue.DriverName -ne $Driver -or $queue.PortName -ne $portName) {throw 'PRINTER_QUEUE_VERIFY_FAILED'}
    Write-Host ("BROTHER_OFFLINE_QUEUE_OK: {0}; IP={1}; Driver={2}" -f $PrinterNaam,$PrinterIpAdres,$Driver)
    try {
        Set-PrintConfiguration -PrinterName $PrinterNaam -Color $false -DuplexingMode OneSided -PaperSize A4 -ErrorAction Stop
        $cfg=Get-PrintConfiguration -PrinterName $PrinterNaam -ErrorAction Stop
        if ($cfg.Color -or [string]$cfg.DuplexingMode -ne 'OneSided' -or [string]$cfg.PaperSize -ne 'A4') {
            throw 'BROTHER_PRINT_CONFIG_NOT_PERSISTED'
        }
        Write-Host 'BROTHER_PRINT_CONFIG_OK: MONO/OneSided/A4'
    } catch {
        Write-Warning ('BROTHER_PRINT_CONFIG_PENDING: '+$_.Exception.Message)
    }
    Write-Host 'BROTHER_OFFLINE_PILOT_OK: physical print and driver device selection NOT YET verified.'
    exit 0
} catch {
    Write-Error ('BROTHER_PILOT_FAILED: '+$_.Exception.Message)
    exit 1
}
