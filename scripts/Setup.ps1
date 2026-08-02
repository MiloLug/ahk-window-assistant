<#
.SYNOPSIS
    Deploys the window manager and registers a task for auto running it.
.DESCRIPTION
    See docs\elevation.md.
    This script reads the destination from the repo's config
    ([setup] path), mirrors the required parts there, and locks the tree down
    so the non-admin account cannot write to it (this would be very dangerous, this will run as SYSTEM),
    and registers it all as a SYSTEM logon task.

    The deployed tree runs as SYSTEM: anything the normal account can write there is a
    system-compromise path, which is why the ACL is verified before the task is registered.
.EXAMPLE
    pwsh -File scripts\Setup.ps1 -Start
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.ini'),
    [string]$TaskName,
    [switch]$Start,
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false  # robocopy returns success with non-zero codes


# Reading the config
Import-Module (Join-Path $PSScriptRoot 'IniUtils.psm1') -Force
$config = LoadIni($ConfigPath)
if (-not $config.ContainsKey('setup') -or -not $config['setup'].ContainsKey('path') -or -not $config['common'].ContainsKey('ahkPath')) {
    throw "$ConfigPath has not enough info. Copy config.example.ini to config.ini and set the deploy destination and all required variables."
}


# We need to make sure the script is elevated
function Test-Admin {
    $user = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $user.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if (-not (Test-Admin)) {
    if ($Elevated) { throw 'Still not running as admin after elevating. Run this from an admin account.' }
    $relaunch = @('-NoExit', '-NoProfile', '-File', "`"$PSCommandPath`"", '-Elevated', '-ConfigPath', "`"$ConfigPath`"")
    if ($TaskName) { $relaunch += @('-TaskName', "`"$TaskName`"") }
    if ($Start) { $relaunch += '-Start' }
    Start-Process pwsh -Verb RunAs -ArgumentList $relaunch
    exit
}


# Some general constants

$RepoRoot = Split-Path $PSScriptRoot -Parent
$AhkExe = $config['common']['ahkPath']
$DllName = 'VirtualDesktopAccessor.dll'
$AdminSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')  # SYSTEM, Administrators, TrustedInstaller
$WriteMask = [System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteAttributes, WriteExtendedAttributes, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
$DeployDacl = 'D:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)'

function Get-DeployPath {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Raw)

    $p = $Raw.Trim().Trim('"')
    if (-not $p) { throw '[setup] path is empty in the config.' }

    # I don't want any accidents with relative paths
    if ($p -notmatch '^[A-Za-z]:\\') { throw "Deploy path must be absolute on a local drive (e.g. C:\Program Files\...): $p" }
    return [System.IO.Path]::GetFullPath($p).TrimEnd('\')  # robocopy: a trailing backslash escapes the closing quote
}

function Test-PathInside {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Container)

    $a = $Path.TrimEnd('\') + '\'
    $b = $Container.TrimEnd('\') + '\'
    return $a.StartsWith($b, [StringComparison]::OrdinalIgnoreCase)
}

function Get-NonAdminWriteRules {
    param([Parameter(Mandatory)]$Acl)

    return $Acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        ($_.FileSystemRights -band $WriteMask) -and
        (Get-SidOf $_.IdentityReference) -notin $AdminSids
    }
}

function Get-SidOf {
    param([Parameter(Mandatory)]$Identity)

    try { return $Identity.Translate([System.Security.Principal.SecurityIdentifier]).Value }
    catch { return $Identity.Value }
}

function Assert-Preflight {
    param([Parameter(Mandatory)][string]$Dest)

    $drive = [System.IO.Path]::GetPathRoot($Dest)
    if (-not (Test-Path -LiteralPath $drive)) { throw "Drive $drive does not exist (deploy path: $Dest)." }

    if ((Test-PathInside $Dest $RepoRoot) -or (Test-PathInside $RepoRoot $Dest)) {
        throw "Deploy path overlaps the repo ($RepoRoot). Choose another destination."
    }

    # Better be safe...
    # Also, the script should have full access to the directory
    $reserved = @($drive, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    if ($Dest.TrimEnd('\') -in $reserved) {
        throw "Refusing to deploy to $Dest - it is a system directory. Use a dedicated subdirectory under it."
    }
    if ((Test-Path -LiteralPath $Dest) -and
        -not (Test-Path -LiteralPath (Join-Path $Dest 'scripts\Launcher.ahk')) -and
        (Get-ChildItem -LiteralPath $Dest -Force | Select-Object -First 1)) {
        throw "$Dest already exists and it's not a previous deployment. Delete it or pick another [setup] path."
    }

    foreach ($f in @("$RepoRoot\src\Main.ahk", "$PSScriptRoot\Launcher.ahk", "$PSScriptRoot\Task.xml")) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Missing required file: $f" }
    }
    if (-not (Test-Path -LiteralPath "$RepoRoot\$DllName" -PathType Leaf)) {
        throw "Missing $RepoRoot\$DllName. It is gitignored - download it from https://github.com/Ciantic/VirtualDesktopAccessor and put it in the repo root."
    }
    if (-not (Test-Path -LiteralPath $AhkExe -PathType Leaf)) {
        throw "AutoHotkey v2 not found at $AhkExe. The launcher and the task both need this."
    }

    $parent = Split-Path $Dest -Parent
    if (Test-Path -LiteralPath $parent) {
        $policy = Get-NonAdminWriteRules (Get-Acl -LiteralPath $parent)
        if ($policy) {
            # Write access to the parent means the deploy dir can be deleted and recreated with
            # hostile content, regardless of its own ACL.
            Write-Warning "$policy is writable by non-admin principals: $(($policy.IdentityReference | Select-Object -Unique) -join ', ')"
            Write-Warning "Pick a deploy path under an admin-only parent (e.g. C:\Program Files\...) or lock $parent down first."
        }
    }
}

function Stop-DeployedInstance {
    param([Parameter(Mandatory)][string]$Dest, [Parameter(Mandatory)][string]$Task)

    $existing = Get-ScheduledTask -TaskName $Task -TaskPath '\' -ErrorAction SilentlyContinue
    if ($existing -and $existing.State -eq 'Running') {
        Write-Host "Stopping task $Task"
        Stop-ScheduledTask -TaskName $Task -TaskPath '\'
    }

    foreach ($p in Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'") {
        if (-not $p.CommandLine) { continue }
        if ($p.CommandLine.IndexOf($Dest, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Host "Killing deployed instance PID $($p.ProcessId)"
            & taskkill.exe /F /T /PID $p.ProcessId | Out-Null  # unlike Stop-Process, taskkill enables SeDebugPrivilege
        } elseif ($p.CommandLine -match 'Main\.ahk') {
            Write-Warning "Another instance is running from a different tree (PID $($p.ProcessId)): $($p.CommandLine)"
            Write-Warning "Review and kill it if it's another instance of this repo."
        }
    }

    # The DLL stays locked for a moment after the process dies, so we must dispose it
    $dll = Join-Path $Dest $DllName
    $deadline = [datetime]::UtcNow.AddSeconds(10)
    while ((Test-Path -LiteralPath $dll) -and [datetime]::UtcNow -lt $deadline) {
        try { [System.IO.File]::Open($dll, 'Open', 'ReadWrite', 'None').Dispose(); break }
        catch { Start-Sleep -Milliseconds 250 }
    }
}

function Copy-DeployTree {
    param([Parameter(Mandatory)][string]$Dest)

    New-Item -ItemType Directory -Path $Dest -Force | Out-Null

    # /MIR purges files deleted from the repo
    & robocopy.exe "$RepoRoot\src" "$Dest\src" /MIR /XJ /NFL /NDL /NJH /NJS /NP /R:2 /W:2 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
    $global:LASTEXITCODE = 0

    Copy-Item -LiteralPath "$RepoRoot\$DllName" -Destination $Dest -Force

    # Launcher must stay under scripts\ to work with the includes from src\Lib\
    New-Item -ItemType Directory -Path "$Dest\scripts" -Force | Out-Null
    Copy-Item -LiteralPath "$PSScriptRoot\Launcher.ahk" -Destination "$Dest\scripts\Launcher.ahk" -Force
    Copy-Item -LiteralPath $ConfigPath -Destination "$Dest\config.ini" -Force
}

function Set-DeployAcl {
    param([Parameter(Mandatory)][string]$Dest)

    # /reset will make the children inherit ACLs
    & icacls.exe $Dest /reset /T /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls /reset failed with exit code $LASTEXITCODE" }

    $acl = Get-Acl -LiteralPath $Dest
    $acl.SetSecurityDescriptorSddlForm($DeployDacl)
    Set-Acl -LiteralPath $Dest -AclObject $acl

    # Make sure the owner is admin - since he'll always have WRITE_DAC and could even re-grant itself
    & icacls.exe $Dest /setowner '*S-1-5-32-544' /T /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls /setowner failed with exit code $LASTEXITCODE" }
}

function Assert-DeployAcl {
    param([Parameter(Mandatory)][string]$Dest)

    # Children are on the inheritance, so we can just check the root
    $acl = Get-Acl -LiteralPath $Dest
    if (-not $acl.AreAccessRulesProtected) { throw "$Dest inherits permissions from its parent." }
    if ((Get-SidOf $acl.GetOwner([System.Security.Principal.NTAccount])) -notin $AdminSids) {
        throw "$Dest is owned by $($acl.Owner), not Administrators."
    }
    $dacl = $acl.Sddl -replace '^.*?(?=D:)', ''
    if ($dacl -ne $DeployDacl) {
        throw "$Dest has an unexpected DACL: $dacl (wanted $DeployDacl). This may be a privilege-escalation path."
    }

    Write-Host "ACL verified: $Dest is admin-only."
}

function Register-DeployTask {
    param([Parameter(Mandatory)][string]$Dest, [Parameter(Mandatory)][string]$Task)

    $xml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Task.xml') -Raw
    $values = @{
        '{{AHK_EXE}}'  = $AhkExe
        '{{LAUNCHER}}' = (Join-Path $Dest 'scripts\Launcher.ahk')
        '{{DEST}}'     = $Dest
    }
    foreach ($kv in $values.GetEnumerator()) {
        $xml = $xml.Replace($kv.Key, [System.Security.SecurityElement]::Escape($kv.Value))
    }
    Register-ScheduledTask -TaskName $Task -TaskPath '\' -Xml $xml -Force | Out-Null
}

# and here it all happens:

$dest = Get-DeployPath $config['setup']['path']
if (-not $TaskName) { $TaskName = Split-Path $dest -Leaf }

Write-Host "Deploying $RepoRoot -> $dest (task: $TaskName)"
Assert-Preflight $dest
Stop-DeployedInstance $dest $TaskName
Copy-DeployTree $dest
Set-DeployAcl $dest
Assert-DeployAcl $dest
Register-DeployTask $dest $TaskName

if ($Start) {
    Start-ScheduledTask -TaskName $TaskName -TaskPath '\'
    Write-Host 'Task started.'
} else {
    Write-Host "Done. Start it now with: Start-ScheduledTask -TaskName '$TaskName'  (or just log off and back on)"
}
Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath '\' | Select-Object TaskName, LastRunTime, LastTaskResult

#endregion
