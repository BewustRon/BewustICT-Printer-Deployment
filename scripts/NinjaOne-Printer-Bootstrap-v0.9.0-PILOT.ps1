#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - NinjaOne printerdeployment launcher v0.9.0-PILOT.
.DESCRIPTION
  Downloadt uitsluitend de vastgepinde en SHA256-gecontroleerde centrale
  printerdeployment code. NinjaOne Script Variables blijven als process
  environment variables beschikbaar in het PowerShell-childproces.
  Epson en Brother offline getest in Windows CI; overige merken fail-closed.
#>
$ErrorActionPreference = 'Stop'
$commit = 'e779a8fc80357059f70b1c728ee1788aaf5c52b0'
$expectedSha256 = 'E896015B2E12040135B4EBAD5F72D9A05EBEEA4A1974B36F349C0CADD38C8BB6'
$url = 'https://raw.githubusercontent.com/BewustRon/BewustICT-Printer-Deployment/' +
       $commit + '/scripts/Deploy-BewustICTPrinter.ps1'
$directory = Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\Launcher'
$file = Join-Path $directory ('Deploy-{0}.ps1' -f [guid]::NewGuid().ToString('N'))

try {
    if (-not [Environment]::Is64BitProcess) { throw 'Windows PowerShell 64-bit vereist.' }
    New-Item -ItemType Directory -Force -Path $directory -ErrorAction Stop | Out-Null
    Write-Host ('Bewust ICT printerdeploy v0.9.0-PILOT. Pinned GitHub commit: ' + $commit)
    Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($hash -ne $expectedSha256) {
        throw ('SCRIPT_HASH_MISMATCH: verwacht ' + $expectedSha256 + '; gekregen ' + $hash)
    }
    Write-Host 'Integriteitscontrole geslaagd. Centrale deployment start.'
    # Gebruik Windows PowerShell x64. Procesomgevingsvariabelen van NinjaOne worden geerfd.
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('Centrale printerdeployment faalde, exitcode=' + $code) }
    Write-Host 'NINJAONE_PRINTER_AUTOMATION_OK'
    exit 0
}
catch {
    Write-Error ('NINJAONE_PRINTER_AUTOMATION_FAILED: ' + $_.Exception.Message)
    exit 1
}
finally {
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
}
