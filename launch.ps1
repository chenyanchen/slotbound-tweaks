# Launch Slotbound with Slotbound Tweaks (Windows). Use launch.bat, which
# makes sure this runs in 64-bit PowerShell:
#   Terminal:            launch.bat [path\to\Slotbound.exe] [game args]
#   Steam launch option: "C:\path\to\slotbound-tweaks\launch.bat" %command%
# Env:
#   SB_DRYRUN=1   check the environment (64-bit PowerShell, C# compiler) without starting the game
#   SB_SELFTEST=1 run tools/selftest.lua after startup
#   SB_PROBE=1    run tools/probe.lua: a file-based REPL in the game (docs/investigating.md)
$ErrorActionPreference = 'Stop'
$Dir = $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $Dir 'logs'), (Join-Path $Dir 'config') | Out-Null
$LaunchLog = Join-Path $Dir 'logs\launch.log'
# Logging must never stop the launch: antivirus scanners briefly lock freshly
# written files, so retry and then give up silently.
$Utf8 = New-Object System.Text.UTF8Encoding $false
function Log([string]$msg) {
  for ($i = 0; $i -lt 10; $i++) {
    try { [IO.File]::AppendAllText($LaunchLog, $msg + "`r`n", $Utf8); return } catch { Start-Sleep -Milliseconds 50 }
  }
}

function Find-Game {
  $roots = @()
  $sp = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
  if ($sp) { $roots += $sp }
  $roots += (Join-Path ${env:ProgramFiles(x86)} 'Steam')
  $libs = @()
  foreach ($r in $roots) {
    $libs += $r
    $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
      foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
        $libs += $m.Groups[1].Value.Replace('\\', '\')
      }
    }
  }
  foreach ($lib in ($libs | Select-Object -Unique)) {
    $dir = Join-Path $lib 'steamapps\common\Slotbound'
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $exe = Join-Path $dir 'Slotbound.exe'
    if (Test-Path -LiteralPath $exe) { return $exe }
    $cands = @(Get-ChildItem -LiteralPath $dir -Filter '*.exe' | Where-Object { $_.Name -notmatch '^(lovec|unins)' })
    if ($cands.Count -eq 1) { return $cands[0].FullName }
  }
  return $null
}

try {
  Log ("=== launch.ps1 {0} 64bit={1} args: {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
       [Environment]::Is64BitProcess, ($args -join ' '))
  if (-not [Environment]::Is64BitProcess) { throw '64-bit PowerShell required (start through launch.bat)' }

  $src = Get-Content -LiteralPath (Join-Path $Dir 'inject.cs') -Raw -Encoding UTF8
  if (-not ('SlotboundTweaks.Injector' -as [type])) { Add-Type -TypeDefinition $src -Language CSharp }

  if ($env:SB_DRYRUN -eq '1') {
    Log ("PowerShell {0}; inject.cs compiled OK" -f $PSVersionTable.PSVersion)
    $g = Find-Game
    Log ("game: {0}" -f $(if ($g) { $g } else { 'not found' }))
    exit 0
  }

  $rest = @($args)
  $game = $null
  if ($rest.Count -gt 0 -and $rest[0] -like '*.exe') { $game = $rest[0]; $rest = @($rest | Select-Object -Skip 1) }
  if (-not $game) { $game = Find-Game }
  if (-not $game -or -not (Test-Path -LiteralPath $game)) { throw "Slotbound not found: $game" }
  $game = (Resolve-Path -LiteralPath $game).Path

  if (-not $env:SteamAppId) { $env:SteamAppId = '4459590' }
  if (-not $env:SteamGameId) { $env:SteamGameId = '4459590' }

  $gamePid = [SlotboundTweaks.Injector]::Run($game, [string[]]$rest, (Join-Path $Dir 'loader.lua'),
    (Join-Path $Dir 'logs\game.log'), (Join-Path $Dir 'logs\inject.log'), 120)

  # Keep this script alive while the game runs so Steam still sees it as running.
  if ($gamePid -gt 0) {
    Wait-Process -Id $gamePid -ErrorAction SilentlyContinue
    Log 'game exited'
  }
} catch {
  Log ("ERROR: {0}" -f $_)
  exit 1
}
