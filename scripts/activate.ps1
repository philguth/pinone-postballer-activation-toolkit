<#
.SYNOPSIS
  PinOne Post-Baller Activation Toolkit - Activation Wizard

.DESCRIPTION
  Loads a cabinet profile JSON and runs activation stages in order.
  Generates a health report (text + JSON) under .\reports\

.PARAMETER ProfilePath
  Path to the cabinet profile JSON.

.PARAMETER SchemaPath
  Optional JSON schema path. If provided, script will attempt basic schema checks.

.PARAMETER NonInteractive
  Run all stages in sequence without prompts (still logs results).

.PARAMETER Force
  Continue running stages even if a prior stage fails.

.EXAMPLE
  .\scripts\activate.ps1 -ProfilePath .\profiles\pinone-10solenoid-profile.json

.EXAMPLE
  .\scripts\activate.ps1 -ProfilePath .\profiles\pinone-10solenoid-profile.json -NonInteractive -Force
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string] $ProfilePath = ".\profiles\pinone-10solenoid-profile.json",

  [Parameter(Mandatory = $false)]
  [string] $SchemaPath = ".\profiles\schema\profile.schema.json",

  [switch] $NonInteractive,

  [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ----------------------------
# Helpers
# ----------------------------
function Write-Section([string]$title) {
  Write-Host ""
  Write-Host ("=" * 70)
  Write-Host $title
  Write-Host ("=" * 70)
}

function Ensure-Folder([string]$path) {
  if (-not (Test-Path $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

function Read-JsonFile([string]$path) {
  if (-not (Test-Path $path)) {
    throw "File not found: $path"
  }
  $raw = Get-Content -Path $path -Raw -Encoding UTF8
  try {
    return $raw | ConvertFrom-Json
  } catch {
    $err = $_.Exception.Message
    $hint = ""
    if ($err -match "Bad Unicode escape|Bad JSON escape") {
      $hint = " Hint: If this JSON contains Windows paths (e.g., c:\\users\\... or C:\\Program Files\\...), you must escape backslashes (\\\\) or use forward slashes (C:/Users/... )."
    }
    $context = ""
    if ($err -match "position\s+(\d+)") {
      try {
        $pos = [int]$Matches[1]
        if ($pos -ge 0 -and $pos -lt $raw.Length) {
          $start = [Math]::Max(0, $pos - 40)
          $len = [Math]::Min($raw.Length - $start, 80)
          $snippet = $raw.Substring($start, $len) -replace "\r?\n", " "
          $context = " Context near position $pos: '...$snippet...'"
        }
      } catch { }
    }
    throw "Invalid JSON in file: $path. Error: $err$hint$context"
  }
}

function Test-ProfileBasics($profile) {
  # Minimal checks (schema validation can be added later)
  $requiredTop = @("profileName", "version", "controller", "outputs", "audio", "lighting")
  foreach ($k in $requiredTop) {
    if (-not ($profile.PSObject.Properties.Name -contains $k)) {
      throw "Profile missing required property: '$k'"
    }
  }

  if (-not $profile.controller.type -or -not $profile.controller.connection) {
    throw "Profile.controller must include 'type' and 'connection'."
  }

  if (-not ($profile.outputs -is [System.Collections.IEnumerable]) -or $profile.outputs.Count -lt 1) {
    throw "Profile.outputs must be a non-empty array."
  }

  foreach ($o in $profile.outputs) {
    if (-not $o.outputNumber -or -not $o.logicalName) {
      throw "Each output must include 'outputNumber' and 'logicalName'."
    }
  }

  if (-not $profile.audio.mode -or -not $profile.audio.channels) {
    throw "Profile.audio must include 'mode' and 'channels'."
  }

  return $true
}

function Invoke-Stage {
  param(
    [Parameter(Mandatory=$true)][string]$StageId,
    [Parameter(Mandatory=$true)][string]$StageName,
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter(Mandatory=$true)]$Profile,
    [Parameter(Mandatory=$true)][string]$ReportFolder
  )

  $result = [ordered]@{
    stageId      = $StageId
    stageName    = $StageName
    status       = "NOTRUN"
    startedUtc   = (Get-Date).ToUniversalTime().ToString("o")
    endedUtc     = $null
    notes        = @()
    data         = @{}
  }

  if (-not (Test-Path $ScriptPath)) {
    $result.status = "SKIPPED"
    $result.endedUtc = (Get-Date).ToUniversalTime().ToString("o")
    $result.notes += "Stage script not found: $ScriptPath"
    return [pscustomobject]$result
  }

  try {
    Write-Host ""
    Write-Host "Running: $StageId - $StageName"
    Write-Host "Script : $ScriptPath"

    # Each stage script should accept -Profile and -ReportFolder and return an object:
    # @{ status="PASS|FAIL|WARN"; notes=@("..."); data=@{...} }
    $stageOut = & $ScriptPath -Profile $Profile -ReportFolder $ReportFolder

    if ($null -eq $stageOut) {
      $result.status = "WARN"
      $result.notes += "Stage returned no output. Treating as WARN."
    } else {
      if ($stageOut.PSObject.Properties.Name -contains "status") {
        $result.status = [string]$stageOut.status
      } else {
        $result.status = "WARN"
        $result.notes += "Stage output missing 'status'. Treating as WARN."
      }

      if ($stageOut.PSObject.Properties.Name -contains "notes" -and $stageOut.notes) {
        $result.notes += $stageOut.notes
      }

      if ($stageOut.PSObject.Properties.Name -contains "data" -and $stageOut.data) {
        $result.data = $stageOut.data
      }
    }
  } catch {
    $result.status = "FAIL"
    $result.notes += "Exception: $($_.Exception.Message)"
  } finally {
    $result.endedUtc = (Get-Date).ToUniversalTime().ToString("o")
  }

  return [pscustomobject]$result
}

function Write-HealthReport {
  param(
    [Parameter(Mandatory=$true)][string]$ReportFolder,
    [Parameter(Mandatory=$true)]$Profile,
    [Parameter(Mandatory=$true)][System.Collections.Generic.List[object]]$StageResults
  )

  Ensure-Folder $ReportFolder

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ReportFolder "health-report-$stamp.json"
  $txtPath  = Join-Path $ReportFolder "health-report-$stamp.txt"

  $overall = "PASS"
  foreach ($r in $StageResults) {
    if ($r.status -eq "FAIL") { $overall = "FAIL"; break }
    if ($r.status -eq "WARN" -and $overall -ne "FAIL") { $overall = "WARN" }
  }

  $reportObj = [ordered]@{
    generatedUtc = (Get-Date).ToUniversalTime().ToString("o")
    overallStatus = $overall
    profile = [ordered]@{
      profileName = $Profile.profileName
      version     = $Profile.version
      controller  = $Profile.controller
      audio       = $Profile.audio
      lighting    = $Profile.lighting
      outputCount = $Profile.outputs.Count
      inputCount  = if ($Profile.PSObject.Properties.Name -contains "inputs") { $Profile.inputs.Count } else { 0 }
    }
    stages = $StageResults
  }

  ($reportObj | ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 $jsonPath

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("Cabinet Activation Report")
  $lines.Add(("=" * 26))
  $lines.Add("Generated (UTC): $($reportObj.generatedUtc)")
  $lines.Add("Overall Status : $($reportObj.overallStatus)")
  $lines.Add("")
  $lines.Add("Profile: $($Profile.profileName)  (v$($Profile.version))")
  $lines.Add("Controller: $($Profile.controller.type) via $($Profile.controller.connection)")
  $lines.Add("Outputs: $($Profile.outputs.Count) | Audio: $($Profile.audio.mode) $($Profile.audio.channels) | LED Matrix: $($Profile.lighting.ledMatrix) | Addressable: $($Profile.lighting.addressableStrips)")
  $lines.Add("")
  $lines.Add("Stage Results:")
  foreach ($r in $StageResults) {
    $lines.Add(("- {0} [{1}] {2}" -f $r.stageId, $r.status, $r.stageName))
    if ($r.notes -and $r.notes.Count -gt 0) {
      foreach ($n in $r.notes) {
        $lines.Add(("    - {0}" -f $n))
      }
    }
  }

  $lines | Set-Content -Encoding UTF8 $txtPath

  return [pscustomobject]@{
    overallStatus = $overall
    jsonPath = $jsonPath
    textPath = $txtPath
  }
}

# ----------------------------
# Main
# ----------------------------
Write-Section "PinOne Post-Baller Activation Toolkit"

# Resolve paths from current working directory
$repoRoot = (Resolve-Path ".").Path
$ProfilePathResolved = (Resolve-Path $ProfilePath).Path

Write-Host "Repo Root   : $repoRoot"
Write-Host "Profile Path: $ProfilePathResolved"

$profile = Read-JsonFile $ProfilePathResolved
Test-ProfileBasics $profile | Out-Null

Write-Host ""
Write-Host "Loaded Profile:"
Write-Host "  Name      : $($profile.profileName)"
Write-Host "  Version   : $($profile.version)"
Write-Host "  Controller: $($profile.controller.type) ($($profile.controller.connection))"
Write-Host "  Outputs   : $($profile.outputs.Count)"
Write-Host "  Audio     : $($profile.audio.mode) $($profile.audio.channels)"
Write-Host "  Lighting  : LedMatrix=$($profile.lighting.ledMatrix) AddressableStrips=$($profile.lighting.addressableStrips)"

$reportFolder = Join-Path $repoRoot "reports"
Ensure-Folder $reportFolder

# Define stages (can expand over time)
$stages = @(
  [pscustomobject]@{
    id = "S1"
    name = "Windows Hardening"
    script = Join-Path $repoRoot "scripts\validate-windows.ps1"
  },
  [pscustomobject]@{
    id = "S2"
    name = "PinOne Device Validation"
    script = Join-Path $repoRoot "scripts\validate-pinone.ps1"
  },
  [pscustomobject]@{
    id = "S3"
    name = "VPX Input Mapping + Plunger"
    script = Join-Path $repoRoot "scripts\validate-vpx.ps1"
  },
  [pscustomobject]@{
    id = "S4"
    name = "DOF Bring-Up + Output Test"
    script = Join-Path $repoRoot "scripts\test-dof.ps1"
  },
  [pscustomobject]@{
    id = "S5"
    name = "LED Matrix + Addressable LEDs"
    script = Join-Path $repoRoot "scripts\test-leds.ps1"
  },
  [pscustomobject]@{
    id = "S6"
    name = "SSF 7.1 Calibration"
    script = Join-Path $repoRoot "scripts\test-ssf.ps1"
  }
)

$stageResults = New-Object System.Collections.Generic.List[object]

function Run-AllStages {
  foreach ($s in $stages) {
    $r = Invoke-Stage -StageId $s.id -StageName $s.name -ScriptPath $s.script -Profile $profile -ReportFolder $reportFolder
    $stageResults.Add($r) | Out-Null

    if (-not $Force -and $r.status -eq "FAIL") {
      Write-Host ""
      Write-Host "Stopping due to FAIL in $($s.id) (use -Force to continue)." -ForegroundColor Yellow
      break
    }
  }
}

function Show-Menu {
  Write-Host ""
  Write-Host "Select an option:"
  Write-Host "  1) Run all stages"
  Write-Host "  2) Run Stage 1 (Windows Hardening)"
  Write-Host "  3) Run Stage 2 (PinOne Validation)"
  Write-Host "  4) Run Stage 3 (VPX Mapping)"
  Write-Host "  5) Run Stage 4 (DOF Output Test)"
  Write-Host "  6) Run Stage 5 (LED Tests)"
  Write-Host "  7) Run Stage 6 (SSF Tests)"
  Write-Host "  8) Generate report from current results"
  Write-Host "  9) Exit"
}

if ($NonInteractive) {
  Run-AllStages
} else {
  while ($true) {
    Show-Menu
    $choice = Read-Host "Enter choice (1-9)"

    switch ($choice) {
      "1" { Run-AllStages }
      "2" {
        $s = $stages | Where-Object { $_.id -eq "S1" }
        $stageResults.Add((Invoke-Stage -StageId $s.id -StageName $s.name -ScriptPath $s.script -Profile $profile -ReportFolder $reportFolder)) | Out-Null
      }
      "3" {
        $s = $stages | Where-Object { $_.id -eq "S2" }
        $stageResults.Add((Invoke-Stage -StageId $s.id -StageName $s.name -ScriptPath $s.script -Profile $profile -ReportFolder $reportFolder)) | Out-Null
      }
      "4" {
        $s = $stages | Where-Object { $_.id -eq "S3" }
        $stageResults.Add((Invoke-Stage -StageId $s.id -StageName $s.name -ScriptPath $s.script -Profile $profile -ReportFolder $reportFolder)) | Out-Null
      }
      "5" {
        $s = $stages | Where-Object { $_.id -eq "S4" }
        $stageResults.Add((Invoke-Stage -StageId $s.id -StageName $s.name -ScriptPath $s.script -Profile $profile -ReportFolder $reportFolder)) | Out-Null
      }
      "6" {
        $s = $stages | Where-Object { $_.id -eq "S5" }
        $stageResults.Add((Invoke-Stage -StageId $s.id -StageName $s.name -ScriptPath $s.script -Profile $profile -ReportFolder $reportFolder)) | Out-Null
      }
      "7" {
        $s = $stages | Where-Object { $_.id -eq "S6" }
        $stageResults.Add((Invoke-Stage -StageId $s.id -StageName $s.name -ScriptPath $s.script -Profile $profile -ReportFolder $reportFolder)) | Out-Null
      }
      "8" {
        $rep = Write-HealthReport -ReportFolder $reportFolder -Profile $profile -StageResults $stageResults
        Write-Host ""
        Write-Host "Report generated:"
        Write-Host "  JSON: $($rep.jsonPath)"
        Write-Host "  TEXT: $($rep.textPath)"
      }
      "9" { break }
      default { Write-Host "Invalid choice." -ForegroundColor Yellow }
    }
  }
}

# Always write a report at end if we have any results
if ($stageResults.Count -gt 0) {
  $rep = Write-HealthReport -ReportFolder $reportFolder -Profile $profile -StageResults $stageResults
  Write-Host ""
  Write-Host "Final report:"
  Write-Host "  JSON: $($rep.jsonPath)"
  Write-Host "  TEXT: $($rep.textPath)"
} else {
  Write-Host ""
  Write-Host "No stages were run. Exiting."
}