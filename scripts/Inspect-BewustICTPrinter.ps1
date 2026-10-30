#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - READ-ONLY diagnose papierladen van een lokale Windows-printerqueue.
.DESCRIPTION
  Leest via System.Drawing.Printing.PrinterSettings de drivergerapporteerde
  papierbronnen en hun RawKind-IDs uit. Er hoeft GEEN printer online te zijn.
  De waarde van SourceName komt van de printerdriver; hiermee is niet bewezen
  dat de fysieke printer de lade ook daadwerkelijk heeft.
.NOTES
  Windows PowerShell 5.1 x64; uitvoeren onder Administrator/SYSTEM.
  Als de driver geen bronnen aanbiedt, eindigt dit script met een fout,
  niet met een onterechte successmelding.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$PrinterNaam
)
$ErrorActionPreference = 'Stop'
Import-Module PrintManagement -ErrorAction Stop
$printer = Get-Printer -Name $PrinterNaam -ErrorAction Stop
$configuration = Get-PrintConfiguration -PrinterName $PrinterNaam -ErrorAction Stop
$root = Join-Path $env:ProgramData 'BewustICT\PrinterDeployment\Diagnostics'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$safeName = $PrinterNaam -replace '[^A-Za-z0-9_.-]', '_'
$folder = Join-Path $root ($stamp + '-' + $safeName)
New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null

Write-Output ("PRINTER_INFO Name='{0}'; Driver='{1}'; Port='{2}'; Kleur={3}; Duplex={4}; Papier={5}" -f
    $printer.Name,$printer.DriverName,$printer.PortName,$configuration.Color,
    $configuration.DuplexingMode,$configuration.PaperSize)

# Geen WPF ReachFramework/System.Printing nodig; werkt ook zonder de printer online.
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
$settings = New-Object System.Drawing.Printing.PrinterSettings
$settings.PrinterName = $PrinterNaam
if (-not $settings.IsValid) {
    throw "PrinterSettings heeft '$PrinterNaam' als ongeldige queue gemeld."
}

$sources = New-Object 'System.Collections.Generic.List[object]'
foreach ($source in $settings.PaperSources) {
    $sources.Add([pscustomobject]@{
        SourceName = [string]$source.SourceName
        RawKind = [int]$source.RawKind
        Kind = [string]$source.Kind
    })
}
if ($sources.Count -lt 1) {
    throw "TRAYS_NOT_AVAILABLE: driver '$($printer.DriverName)' rapporteert geen papierbronnen."
}
$csvPath = Join-Path $folder 'Papierladen.csv'
$sources | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
Write-Output ("PAPER_SOURCES_COUNT={0}" -f $sources.Count)
foreach ($source in $sources) {
    Write-Output ("PAPER_SOURCE Name='{0}' RawKind={1} Kind='{2}'" -f $source.SourceName,$source.RawKind,$source.Kind)
}
try {
    $defaultSource = $settings.DefaultPageSettings.PaperSource
    if ($null -ne $defaultSource) {
        Write-Output ("DRIVER_DEFAULT_PAPER_SOURCE Name='{0}' RawKind={1}" -f
            $defaultSource.SourceName,$defaultSource.RawKind)
    }
} catch {
    Write-Warning ('Standaardbron is niet opvraagbaar: ' + $_.Exception.Message)
}

# PrintTicket is aanvullend informatief, zonder deze te wijzigen.
$ticketString = [string]$configuration.PrintTicketXml
if (-not [string]::IsNullOrWhiteSpace($ticketString)) {
    $ticketPath = Join-Path $folder 'PrintTicket.xml'
    [IO.File]::WriteAllText($ticketPath,$ticketString,[Text.Encoding]::UTF8)
    try {
        [xml]$ticket = $ticketString
        $features = @($ticket.SelectNodes("//*[local-name()='Feature' and contains(@name,'InputBin')]"))
        Write-Output ("PRINTTICKET_INPUTBIN_FEATURES={0}" -f $features.Count)
        foreach ($feature in $features) {
            $option = @($feature.SelectNodes("./*[local-name()='Option']"))
            $names = @($option | ForEach-Object { $_.GetAttribute('name') })
            Write-Output ("PRINTTICKET_INPUTBIN Feature='{0}' Options='{1}'" -f
                $feature.GetAttribute('name'),($names -join ','))
        }
    } catch {
        Write-Warning ('PrintTicket XML kon niet geinterpreteerd worden: '+$_.Exception.Message)
    }
}
Write-Output ("PAPER_SOURCES_OK: driver heeft {0} papierbronnen teruggegeven." -f $sources.Count)
Write-Output ("RESULTS_PATH={0}" -f $folder)
