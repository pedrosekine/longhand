# A Windows shortcut for Longhand, written or read (windows/shortcuts.py).
#
# Written through Windows' own shell object. Then, with -AppId, given the
# name the running Longhand gives itself to Windows (System.AppUserModel.ID),
# which is what lets the taskbar know Longhand's window for this shortcut's:
# the shell object cannot set it, so it is set through the shortcut's
# property store. If that part fails the shortcut stands, and a line
# starting "appid:" says why.
#
# -Read prints what a shortcut holds, as JSON.
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Target = "",
    [string]$Arguments = "",
    [string]$Icon = "",
    [string]$Description = "",
    [string]$WorkDir = "",
    [string]$AppId = "",
    [switch]$Read
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$shell = New-Object -ComObject WScript.Shell

if ($Read) {
    $link = $shell.CreateShortcut($Path)
    $folder = (New-Object -ComObject Shell.Application).Namespace((Split-Path $Path))
    $item = $folder.ParseName((Split-Path $Path -Leaf))
    $id = if ($item) { [string]$item.ExtendedProperty("System.AppUserModel.ID") } else { "" }
    @{ target = $link.TargetPath; arguments = $link.Arguments; icon = $link.IconLocation
       description = $link.Description; workdir = $link.WorkingDirectory; appid = $id } | ConvertTo-Json -Compress
    exit 0
}

$link = $shell.CreateShortcut($Path)
$link.TargetPath = $Target
$link.Arguments = $Arguments
if ($Icon) { $link.IconLocation = "$Icon,0" }
$link.Description = $Description
if ($WorkDir) { $link.WorkingDirectory = $WorkDir }
$link.Save()

if ($AppId) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class LonghandShortcut
{
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink { }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    private interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct PropertyKey { public Guid Format; public uint Id; }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    private struct PropVariant { [FieldOffset(0)] public ushort Type; [FieldOffset(8)] public IntPtr Pointer; }

    public static void SetAppId(string shortcut, string id)
    {
        object link = new ShellLink();
        IntPtr text = Marshal.StringToCoTaskMemUni(id);
        try
        {
            ((IPersistFile)link).Load(shortcut, 2);                     // STGM_READWRITE
            PropertyKey key = new PropertyKey { Format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), Id = 5 };
            PropVariant value = new PropVariant { Type = 31, Pointer = text };   // VT_LPWSTR
            IPropertyStore store = (IPropertyStore)link;
            Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref value));
            Marshal.ThrowExceptionForHR(store.Commit());
            ((IPersistFile)link).Save(shortcut, true);
        }
        finally
        {
            Marshal.FreeCoTaskMem(text);
            Marshal.ReleaseComObject(link);
        }
    }
}
'@
        [LonghandShortcut]::SetAppId($Path, $AppId)
    }
    catch {
        "appid: $($_.Exception.Message)"
    }
}
exit 0
