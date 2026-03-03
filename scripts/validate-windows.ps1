<#
.SYNOPSIS
  Stage 1 - Windows Hardening Validator

.DESCRIPTION
  Validates Windows settings that commonly break vpin stability:
  - Power plan (High performance / Ultimate performance)
  - USB selective suspend
  - Sleep / Hibernate timeouts
  - Fast Startup
  - (Optional) basic USB power management hints

  Returns: @{ status="PASS|WARN|FAIL"; notes=@(); data=@{} }

.PARAMETER Profile
  Cabinet profile object from activate.ps1

.PARAMETER ReportFolder
  Folder where reports/artifacts can be written

.PARAMETER ApplyFixes
  If specified, will apply non-destructive fixes where possible:
  - Set High performance (if available)
  - Disable USB selective suspend (DC/AC)
  - Disable sleep timeouts (DC/AC)
  - Disable hibernate
  - Disable Fast Startup

.EXAMPLE
  .\scripts\validate-windows.ps1 -Profile $profile -ReportFolder .\reports

.EXAMPLE
  .\scripts\validate-windows.ps1 -Profile $profile -ReportFolder .\reports -ApplyFixes
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  $Profile,
  

  [Parameter(Mandatory = $true)]
  [string] $ReportFolder,
  [string] $ExpectedCabinetUser = "Pinball",

  [switch] $ApplyFixes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Add-Note([System.Collections.Generic.List[string]]$notes, [string]$msg) {
  $notes.Add($msg) | Out-Null
}

