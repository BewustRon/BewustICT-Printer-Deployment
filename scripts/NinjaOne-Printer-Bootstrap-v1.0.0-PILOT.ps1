#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - NinjaOne Printer toevoegen v1.0.0-PILOT.
.DESCRIPTION
  Pinned, SHA256-verified central printer deployment.
  Brother now uses Enhanced Generic PCL5e without interactive device selection.
  NinjaOne Script Variables are inherited in the PowerShell child process.
#>
$ErrorActionPreference='Stop'
$Commit='664529c36930cedeb5c6242139a23f40ececa12c'
$ExpectedSha256='4E7649FA00DDABE61C1D0D0AFE33990DA5EE98C6338D957F08BDE7337CF7612B'
$Url="https://raw.githubusercontent.com/BewustRon/BewustICT-Printer-Deployment/$Commit/scripts/Deploy-BewustICTPrinter.ps1"
$Folder=Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\Launcher'
$File=Join-Path $Folder ('Deploy-'+[guid]::NewGuid().ToString('N')+'.ps1')
try {
    if(-not [Environment]::Is64BitProcess) {throw '64-bit Windows PowerShell 5.1 is required.'}
    New-Item -ItemType Directory -Path $Folder -Force -ErrorAction Stop | Out-Null
    Write-Host "Bewust ICT Printerdeployment v1.0.0-PILOT. Pinned commit: $Commit"
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
