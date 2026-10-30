#Requires -Version 5.1
<#
.SYNOPSIS
  Bewust ICT - Stel de globale standaardpapierlade voor een BEHEERDE Windows-printerqueue in.
.DESCRIPTION
  Gebruikt de drivergerapporteerde papierbronnen (System.Drawing.Printing)
  en de officiële Windows spooler-API (DocumentProperties + SetPrinter, Level 8).
  Wijzigt alleen de bestaande printerqueue; probeert de fysieke printer NIET te bereiken.
  Werkt merk-onafhankelijk voor drivers die de DEVMODE dmDefaultSource ondersteunen.
  De fysieke printer/driver kan later per-job instellingen overrulen: printtest noodzakelijk.
.PARAMETER PrinterNaam
  Exacte bestaande queue, bijvoorbeeld 'BIC EPSON PILOT - Blanco Kleur'.
.PARAMETER Papierlade
  Exacte papierbron zoals vermeld door de driver ('Cassette 1', 'Cassette 2', enz.).
.PARAMETER Actie
  Controleren (standaard: READ-ONLY) of Instellen (past GLOBAL default queue aan).
.NOTES
  PILOT. Alleen lokale queues die aan Bewust ICT marker zijn herkend.
  Niet-beheerde queues en andere printers worden nooit gewijzigd.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PrinterNaam,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Papierlade,
    [ValidateSet('Controleren','Instellen')][string]$Actie = 'Controleren'
)
$ErrorActionPreference = 'Stop'
Import-Module PrintManagement -ErrorAction Stop

$queue = Get-Printer -Name $PrinterNaam -ErrorAction Stop
$marker = [string]$queue.Comment
if (-not ($marker.StartsWith('BewustICT-EPSON-PILOT|',[StringComparison]::OrdinalIgnoreCase) -or
          $marker.StartsWith('BewustICT-TCP|',[StringComparison]::OrdinalIgnoreCase))) {
    throw "REFUSED_UNMANAGED_QUEUE: '$PrinterNaam' heeft geen bekende Bewust ICT deploymentmarker."
}
if (-not [Environment]::Is64BitProcess) { throw '64-bit Windows PowerShell vereist.' }
if ($Actie -eq 'Instellen') {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Voor Instellen: Run as SYSTEM of Administrator.'
    }
}
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
$settings = New-Object System.Drawing.Printing.PrinterSettings
$settings.PrinterName = $PrinterNaam
if (-not $settings.IsValid) { throw "PrinterSettings.IsValid is False voor '$PrinterNaam'." }
$sources = @($settings.PaperSources)
$matches = @($sources | Where-Object { [string]::Equals([string]$_.SourceName,$Papierlade,[StringComparison]::OrdinalIgnoreCase) })
if ($matches.Count -ne 1) {
    $available = ($sources | ForEach-Object { "$($_.SourceName) (RawKind=$($_.RawKind))" }) -join '; '
    throw "PAPIERLADE_NIET_UNIEK_OF_ONBEKEND: '$Papierlade' komt $($matches.Count)x voor. Beschikbaar: $available"
}
$target = $matches[0]
if ($target.RawKind -lt 1 -or $target.RawKind -gt 32767) {
    throw "Ongeldige dmDefaultSource: $($target.RawKind)"
}
Write-Host ("TRAY_REQUEST Printer='{0}' Driver='{1}' Tray='{2}' RawKind={3} Action={4}" -f
    $PrinterNaam,$queue.DriverName,$target.SourceName,$target.RawKind,$Actie)

