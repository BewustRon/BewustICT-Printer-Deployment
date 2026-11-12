#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - Brother Enhanced Generic PCL x64 driver-only installer (PILOT).
.DESCRIPTION
  Uses the manufacturer-signed Brother Enhanced Generic PCL 1.09, NOT the
  Brother Mono Universal Printer (PCL) that requires manual device discovery.
  Does not search the network or require an attached printer.
  Installs the generic Brother PCL5e Windows print driver through INF/CAT.
  PCL5e is monochrome; output and optional printer features require a pilot test.
#>
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Url='https://download.brother.com/welcome/dlf103331/genp5e-64-dut-109.EXE'
$ExpectedSha='9757643C48FB9EAF04DC9EED503A2F80C105F96E28A3954B201A8E38C3EF8F92'
$DriverName='Brother PCL5e Driver'
$Root=Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\BrotherGenericPCL-1.09'
$Exe=Join-Path $Root 'genp5e-64-dut-109.EXE'
$Extract=Join-Path $Root 'Extracted'
$InfRelative='DUT\BHPCL5E.INF'
$CatRelative='DUT\bhpcl5e.cat'
$SevenUrl='https://github.com/ip7z/7zip/releases/download/26.05/7z2605-extra.7z'
$SevenHash='F27A8F103C84785026EDCBA1F67FAF1357225DF9D19DDB0B7760D55947141BC7'
$SevenArchive=Join-Path $Root '7z2605-extra.7z'
$SevenDir=Join-Path $Root '7ZipPortable'

function Assert-Sha([string]$Path,[string]$Hash) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)) {throw "Required file missing: $Path"}
    $Actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    if($Actual -ne $Hash) {throw "SHA256 mismatch for '$Path': $Actual"}
}
function Assert-Signature([string]$Path,[string]$ExpectedSigner) {
    $Signature=Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    $Subject=[string]$Signature.SignerCertificate.Subject
    if($Signature.Status -ne 'Valid' -or $Subject -notmatch $ExpectedSigner) {
        throw "Authenticode invalid for '$Path': status=$($Signature.Status), signer=$Subject"
    }
}
try {
    if(-not [Environment]::Is64BitProcess) {throw '64-bit Windows PowerShell is required.'}
    $Who=[Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal=New-Object Security.Principal.WindowsPrincipal($Who)
    if(-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run as Administrator or SYSTEM is required.'
    }
    Import-Module PrintManagement -ErrorAction Stop
    if((Get-Service -Name Spooler -ErrorAction Stop).Status -ne 'Running') {
        throw 'Print Spooler is not running.'
    }
    $Installed=Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
    if($Installed) {
        if([string]$Installed.Manufacturer -notmatch 'Brother') {
            throw "Unexpected manufacturer for installed '$DriverName': $($Installed.Manufacturer)"
        }
        Write-Host "BROTHER_GENERIC_ALREADY_PRESENT: $DriverName"
        Write-Host 'BROTHER_GENERIC_DRIVER_OK'
        exit 0
    }
    New-Item -ItemType Directory -Path $Root -Force -ErrorAction Stop | Out-Null
    if(-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
        Write-Host "Download signed Brother Enhanced Generic PCL 1.09 from manufacturer."
        Invoke-WebRequest -Uri $Url -OutFile $Exe -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
    }
    Assert-Sha -Path $Exe -Hash $ExpectedSha
    Assert-Signature -Path $Exe -ExpectedSigner 'Brother Industries'

    # Manufacturer SFX must be interpreted as ZIP, not PE resources.
    # Portable 7-Zip Extra is obtained from official publisher and SHA256 pinned.
    if(-not (Test-Path -LiteralPath $SevenArchive -PathType Leaf)) {
        Invoke-WebRequest -Uri $SevenUrl -OutFile $SevenArchive -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
    }
    Assert-Sha -Path $SevenArchive -Hash $SevenHash
    $Tar=Join-Path $env:WINDIR 'System32\tar.exe'
    if(-not (Test-Path -LiteralPath $Tar -PathType Leaf)) {
        throw 'Windows tar.exe is required for portable archive unpacking.'
    }
    if(Test-Path -LiteralPath $SevenDir) {
        Remove-Item -LiteralPath $SevenDir -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $SevenDir -Force -ErrorAction Stop | Out-Null
    & $Tar '-xf' $SevenArchive '-C' $SevenDir
    if($LASTEXITCODE -ne 0) {throw "Failed to unpack portable 7-Zip, exit=$LASTEXITCODE"}
    $SevenExe=Join-Path $SevenDir 'x64\7za.exe'
    foreach($Relative in @('x64\7za.exe','x64\7za.dll','x64\7zxa.dll')) {
        if(-not (Test-Path -LiteralPath (Join-Path $SevenDir $Relative) -PathType Leaf)) {
            throw "Missing portable 7-Zip component: $Relative"
        }
    }
    if(Test-Path -LiteralPath $Extract) {
        Remove-Item -LiteralPath $Extract -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $Extract -Force -ErrorAction Stop | Out-Null
    $SevenOutput=& $SevenExe 'x' '-tzip' $Exe ('-o'+$Extract) '-y' '-bso0' '-bsp0' 2>&1
    if($LASTEXITCODE -ne 0) {
        throw "Brother Enhanced Generic PCL ZIP extraction failed: $($SevenOutput -join ' ')"
    }
    $Inf=Join-Path $Extract $InfRelative
    $Cat=Join-Path $Extract $CatRelative
    if(-not (Test-Path -LiteralPath $Inf -PathType Leaf) -or
       -not (Test-Path -LiteralPath $Cat -PathType Leaf)) {
        throw 'Brother Enhanced Generic PCL INF/CAT missing.'
    }
    Assert-Signature -Path $Cat -ExpectedSigner 'Microsoft Windows Hardware Compatibility Publisher'
    $Pnp=Join-Path $env:WINDIR 'System32\pnputil.exe'
    $Result=& $Pnp '/add-driver' $Inf 2>&1
    if($LASTEXITCODE -ne 0) {
        throw "pnputil failed: $($Result -join ' ')"
    }
    Add-PrinterDriver -Name $DriverName -ErrorAction Stop
    $Registered=Get-PrinterDriver -Name $DriverName -ErrorAction Stop
    if(-not $Registered -or $Registered.Name -ne $DriverName -or
       [string]$Registered.Manufacturer -notmatch 'Brother') {
        throw 'Brother PCL5e driver registration verification failed.'
    }
    Write-Host "BROTHER_GENERIC_DRIVER_REGISTERED=$($Registered.Name)"
    Write-Host 'BROTHER_GENERIC_DRIVER_OK'
    exit 0
} catch {
    Write-Error ('BROTHER_GENERIC_DRIVER_FAILED: '+$_.Exception.Message)
    exit 1
}
