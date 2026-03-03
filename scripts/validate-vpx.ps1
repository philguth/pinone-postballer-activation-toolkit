[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]$Profile,
  [Parameter(Mandatory=$true)][string]$ReportFolder
)

# TODO: Verify VPX configuration paths, key mappings, plunger axis configured, etc.
# For now: return WARN with guidance
return @{
  status = "WARN"
  notes  = @(
    "VPX validation not implemented yet.",
    "Manual check: open VPX, confirm flippers/start/exit mapped and plunger axis configured."
  )
  data   = @{}
}