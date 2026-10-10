<#
Moves FightPlan's user data from the old root layout into Settings\ (run by
FightPlan.lua on load while an old file is present):
  settings.lua                      -> Settings\Shared.lua
  settings.lua.* / *.bak            -> Settings\Backups\
  partySavedFiles\**                -> Settings\Party\Legacy\**
  other non-addon files in the root -> Settings\Other\
Identical duplicates are dropped; when two different copies meet, the newer
one is kept and the older goes to Settings\Backups\Conflicts. A locked or
failing file is reported and skipped; the rest still moves. A named mutex
keeps two clients from migrating at once. Prints one line per step,
"ERROR: ..." per failure, then "OK" when everything moved.

Usage: powershell -NoProfile -ExecutionPolicy Bypass -File DataMigrate.ps1 -Root <addon folder>
#>
param([Parameter(Mandatory)][string]$Root)
$ErrorActionPreference = 'Stop'
$settings = Join-Path $Root 'Settings'
# Root files that belong to the addon itself (deploy owns them).
$owned = @('module.def', 'module.dis', 'icon.png')

# Old root-relative path -> new path under Settings\.
function ConvertTo-NewPath([string]$Relative) {
    $parts = $Relative.Split('\')
    if ($parts[0] -eq 'partySavedFiles') { return 'Party\Legacy\' + (($parts[1..($parts.Count - 1)]) -join '\') }
    if ($Relative -eq 'settings.lua') { return 'Shared.lua' }
    if ($Relative -match '^settings\.lua\..+|\.bak$') { return 'Backups\' + $Relative }
    return 'Other\' + $Relative
}

function Move-FPFile([IO.FileInfo]$File, [string]$To) {
    New-Item -ItemType Directory -Force -Path (Split-Path $To -Parent) | Out-Null
    $label = $To.Substring($settings.Length + 1)
    if (Test-Path -LiteralPath $To) {
        $existing = Get-Item -LiteralPath $To -Force
        if ((Get-FileHash -LiteralPath $To).Hash -eq (Get-FileHash -LiteralPath $File.FullName).Hash) {
            Remove-Item -LiteralPath $File.FullName -Force
            "dropped identical duplicate of $label"
            return
        }
        $conflict = Join-Path $settings ('Backups\Conflicts\' + $label + '.' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
        New-Item -ItemType Directory -Force -Path (Split-Path $conflict -Parent) | Out-Null
        if ($File.LastWriteTimeUtc -gt $existing.LastWriteTimeUtc) {
            Move-Item -LiteralPath $To -Destination $conflict
            Move-Item -LiteralPath $File.FullName -Destination $To
        } else {
            Move-Item -LiteralPath $File.FullName -Destination $conflict
        }
        "kept newer copy of $label; older one in Backups\Conflicts"
        return
    }
    Move-Item -LiteralPath $File.FullName -Destination $To
    "moved $($File.FullName.Substring($Root.Length + 1)) -> Settings\$label"
}

$mutex = [Threading.Mutex]::new($false, 'Global\FightPlanDataMigration')
$failed = 0
try {
    [void]$mutex.WaitOne()
    $files = @(Get-ChildItem -LiteralPath $Root -File -Force | Where-Object { $_.Name -notin $owned -and $_.Extension -ne '.lua' -or $_.Name -eq 'settings.lua' })
    $party = Join-Path $Root 'partySavedFiles'
    if (Test-Path -LiteralPath $party -PathType Container) {
        if ((Get-Item -LiteralPath $party -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { "ERROR: refusing to migrate a junction/symlink: $party"; $failed++ }
        else { $files += @(Get-ChildItem -LiteralPath $party -Recurse -File -Force) }
    }
    foreach ($file in $files) {
        try { Move-FPFile $file (Join-Path $settings (ConvertTo-NewPath $file.FullName.Substring($Root.Length + 1))) }
        catch { "ERROR: $($file.FullName): $($_.Exception.Message)"; $failed++ }
    }
    if ((Test-Path -LiteralPath $party) -and -not @(Get-ChildItem -LiteralPath $party -Recurse -File -Force).Count) {
        Remove-Item -LiteralPath $party -Recurse -Force
        'removed empty partySavedFiles'
    }
    if ($failed -eq 0) { 'OK' }
} catch {
    "ERROR: $($_.Exception.Message)"
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
