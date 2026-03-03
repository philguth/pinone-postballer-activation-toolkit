<#
.SYNOPSIS
  Stage 2 - PinOne Device Detection (Windows-level)

.DESCRIPTION
  Detects the CSD PinOne controller as a USB/HID device using PnP inventory.
  Validates presence and "OK" status. Outputs a structured result object for activate.ps1.

  Matching strategy (best-first):
  1) VID/PID if provided in profile.controller.vid / profile.controller.pid
  2) Name patterns from profile.controller.namePatterns (array) or defaults

  Returns: @{ status="PASS|WARN|FAIL"; notes=@(); data=@{} }

.PARAMETER Profile
  Cabinet profile object from activate.ps1

.PARAMETER ReportFolder
  Folder where reports/artifacts can be written

.EXAMPLE
  .\scripts\validate-pinone.ps1 -Profile $profile -ReportFolder .\reports
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  $Profile,

  [Parameter(Mandatory = $true)]
  [string] $ReportFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Add-Note([System.Collections.Generic.List[string]]$notes, [string]$msg) {
  $notes.Add($msg) | Out-Null
}

function Ensure-Folder([string]$path) {
  if (-not (Test-Path $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

function Normalize-Hex4([string]$s) {
  if (-not $s) { return $null }
  $t = $s.Trim()
  $t = $t -replace "^0x",""
  $t = $t -replace "^VID_",""
  $t = $t -replace "^PID_",""
  $t = $t.ToUpper()
  if ($t.Length -gt 4) { $t = $t.Substring($t.Length-4, 4) }
  return $t.PadLeft(4,'0')
}

function Get-PnpSnapshot {
  # Pull a broad snapshot; filters will be applied after
  # Requires admin sometimes for certain classes; still usually works as normal user.
  $devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
  if (-not $devices) { return @() }
  return $devices
}

function Match-ByVidPid($devices, [string]$vid, [string]$pid) {
  if (-not $vid -or -not $pid) { return @() }

  $vidN = Normalize-Hex4 $vid
  $pidN = Normalize-Hex4 $pid

  $matched = @()
  foreach ($d in $devices) {
    $id = [string]$d.InstanceId
    if ($id -match ("VID_" + $vidN) -and $id -match ("PID_" + $pidN)) {
      $matched += $d
    }
  }
  return $matched
}

function Match-ByNamePatterns($devices, [string[]]$patterns) {
  if (-not $patterns -or $patterns.Count -eq 0) { return @() }

  $matched = @()
  foreach ($d in $devices) {
    $name = [string]$d.FriendlyName
    $desc = [string]$d.Description
    $cls  = [string]$d.Class

    foreach ($p in $patterns) {
      if (-not $p) { continue }
      if ($name -match $p -or $desc -match $p) {
        $matched += $d
        break
      }
    }
  }
  return $matched
}

function Summarize-Device($d) {
  return [ordered]@{
    friendlyName = [string]$d.FriendlyName
    description  = [string]$d.Description
    class        = [string]$d.Class
    status       = [string]$d.Status
    instanceId   = [string]$d.InstanceId
    manufacturer = [string]$d.Manufacturer
  }
}

# ----------------------------
# Begin Stage
# ----------------------------
$notes = New-Object System.Collections.Generic.List[string]
$data  = @{}
$status = "PASS"

Write-Host "Stage 2 - PinOne Device Detection"

# Pull matching hints from profile if present
$vid = $null
$pid = $null
$namePatterns = $null

if ($Profile.controller) {
  if ($Profile.controller.PSObject.Properties.Name -contains "vid") { $vid = [string]$Profile.controller.vid }
  if ($Profile.controller.PSObject.Properties.Name -contains "pid") { $pid = [string]$Profile.controller.pid }
  if ($Profile.controller.PSObject.Properties.Name -contains "namePatterns") { $namePatterns = @($Profile.controller.namePatterns) }
}

# Default patterns (works for most users even without VID/PID)
if (-not $namePatterns -or $namePatterns.Count -eq 0) {
  $namePatterns = @(
    "PinOne",
    "CSD",
    "Cleveland Software Design",
    "Pins?cape",   # harmless fallback if people reuse scripts
    "HID"          # last-resort catch; we won’t rely on this alone for PASS
  )
}

$data.matchHints = @{
  vid = $vid
  pid = $pid
  namePatterns = $namePatterns
}

$devices = Get-PnpSnapshot
if (-not $devices -or $devices.Count -eq 0) {
  Add-Note $notes "FAIL: Unable to enumerate PnP devices (Get-PnpDevice returned nothing)."
  $status = "FAIL"
} else {
  # Prefer matching by VID/PID if available
  $matched = @()
  $matchMethod = $null

  if ($vid -and $pid) {
    $matched = Match-ByVidPid -devices $devices -vid $vid -pid $pid
    $matchMethod = "VIDPID"
    Add-Note $notes "INFO: Matching by VID/PID: VID_$(Normalize-Hex4 $vid) PID_$(Normalize-Hex4 $pid)"
  }

  # Fallback: name patterns
  if (-not $matched -or $matched.Count -eq 0) {
    $matched = Match-ByNamePatterns -devices $devices -patterns $namePatterns
    $matchMethod = "NAMEPATTERN"
    Add-Note $notes "INFO: Matching by name patterns."
  }

  # If we only matched because of very broad 'HID', treat as WARN, not PASS
  $broadOnly = $false
  if ($matchMethod -eq "NAMEPATTERN") {
    $nonBroad = @("PinOne","CSD","Cleveland Software Design")
    $anyStrong = $false
    foreach ($d in $matched) {
      $n = [string]$d.FriendlyName
      $ds = [string]$d.Description
      foreach ($s in $nonBroad) {
        if ($n -match $s -or $ds -match $s) { $anyStrong = $true; break }
      }
      if ($anyStrong) { break }
    }
    if (-not $anyStrong) { $broadOnly = $true }
  }

  $data.matchMethod = $matchMethod
  $data.matchedCount = $matched.Count
  $data.matchedDevices = @($matched | ForEach-Object { Summarize-Device $_ })

  if (-not $matched -or $matched.Count -eq 0) {
    Add-Note $notes "FAIL: PinOne device not detected."
    Add-Note $notes "NEXT: Confirm USB cable, try a different port, and check Device Manager for unknown devices."
    $status = "FAIL"
  } else {
    # Evaluate health
    $ok = @($matched | Where-Object { $_.Status -eq "OK" })
    $notOk = @($matched | Where-Object { $_.Status -ne "OK" })

    if ($ok.Count -ge 1 -and -not $broadOnly) {
      Add-Note $notes "PASS: Detected PinOne-related device(s) with Status=OK: $($ok.Count)"
      Add-Note $notes "NEXT: Verify buttons/plunger axis in Windows: run 'joy.cpl' and test inputs."
      $status = "PASS"
    } elseif ($ok.Count -ge 1 -and $broadOnly) {
      Add-Note $notes "WARN: Detected HID device(s) but match confidence is low (no strong PinOne/CSD name match)."
      Add-Note $notes "NEXT: Provide VID/PID in the profile for precise detection once known."
      Add-Note $notes "NEXT: Run 'joy.cpl' to confirm the correct controller is present and inputs respond."
      $status = "WARN"
    } else {
      Add-Note $notes "FAIL: Device matched, but none have Status=OK."
      foreach ($d in $notOk) {
        Add-Note $notes ("DETAIL: {0} | Status={1} | InstanceId={2}" -f $d.FriendlyName, $d.Status, $d.InstanceId)
      }
      Add-Note $notes "NEXT: In Device Manager, open the device properties and resolve driver/power issues."
      $status = "FAIL"
    }
  }
}

# Write stage artifact
try {
  Ensure-Folder $ReportFolder
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $artifactPath = Join-Path $ReportFolder "stage-S2-pinone-$stamp.json"
  (@{ stage="S2"; status=$status; notes=$notes; data=$data } | ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 $artifactPath
  Add-Note $notes "INFO: Wrote stage artifact: $artifactPath"
} catch {
  Add-Note $notes "WARN: Could not write stage artifact: $($_.Exception.Message)"
}

return @{
  status = $status
  notes  = $notes
  data   = $data
}