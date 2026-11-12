#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - NinjaOne Printer toevoegen v1.2.0-PILOT.
.DESCRIPTION
  Pinned, SHA256-verified central printer deployment.
  One universal manufacturer driver per brand, and strict *offline* paper-source aliases (HP Tray/Lade 2 vs Epson Cassette 2) without silent fallback.
  NinjaOne Script Variables are inherited in the PowerShell child process.
#>
$ErrorActionPreference='Stop'
$Commit='cf351260f354deae96ae02d4abc0b087543255cb'
$ExpectedSha256='CFA0D2EF9A1CCA0AC3AC5FFADDA914482447ED1AADD55F1067BABAD15A970A1B'
$Url="https://raw.githubusercontent.com/BewustRon/BewustICT-Printer-Deployment/$Commit/scripts/Deploy-BewustICTPrinter.ps1"
$Folder=Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\Launcher'
$File=Join-Path $Folder ('Deploy-'+[guid]::NewGuid().ToString('N')+'.ps1')
try {
    if(-not [Environment]::Is64BitProcess) {throw '64-bit Windows PowerShell 5.1 is required.'}
    New-Item -ItemType Directory -Path $Folder -Force -ErrorAction Stop | Out-Null
    Write-Host "Bewust ICT Printerdeployment v1.2.0-PILOT. Pinned commit: $Commit"
    Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
    $ActualHash=(Get-FileHash -LiteralPath $File -Algorithm SHA256 -ErrorAction Stop).Hash
    if($ActualHash -ne $ExpectedSha256) {
        throw "SCRIPT_HASH_MISMATCH expected=$ExpectedSha256 actual=$ActualHash"
    }
    Write-Host 'Integriteitscontrole geslaagd. Centrale deployment start.'
    $PowerShell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $PowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $File
    $ExitCode=$LASTEXITCODE
    if($ExitCode -ne 0) {
        throw "Central printer deployment failed, exitcode=$ExitCode"
    }
    Write-Host 'NINJAONE_PRINTER_AUTOMATION_OK'
    exit 0
} catch {
    Write-Error ('NINJAONE_PRINTER_AUTOMATION_FAILED: '+$_.Exception.Message)
    exit 1
} finally {
    if(Test-Path -LiteralPath $File -PathType Leaf) {
        Remove-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue
    }
}