function Test-LocalUserExists([string]$UserName) {
  try {
    Get-LocalUser -Name $UserName -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Ensure-CabinetUser([System.Collections.Generic.List[string]]$notes, [hashtable]$data) {
  $data.cabinetUser = @{ expected = $ExpectedCabinetUser }

  if (Test-LocalUserExists $ExpectedCabinetUser) {
    Add-Note $notes "PASS: Cabinet user exists: $ExpectedCabinetUser"
    return "PASS"
  }

  Add-Note $notes "FAIL: Cabinet user missing: $ExpectedCabinetUser (Settings → Accounts → Other users)"
  return "FAIL"
}

function Ensure-AutoLogon([System.Collections.Generic.List[string]]$notes, [hashtable]$data) {
  $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
  $auto = $null
  $user = $null
  $dom  = $null
  $pwd  = $null

  try { $auto = (Get-ItemProperty $path -Name "AutoAdminLogon" -ErrorAction Stop)."AutoAdminLogon" } catch { }
  try { $user = (Get-ItemProperty $path -Name "DefaultUserName" -ErrorAction Stop)."DefaultUserName" } catch { }
  try { $dom  = (Get-ItemProperty $path -Name "DefaultDomainName" -ErrorAction Stop)."DefaultDomainName" } catch { }
  try { $pwd  = (Get-ItemProperty $path -Name "DefaultPassword" -ErrorAction Stop)."DefaultPassword" } catch { }

  $data.autoLogon = @{
    regPath = $path
    AutoAdminLogon = $auto
    DefaultUserName = $user
    DefaultDomainName = $dom
    DefaultPasswordPresent = ($null -ne $pwd)
    expectedUser = $ExpectedCabinetUser
  }

  if ($auto -eq "1" -and $user) {
    if ($user -ieq $ExpectedCabinetUser) {
      Add-Note $notes "PASS: Auto-logon enabled for '$user'."
      if ($null -ne $pwd) {
        Add-Note $notes "WARN: DefaultPassword is stored in registry (acceptable for cabinet, not ideal)."
        return "WARN"
      }
      return "PASS"
    }

    Add-Note $notes "WARN: Auto-logon enabled for '$user' (expected '$ExpectedCabinetUser')."
    return "WARN"
  }

  Add-Note $notes "FAIL: Auto-logon not configured (AutoAdminLogon/DefaultUserName not set)."
  return "FAIL"
}

function Ensure-FrontEndAutostartHint([System.Collections.Generic.List[string]]$notes, [hashtable]$data) {
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  $startupDir = [Environment]::GetFolderPath("Startup")

  $runCount = 0
  try {
    $props = Get-ItemProperty -Path $runKey -ErrorAction Stop
    $runCount = ($props.PSObject.Properties | Where-Object { $_.Name -notin @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider") }).Count
  } catch { }

  $startupFiles = @()
  try {
    if (Test-Path $startupDir) {
      $startupFiles = @(Get-ChildItem -Path $startupDir -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
  } catch { $startupFiles = @() }

  $startupCount = @($startupFiles).Count

  $data.frontEndAutostart = @{
    hkcuRunEntryCount = $runCount
    startupFolder = $startupDir
    startupFolderItems = $startupFiles
  }

  if ($runCount -gt 0 -or $startupCount -gt 0) {
    Add-Note $notes "INFO: Autostart items found (HKCU Run: $runCount, Startup folder: $startupCount)."
    return "PASS"
  }

  Add-Note $notes "WARN: No obvious autostart entries found for current user ($env:USERNAME). Front-end may not auto-launch."
  return "WARN"
}

function Get-ActivePowerScheme {
  # Returns @{ Guid="..."; Name="..." } or $null
  $out = & powercfg /getactivescheme 2>$null
  if (-not $out) { return $null }

  # Example:
  # "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)"
  $m = [regex]::Match($out, "GUID:\s*([0-9a-fA-F\-]{36})\s*\((.+)\)")
  if (-not $m.Success) { return $null }

  return [pscustomobject]@{
    Guid = $m.Groups[1].Value.ToLower()
    Name = $m.Groups[2].Value.Trim()
  }
}

function Get-PowerSchemes {
  # Returns list of @{ Guid, Name }
  $out = & powercfg /list 2>$null
  if (-not $out) { return @() }

  $schemes = New-Object System.Collections.Generic.List[object]
  foreach ($line in $out -split "`r?`n") {
    # Example:
    # "Power Scheme GUID: 381b...  (Balanced) *"
    $m = [regex]::Match($line, "GUID:\s*([0-9a-fA-F\-]{36})\s*\((.+)\)")
    if ($m.Success) {
      $schemes.Add([pscustomobject]@{
        Guid = $m.Groups[1].Value.ToLower()
        Name = $m.Groups[2].Value.Trim()
        IsActive = ($line -match "\*")
      }) | Out-Null
    }
  }
  return $schemes
}

function Ensure-HighPerformance([System.Collections.Generic.List[string]]$notes, [hashtable]$data) {
  $schemes = Get-PowerSchemes
  $active  = $schemes | Where-Object { $_.IsActive } | Select-Object -First 1

  $data.powerSchemes = $schemes
  $data.activePowerScheme = $active

  if (-not $active) {
    Add-Note $notes "WARN: Unable to determine active power plan (powercfg)."
    return "WARN"
  }

  # Common GUIDs (built-in)
  $guidBalanced = "381b4222-f694-41f0-9685-ff5bb260df2e"
  $guidHighPerf = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
  # Ultimate performance is not present on all editions
  $guidUltimate = "e9a42b02-d5df-448d-aa00-03f14749eb61"

  $isGood =
    ($active.Guid -eq $guidHighPerf) -or
    ($active.Guid -eq $guidUltimate) -or
    ($active.Name -match "High performance") -or
    ($active.Name -match "Ultimate performance")

  if ($isGood) {
    Add-Note $notes "PASS: Power plan is '$($active.Name)'."
    return "PASS"
  }

  Add-Note $notes "FAIL: Power plan is '$($active.Name)'. Recommended: High performance (or Ultimate performance)."

  if ($ApplyFixes) {
    # Prefer Ultimate if present, else High performance
    $target = $schemes | Where-Object { $_.Guid -eq $guidUltimate } | Select-Object -First 1
    if (-not $target) {
      $target = $schemes | Where-Object { $_.Guid -eq $guidHighPerf } | Select-Object -First 1
    }

    if ($target) {
      & powercfg /setactive $target.Guid | Out-Null
      Add-Note $notes "FIXED: Set active power plan to '$($target.Name)'."
      return "WARN"
    } else {
      Add-Note $notes "WARN: High performance plan not found. You may need to enable it or import it."
      return "WARN"
    }
  }

  return "FAIL"
}

function Get-RegDword([string]$path, [string]$name) {
  try {
    $v = Get-ItemProperty -Path $path -Name $name -ErrorAction Stop
    return [int]$v.$name
  } catch {
    return $null
  }
}

function Set-RegDword([string]$path, [string]$name, [int]$value) {
  New-Item -Path $path -Force | Out-Null
  New-ItemProperty -Path $path -Name $name -PropertyType DWord -Value $value -Force | Out-Null
}

function Ensure-UsbSelectiveSuspend([System.Collections.Generic.List[string]]$notes, [hashtable]$data) {
  # Power setting GUIDs
  $subGroupUsb = "2a737441-1930-4402-8d77-b2bebba308a3"
  $settingUsbSuspend = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"

  # Query current values (AC/DC)
  $q = & powercfg /q 2>$null
  if (-not $q) {
    Add-Note $notes "WARN: Unable to query USB selective suspend (powercfg /q)."
    return "WARN"
  }

  # We’ll also enforce with SETACVALUEINDEX/SETDCVALUEINDEX if ApplyFixes
  # Desired: 0 (Disabled)
  $data.usbSelectiveSuspend = @{
    desired = 0
    subgroupGuid = $subGroupUsb
    settingGuid = $settingUsbSuspend
  }

  # We can't reliably parse /q output across locales; treat as WARN unless applying fixes.
  Add-Note $notes "INFO: USB selective suspend should be disabled (AC/DC)."

  if ($ApplyFixes) {
    try {
      & powercfg /SETACVALUEINDEX SCHEME_CURRENT $subGroupUsb $settingUsbSuspend 0 | Out-Null
      & powercfg /SETDCVALUEINDEX SCHEME_CURRENT $subGroupUsb $settingUsbSuspend 0 | Out-Null
      & powercfg /S SCHEME_CURRENT | Out-Null
      Add-Note $notes "FIXED: Disabled USB selective suspend (AC/DC) for active power scheme."
      return "WARN"
    } catch {
      Add-Note $notes "WARN: Could not set USB selective suspend automatically: $($_.Exception.Message)"
      return "WARN"
    }
  }

  # Without applying fixes, we flag as WARN because we aren't parsing /q output.
  return "WARN"
}

function Ensure-SleepTimeouts([System.Collections.Generic.List[string]]$notes, [hashtable]$data) {
  # Sleep setting GUIDs
  $subGroupSleep = "238c9fa8-0aad-41ed-83f4-97be242c8f20"
  $settingSleepTimeout = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"

  $data.sleepTimeout = @{
    desiredMinutes = 0
    subgroupGuid = $subGroupSleep
    settingGuid = $settingSleepTimeout
  }

  Add-Note $notes "INFO: Sleep timeout should be disabled (AC/DC)."

  if ($ApplyFixes) {
    try {
      & powercfg /SETACVALUEINDEX SCHEME_CURRENT $subGroupSleep $settingSleepTimeout 0 | Out-Null
      & powercfg /SETDCVALUEINDEX SCHEME_CURRENT $subGroupSleep $settingSleepTimeout 0 | Out-Null
      & powercfg /S SCHEME_CURRENT | Out-Null
      Add-Note $notes "FIXED: Disabled sleep timeout (AC/DC) for active power scheme."
      return "WARN"
    } catch {
      Add-Note $notes "WARN: Could not set sleep timeout automatically: $($_.Exception.Message)"
      return "WARN"
    }
  }

  return "WARN"
}

function Ensure-Hibernate([System.Collections.Generic.List[string]]$notes, [hashtable]$data) {
  # Capture powercfg output for diagnostics, but use hiberfil.sys presence as the primary signal.
  $out = & powercfg /a 2>$null
  if (-not $out) {
    Add-Note $notes "WARN: Unable to determine hibernate availability (powercfg /a)."
    return "WARN"
  }

  $hiberFile = Join-Path $env:SystemDrive "hiberfil.sys"
  $hiberPresent = $false
  try { $hiberPresent = (Test-Path $hiberFile) } catch { $hiberPresent = $false }

  $data.hibernate = @{
    availabilityRaw = $out
    shouldBeDisabled = $true
    hiberfilPath = $hiberFile
    hiberfilPresent = $hiberPresent
  }

  if (-not $hiberPresent) {
    Add-Note $notes "PASS: Hibernate appears disabled (hiberfil.sys not present)."
    return "PASS"
  }

  Add-Note $notes "WARN: hiberfil.sys present (hibernate likely enabled). Recommended: disable on cabinets."

  if ($ApplyFixes) {
    try {
      & powercfg /hibernate off | Out-Null
      $after = $false
      try { $after = (Test-Path $hiberFile) } catch { $after = $true }
      $data.hibernate.hiberfilPresentAfterFix = $after

      if (-not $after) {
        Add-Note $notes "FIXED: Disabled hibernate (powercfg /hibernate off)."
      } else {
        Add-Note $notes "WARN: Ran powercfg /hibernate off but hiberfil.sys is still present (reboot may be required)."
      }
      return "WARN"
    } catch {
      Add-Note $notes "WARN: Could not disable hibernate automatically: $($_.Exception.Message)"
      return "WARN"
    }
  }

  return "WARN"
}

function Ensure-FastStartup([System.Collections.Generic.List[string]]$notes, [hashtable]$data) {
  $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
  $name = "HiberbootEnabled"  # 1 = Fast Startup enabled, 0 = disabled

  $cur = Get-RegDword $regPath $name
  $data.fastStartup = @{
    regPath = $regPath
    name = $name
    current = $cur
    desired = 0
  }

  if ($null -eq $cur) {
    Add-Note $notes "WARN: Unable to read Fast Startup setting (registry)."
    return "WARN"
  }

  if ($cur -eq 0) {
    Add-Note $notes "PASS: Fast Startup is disabled."
    return "PASS"
  }

  Add-Note $notes "FAIL: Fast Startup is enabled. Recommended: disable it for stable USB/monitor behavior."

  if ($ApplyFixes) {
    try {
      Set-RegDword $regPath $name 0
      Add-Note $notes "FIXED: Disabled Fast Startup (HiberbootEnabled=0). Reboot required."
      return "WARN"
    } catch {
      Add-Note $notes "WARN: Could not disable Fast Startup automatically: $($_.Exception.Message)"
      return "WARN"
    }
  }

  return "FAIL"
}

# ----------------------------
# Run checks
# ----------------------------
$notes = New-Object System.Collections.Generic.List[string]
$data  = @{}
$status = "PASS"

Write-Host "Stage 1 - Windows Hardening"
Write-Host "ApplyFixes: $ApplyFixes"

# 0) Cabinet user exists
$cu = Ensure-CabinetUser -notes $notes -data $data
if ($cu -eq "FAIL") { $status = "FAIL" }
elseif ($cu -eq "WARN" -and $status -ne "FAIL") { $status = "WARN" }

# 0b) Auto-logon configured for cabinet user
$al = Ensure-AutoLogon -notes $notes -data $data
if ($al -eq "FAIL") { $status = "FAIL" }
elseif ($al -eq "WARN" -and $status -ne "FAIL") { $status = "WARN" }

# 1) Power plan
$p = Ensure-HighPerformance -notes $notes -data $data
if ($p -eq "FAIL") { $status = "FAIL" }
elseif ($p -eq "WARN" -and $status -ne "FAIL") { $status = "WARN" }

# 2) Fast Startup
$f = Ensure-FastStartup -notes $notes -data $data
if ($f -eq "FAIL") { $status = "FAIL" }
elseif ($f -eq "WARN" -and $status -ne "FAIL") { $status = "WARN" }

# 3) USB selective suspend (we treat as WARN unless we apply fixes)
$u = Ensure-UsbSelectiveSuspend -notes $notes -data $data
if ($u -eq "FAIL") { $status = "FAIL" }
elseif ($u -eq "WARN" -and $status -ne "FAIL") { $status = "WARN" }

# 4) Sleep timeouts (WARN unless apply fixes)
$s = Ensure-SleepTimeouts -notes $notes -data $data
if ($s -eq "FAIL") { $status = "FAIL" }
elseif ($s -eq "WARN" -and $status -ne "FAIL") { $status = "WARN" }

# 5) Hibernate (PASS/WARN)
$h = Ensure-Hibernate -notes $notes -data $data
if ($h -eq "FAIL") { $status = "FAIL" }
elseif ($h -eq "WARN" -and $status -ne "FAIL") { $status = "WARN" }

# 6) Front-end autostart hint (HKCU)
$fe = Ensure-FrontEndAutostartHint -notes $notes -data $data
if ($fe -eq "FAIL") { $status = "FAIL" }
elseif ($fe -eq "WARN" -and $status -ne "FAIL") { $status = "WARN" }

# Persist stage artifact (optional)
try {
  if (-not (Test-Path $ReportFolder)) { New-Item -ItemType Directory -Path $ReportFolder -Force | Out-Null }
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $artifactPath = Join-Path $ReportFolder "stage-S1-windows-$stamp.json"
  (@{ stage="S1"; status=$status; notes=$notes; data=$data } | ConvertTo-Json -Depth 8) | Set-Content -Encoding UTF8 $artifactPath
  Add-Note $notes "INFO: Wrote stage artifact: $artifactPath"
} catch {
  Add-Note $notes "WARN: Could not write stage artifact: $($_.Exception.Message)"
}

return @{
  status = $status
  notes  = $notes
  data   = $data
}