if (-not ('BewustICT.PrinterTrayNative' -as [type])) {
    $native = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace BewustICT {
    public static class PrinterTrayNative {
        [StructLayout(LayoutKind.Sequential)]
        private struct PRINTER_DEFAULTS {
            public IntPtr pDatatype;
            public IntPtr pDevMode;
            public uint DesiredAccess;
        }

        [DllImport("winspool.drv", EntryPoint="OpenPrinterW", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool OpenPrinter(string name, out IntPtr handle, ref PRINTER_DEFAULTS defaults);
        [DllImport("winspool.drv", EntryPoint="ClosePrinter", SetLastError=true)]
        private static extern bool ClosePrinter(IntPtr handle);
        [DllImport("winspool.drv", EntryPoint="GetPrinterW", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool GetPrinter(IntPtr handle, uint level, IntPtr output, uint outputLength, out uint needed);
        [DllImport("winspool.drv", EntryPoint="SetPrinterW", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool SetPrinter(IntPtr handle, uint level, IntPtr input, uint command);
        [DllImport("winspool.drv", EntryPoint="DocumentPropertiesW", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern int DocumentProperties(IntPtr hwnd, IntPtr printer, string name,
            IntPtr output, IntPtr input, int mode);

        private const int DM_DEFAULTSOURCE = 0x00000200;
        private const int DM_IN_BUFFER = 0x00000008;
        private const int DM_OUT_BUFFER = 0x00000002;
        private const uint PRINTER_ACCESS_ADMINISTER = 0x00000004;

        private static void AssertDevMode(IntPtr ptr) {
            if (ptr == IntPtr.Zero) throw new InvalidOperationException("Null global DEVMODE.");
            int dmSize = (ushort)Marshal.ReadInt16(ptr,68);
            if (dmSize < 92 || dmSize > 8192)
                throw new InvalidOperationException("Unexpected Unicode DEVMODE dmSize=" + dmSize);
        }

        private static IntPtr GetGlobalModePtr(IntPtr handle, out IntPtr infoBuffer) {
            uint required;
            GetPrinter(handle,8,IntPtr.Zero,0,out required);
            if (required < (uint)IntPtr.Size || required > 4*1024*1024)
                throw new InvalidOperationException("Invalid GetPrinter(8) size=" + required);
            infoBuffer = Marshal.AllocHGlobal((int)required);
            try {
                if (!GetPrinter(handle,8,infoBuffer,required,out required))
                    throw new Win32Exception(Marshal.GetLastWin32Error(),"GetPrinter Level 8 failed");
                IntPtr mode = Marshal.ReadIntPtr(infoBuffer);
                AssertDevMode(mode);
                return mode;
            } catch {
                Marshal.FreeHGlobal(infoBuffer);
                infoBuffer = IntPtr.Zero;
                throw;
            }
        }

        private static IntPtr Open(string name, bool administer) {
            PRINTER_DEFAULTS defaults = new PRINTER_DEFAULTS();
            defaults.DesiredAccess = administer ? PRINTER_ACCESS_ADMINISTER : 0x00000008;
            IntPtr handle;
            if (!OpenPrinter(name,out handle,ref defaults) || handle == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(),"OpenPrinter failed");
            return handle;
        }

        public static int ReadGlobalSource(string name) {
            IntPtr h = Open(name,false);
            IntPtr buf = IntPtr.Zero;
            try {
                IntPtr dm = GetGlobalModePtr(h,out buf);
                int fields = Marshal.ReadInt32(dm,72);
                if ((fields & DM_DEFAULTSOURCE) == 0) return -1;
                return (ushort)Marshal.ReadInt16(dm,88);
            } finally {
                if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf);
                ClosePrinter(h);
            }
        }

        public static string WriteGlobalSource(string name,int value) {
            if (value < 1 || value > 32767) throw new ArgumentOutOfRangeException("value");
            IntPtr h=Open(name,true);
            IntPtr infoBuffer=IntPtr.Zero;
            IntPtr inMode=IntPtr.Zero;
            IntPtr outMode=IntPtr.Zero;
            IntPtr pInfo8=IntPtr.Zero;
            try {
                IntPtr dm=GetGlobalModePtr(h,out infoBuffer);
                int currentFields=Marshal.ReadInt32(dm,72);
                int old=(currentFields & DM_DEFAULTSOURCE) != 0 ? (ushort)Marshal.ReadInt16(dm,88) : -1;
                if (old == value) return "ALREADY_SET";

                int dmSize=(ushort)Marshal.ReadInt16(dm,68);
                int dmExtra=(ushort)Marshal.ReadInt16(dm,70);
                int actual=checked(dmSize+dmExtra);
                int recommended=DocumentProperties(IntPtr.Zero,h,name,IntPtr.Zero,IntPtr.Zero,0);
                if(recommended < 0 || recommended > 1024*1024)
                    throw new InvalidOperationException("DocumentProperties returned size="+recommended);
                int bufferSize=Math.Max(actual,recommended);
                inMode=Marshal.AllocHGlobal(bufferSize);
                outMode=Marshal.AllocHGlobal(bufferSize);
                byte[] bytes = new byte[actual];
                Marshal.Copy(dm,bytes,0,actual);
                Marshal.Copy(bytes,0,inMode,actual);
                Marshal.WriteInt32(inMode,72,currentFields | DM_DEFAULTSOURCE);
                Marshal.WriteInt16(inMode,88,(short)value);

                int result=DocumentProperties(IntPtr.Zero,h,name,outMode,inMode,DM_IN_BUFFER|DM_OUT_BUFFER);
                if(result != 1) throw new InvalidOperationException("DocumentProperties validation failed (result="+result+").");
                AssertDevMode(outMode);
                int validated=(ushort)Marshal.ReadInt16(outMode,88);
                int validatedFields=Marshal.ReadInt32(outMode,72);
                if(validated != value || (validatedFields & DM_DEFAULTSOURCE) == 0)
                    throw new InvalidOperationException("Driver rejected paper source "+value+
                        ", returned "+validated+". No printer settings changed.");

                pInfo8=Marshal.AllocHGlobal(IntPtr.Size);
                Marshal.WriteIntPtr(pInfo8,outMode);
                if(!SetPrinter(h,8,pInfo8,0))
                    throw new Win32Exception(Marshal.GetLastWin32Error(),"SetPrinter Level 8 failed");

                // Read back the actual spooler global default, not just a managed copy.
                if(infoBuffer != IntPtr.Zero) {
                    Marshal.FreeHGlobal(infoBuffer);
                    infoBuffer=IntPtr.Zero;
                }
                IntPtr actualDm=GetGlobalModePtr(h,out infoBuffer);
                int saved=(ushort)Marshal.ReadInt16(actualDm,88);
                int savedFlags=Marshal.ReadInt32(actualDm,72);
                if(saved != value || (savedFlags & DM_DEFAULTSOURCE) == 0)
                    throw new InvalidOperationException("SAVE_VERIFICATION_FAILED: expected "+value+", found "+saved+".");
                return "SET_AND_VERIFIED";
            } finally {
                if(pInfo8 != IntPtr.Zero) Marshal.FreeHGlobal(pInfo8);
                if(outMode != IntPtr.Zero) Marshal.FreeHGlobal(outMode);
                if(inMode != IntPtr.Zero) Marshal.FreeHGlobal(inMode);
                if(infoBuffer != IntPtr.Zero) Marshal.FreeHGlobal(infoBuffer);
                ClosePrinter(h);
            }
        }
    }
}
'@
    Add-Type -TypeDefinition $native -ErrorAction Stop
}

$before = [BewustICT.PrinterTrayNative]::ReadGlobalSource($PrinterNaam)
Write-Host ("TRAY_BEFORE_GLOBAL_RAWKIND={0}" -f $before)
if ($Actie -eq 'Controleren') {
    if ($before -ne [int]$target.RawKind) {
        throw "TRAY_READONLY_MISMATCH: $PrinterNaam current=$before expected=$($target.RawKind)."
    }
    Write-Host "TRAY_READONLY_OK: $PrinterNaam; desired=$($target.RawKind); current=$before"
    exit 0
}
$colorBefore = Get-PrintConfiguration -PrinterName $PrinterNaam -ErrorAction Stop
$result = [BewustICT.PrinterTrayNative]::WriteGlobalSource($PrinterNaam,[int]$target.RawKind)
$after = [BewustICT.PrinterTrayNative]::ReadGlobalSource($PrinterNaam)
$colorAfter = Get-PrintConfiguration -PrinterName $PrinterNaam -ErrorAction Stop
if ([bool]$colorBefore.Color -ne [bool]$colorAfter.Color -or
    [string]$colorBefore.DuplexingMode -ne [string]$colorAfter.DuplexingMode -or
    [string]$colorBefore.PaperSize -ne [string]$colorAfter.PaperSize) {
    throw "PRINT_SETTINGS_CHANGED_UNEXPECTEDLY: kleur/duplex/papierformaat verschilden na ladewijziging."
}
if ($after -ne [int]$target.RawKind) {
    throw "TRAY_VERIFY_FAILED: driver/Windows meldt $after, verwacht $($target.RawKind)."
}
Write-Host ("TRAY_SET_OK: Printer='{0}' Lade='{1}' RawKind={2} Status={3}" -f
    $PrinterNaam,$target.SourceName,$after,$result)
