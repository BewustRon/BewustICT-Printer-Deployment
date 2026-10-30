#Requires -Version 5.1
<#
.SYNOPSIS
 Read-only printerdriver en print-lade diagnose voor Bewust ICT.
.NOTES
 Windows PowerShell 5.1 (64-bit). Wijzigt geen printerconfiguratie.
#>
[CmdletBinding()]
param([string]$PrinterNaam = '')

$ErrorActionPreference='Stop'
Import-Module PrintManagement -ErrorAction Stop
$folder=Join-Path $env:ProgramData ('BewustICT\PrinterDeployment\Diagnostics\'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -Path $folder -ItemType Directory -Force | Out-Null
Get-PrinterDriver | Select-Object Name,Manufacturer,PrinterEnvironment,MajorVersion |
    Export-Csv (Join-Path $folder 'Drivers.csv') -NoTypeInformation -Encoding UTF8
Get-Printer | Select-Object Name,DriverName,PortName,Comment |
    Export-Csv (Join-Path $folder 'Printers.csv') -NoTypeInformation -Encoding UTF8
Write-Output "Resultaten: $folder"
if (-not $PrinterNaam) {
    Write-Output 'Geef -PrinterNaam op voor een specifieke queue en papierladen.'
    exit 0
}
$p=Get-Printer -Name $PrinterNaam -ErrorAction Stop
$c=Get-PrintConfiguration -PrinterName $PrinterNaam -ErrorAction Stop
Write-Output ("Queue={0}; Driver={1}; Port={2}; Color={3}; Duplex={4}; Paper={5}" -f $p.Name,$p.DriverName,$p.PortName,$c.Color,$c.DuplexingMode,$c.PaperSize)
if ($c.PrintTicketXml) {
    [IO.File]::WriteAllText((Join-Path $folder 'PrintTicket.xml'),[string]$c.PrintTicketXml,[Text.Encoding]::UTF8)
}
try {
    try { Add-Type -AssemblyName ReachFramework -ErrorAction Stop }
    catch { Add-Type -AssemblyName System.Printing -ErrorAction Stop }
    $server=New-Object System.Printing.LocalPrintServer
    try {
        $queue=$server.GetPrintQueue($PrinterNaam)
        try {
            $stream=$queue.GetPrintCapabilitiesAsXml()
            try {
                $bytes=$stream.ToArray()
                [IO.File]::WriteAllBytes((Join-Path $folder 'PrintCapabilities.xml'),$bytes)
                [xml]$xml=[Text.Encoding]::UTF8.GetString($bytes)
                $lines=@()
                foreach($f in @($xml.SelectNodes("//*[local-name()='Feature' and contains(@name,'InputBin')]"))) {
                    $lines+="Feature: "+$f.GetAttribute('name')
                    foreach($o in @($f.SelectNodes("./*[local-name()='Option']"))) {
                        $labels=@($o.GetAttribute('name'))
                        $labels+=@($o.SelectNodes(".//*[local-name()='Property' and contains(@name,'DisplayName')]//*[local-name()='Value']")|ForEach-Object{$_.InnerText})
                        $lines+="Option: "+($labels -join ' | ')
                    }
                }
                $lines | Set-Content (Join-Path $folder 'Papierladen.txt') -Encoding UTF8
                if ($lines.Count -eq 0) { Write-Warning 'Geen InputBin-features gevonden.' }
                else { $lines | ForEach-Object { Write-Output $_ } }
            } finally { if($stream){$stream.Dispose()} }
        } finally { if($queue){$queue.Dispose()} }
    } finally { if($server){$server.Dispose()} }
} catch {
    Write-Warning ("PrintCapabilities niet beschikbaar: "+$_.Exception.Message)
}
Write-Output 'Read-only diagnose voltooid.'
