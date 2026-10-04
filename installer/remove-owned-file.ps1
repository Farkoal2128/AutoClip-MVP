# Internal primitive: caller must authorize Root from the complete receipt.
# Bounded candidate for the user-approved stopped-app cleanup scope.
# Actual generated-uninstaller qualification remains pending.
# No receipt authority, directory cleanup, or generated-uninstaller integration.
if(-not ('AutoClip.OwnedFileRemoval' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Security.Cryptography;
using Microsoft.Win32.SafeHandles;
namespace AutoClip {
public static class OwnedFileRemoval {
    [StructLayout(LayoutKind.Sequential)] struct Info {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle handle,out Info info);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int kind,IntPtr buffer,uint size);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool SetFileInformationByHandle(SafeFileHandle handle,int kind,ref byte disposition,uint size);
    [DllImport("advapi32.dll")]
    static extern uint GetSecurityInfo(SafeFileHandle handle,int kind,uint fields,out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr descriptor);
    [DllImport("advapi32.dll")]
    static extern uint GetSecurityDescriptorLength(IntPtr descriptor);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool GetTokenInformation(IntPtr token,int kind,out int value,int length,out int returned);
    static SafeFileHandle Open(string path,bool directory) {
        // Directory sharing omits WRITE and DELETE, pinning name and reparse state.
        // File sharing omits WRITE and DELETE until after disposition and close.
        var handle=CreateFileW(path,directory ? 0x80020000U : 0x80030000U,1,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
        if(handle.IsInvalid){int error=Marshal.GetLastWin32Error();handle.Dispose();throw new Win32Exception(error);}
        return handle;
    }
    static void Check(SafeFileHandle handle,bool directory,bool checkAcl,bool protectedRoot,string sid) {
        Info info;
        if(!GetFileInformationByHandle(handle,out info))throw new Win32Exception(Marshal.GetLastWin32Error());
        if((info.Attributes & 0x400)!=0 || ((info.Attributes & 0x10)!=0)!=directory || (!directory && ((info.Attributes & 1)!=0 || info.Links!=1)))throw new InvalidDataException("Unsafe file type, reparse point, read-only file or multiple hard links.");
        if(!checkAcl)return;
        IntPtr owner,group,dacl,sacl,descriptor;
        uint error=GetSecurityInfo(handle,1,5,out owner,out group,out dacl,out sacl,out descriptor);
        if(error!=0)throw new Win32Exception((int)error);
        try {
            byte[] bytes=new byte[GetSecurityDescriptorLength(descriptor)];Marshal.Copy(descriptor,bytes,0,bytes.Length);
            var security=new RawSecurityDescriptor(bytes,0);
            if(security.Owner==null || !Trusted(security.Owner.Value,sid) || security.DiscretionaryAcl==null || security.DiscretionaryAcl.Count==0 || (protectedRoot && (security.ControlFlags & ControlFlags.DiscretionaryAclProtected)==0))throw new InvalidDataException("Unsafe owner or DACL.");
            const int writes=278|64|65536|262144|524288|268435456|1073741824;
            foreach(GenericAce ace in security.DiscretionaryAcl) {
                var qualified=ace as QualifiedAce;
                // Fail closed for callback/object/unknown ACEs rather than guess rights.
                if(!(ace is CommonAce) || qualified.IsCallback)throw new InvalidDataException("Unsupported DACL ACE.");
                if(qualified.AceQualifier==AceQualifier.AccessAllowed && !Trusted(qualified.SecurityIdentifier.Value,sid) && (qualified.AccessMask & writes)!=0)throw new InvalidDataException("Foreign write grant.");
            }
        } finally {LocalFree(descriptor);}
    }
    static bool Trusted(string owner,string sid){return owner==sid || owner=="S-1-5-18" || owner=="S-1-5-32-544";}
    static bool DefaultStreamOnly(SafeFileHandle handle,long length) {
        // Bounded, fail-closed inventory: exactly one unnamed data stream.
        // No retry or path enumeration on unsupported/oversized responses.
        const int capacity=65536;
        IntPtr buffer=Marshal.AllocHGlobal(capacity);
        try {
            // Also reject successful no-stream responses without reading old heap data.
            Marshal.Copy(new byte[40],0,buffer,40);
            if(!GetFileInformationByHandleEx(handle,7,buffer,capacity))return false;
            return Marshal.ReadInt32(buffer,0)==0 && Marshal.ReadInt32(buffer,4)==14
                && Marshal.ReadInt64(buffer,8)==length
                && Marshal.PtrToStringUni(IntPtr.Add(buffer,24),7)=="::$DATA";
        } finally {Marshal.FreeHGlobal(buffer);}
    }
    public static string Remove(string root,string relative,long bytes,string sha) {
        return Remove(root,relative,bytes,sha,true);
    }
    public static string Remove(string root,string relative,long bytes,string sha,bool requireProtectedRoot) {
        var ancestors=new List<SafeFileHandle>();
        try {
            using(var identity=WindowsIdentity.GetCurrent()) {
                int elevated,returned;
                if(!GetTokenInformation(identity.Token,20,out elevated,4,out returned))throw new Win32Exception(Marshal.GetLastWin32Error());
                if(elevated!=0)return "UNSAFE";
                if(new DriveInfo(Path.GetPathRoot(root)).DriveType!=DriveType.Fixed)return "UNSAFE";
                string sid=identity.User.Value;
                string path=Path.Combine(root,relative.Replace('/', '\\'));
                string parent=Path.GetDirectoryName(path),cursor=Path.GetPathRoot(path);
                var chain=new List<string>();chain.Add(cursor);
                foreach(string part in parent.Substring(cursor.Length).Split('\\')){cursor=Path.Combine(cursor,part);chain.Add(cursor);}
                foreach(string directory in chain) {
                    var handle=Open(directory,true);ancestors.Add(handle);
                    bool within=directory.Equals(root,StringComparison.OrdinalIgnoreCase) || directory.StartsWith(root+"\\",StringComparison.OrdinalIgnoreCase);
                    Check(handle,true,within,requireProtectedRoot && directory.Equals(root,StringComparison.OrdinalIgnoreCase),sid);
                }
                using(var file=Open(path,false)) {
                    Check(file,false,true,false,sid);
                    // FileStream uses the very same SafeFileHandle opened with DELETE.
                    using(var stream=new FileStream(file,FileAccess.Read)) {
                        if(!DefaultStreamOnly(file,stream.Length))return "UNSAFE";
                        if(stream.Length!=bytes)return "CHANGED";
                        using(var hash=SHA256.Create()) {
                            string actual=BitConverter.ToString(hash.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
                            if(actual!=sha)return "CHANGED";
                        }
                        // ponytail: stream snapshots require AutoClip/updater stopped;
                        // unrelated concurrent writers need a stronger future primitive.
                        if(!DefaultStreamOnly(file,stream.Length))return "UNSAFE";
                        byte disposition=1;
                        if(!SetFileInformationByHandle(file,4,ref disposition,1))throw new Win32Exception(Marshal.GetLastWin32Error());
                    }
                }
                return "REMOVED";
            }
        } catch(Win32Exception error) {
            if(error.NativeErrorCode==2 || error.NativeErrorCode==3)return "MISSING";
            if(error.NativeErrorCode==32 || error.NativeErrorCode==33)return "LOCKED";
            return "UNSAFE";
        } catch(InvalidDataException) {return "UNSAFE";}
          catch(UnauthorizedAccessException) {return "UNSAFE";}
          catch(IOException) {return "UNSAFE";}
        finally {for(int i=ancestors.Count-1;i>=0;i--)ancestors[i].Dispose();}
    }
}
}
'@
}
function Remove-SetupOwnedFile {
    param($Root,$Row,[switch]$AllowInheritedRoot)
    $ErrorActionPreference='Stop'
    # Same lexical restrictions as Get-SetupRelativePath; no mutable script import.
    $status='INVALID'
    $names=if($Row -is [Collections.IDictionary]){@($Row.Keys)}elseif($null -ne $Row){@($Row.PSObject.Properties.Name)}else{@()}
    $valid=$Root -is [string] -and $Root -match '^[A-Za-z]:[\\/]' -and $Root.Substring(3) -notmatch '[:*?"<>|\x00-\x1f]' -and $Root.Length -gt 3
    if($valid){$valid=!@($Root.Substring(3).Split([char[]]'\/')|Where-Object{!$_ -or $_ -in @('.','..') -or $_.EndsWith('.') -or $_.EndsWith(' ') -or $_ -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'}).Count}
    if($valid){$valid=$names.Count -eq 3 -and !@($names|Where-Object{$_ -notin @('path','bytes','sha256')}).Count -and $Row.path -is [string] -and $Row.sha256 -is [string] -and $Row.sha256 -cmatch '^[a-f0-9]{64}$' -and ($Row.bytes -is [int] -or $Row.bytes -is [long]) -and $Row.bytes -ge 0}
    if($valid){$valid=$Row.path -and $Row.path -notmatch '[\\:*?"<>|\x00-\x1f]' -and !$Row.path.StartsWith('/') -and !@($Row.path.Split('/')|Where-Object{!$_ -or $_ -in @('.','..') -or $_.EndsWith('.') -or $_.EndsWith(' ') -or $_ -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'}).Count}
    if($valid){$status=[AutoClip.OwnedFileRemoval]::Remove([IO.Path]::GetFullPath($Root),$Row.path,$Row.bytes,$Row.sha256,!$AllowInheritedRoot)}
    [pscustomobject]@{status=$status}
}
