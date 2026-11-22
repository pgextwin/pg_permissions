[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PgRoot,

    [Parameter(Mandatory = $true)]
    [string]$UpstreamDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$control = Join-Path $UpstreamDir "pg_permissions.control"
$extensionDir = Join-Path $PgRoot "share\extension"

if (-not (Test-Path $control -PathType Leaf)) {
    throw "Required pg_permissions file was not found: $control"
}
if (-not (Test-Path $extensionDir -PathType Container)) {
    throw "PostgreSQL extension directory was not found: $extensionDir"
}

$sqlFiles = @(Get-ChildItem -Path $UpstreamDir -File -Filter "pg_permissions--*.sql")
if ($sqlFiles.Count -ne 12) {
    throw "Expected 12 pg_permissions SQL files, found $($sqlFiles.Count)."
}

Copy-Item $control (Join-Path $extensionDir "pg_permissions.control") -Force
foreach ($sqlFile in $sqlFiles) {
    Copy-Item $sqlFile.FullName (Join-Path $extensionDir $sqlFile.Name) -Force
}

Write-Host "Installed SQL-only pg_permissions control and $($sqlFiles.Count) SQL files into $extensionDir"
