#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - NinjaOne printerdeployment launcher v0.8.0-PILOT.
.DESCRIPTION
  Downloadt uitsluitend de vastgepinde en SHA256-gecontroleerde centrale
  printerdeployment code. NinjaOne Script Variables blijven als process
  environment variables beschikbaar in het PowerShell-childproces.
  Voor Epson geverifieerd in Windows; andere merken blijven fail-closed.
#>
$ErrorActionPreference = 'Stop'
$commit = '66a830be3175cfc835597a232b1bc87ae3924fb6'
$expectedSha256 = 'DAAA9F1DDAA3844A2E9FBF76E35D703A36936C9C64BB04D058131E9628ADE6FA'
$url = 'https://raw.githubusercontent.com/BewustRon/BewustICT-Printer-Deployment/' +
       $commit + '/scripts/Deploy-BewustICTPrinter.ps1'
$directory = Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\Launcher'
$file = Join-Path $directory ('Deploy-{0}.ps1' -f [guid]::NewGuid().ToString('N'))

try {
    if (-not [Environment]::Is64BitProcess) { throw 'Windows PowerShell 64-bit vereist.' }
    New-Item -ItemType Directory -Force -Path $directory -ErrorAction Stop | Out-Null
    Write-Host ('Bewust ICT printerdeploy v0.8.0-PILOT. Pinned GitHub commit: ' + $commit)
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
