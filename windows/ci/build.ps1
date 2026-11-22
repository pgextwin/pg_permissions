[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PgRoot,

    [Parameter(Mandatory = $true)]
    [string]$UpstreamDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$manifestPath = Join-Path $PSScriptRoot "../../config/extension.json"
if (-not (Test-Path $manifestPath)) {
    throw "Missing packaging extension manifest: $manifestPath"
}
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($manifest.name -ne "pg_permissions" -or
    [string]::IsNullOrWhiteSpace([string]$manifest.upstream.version) -or
    [string]::IsNullOrWhiteSpace([string]$manifest.upstream.commit)) {
    throw "Invalid pg_permissions packaging manifest."
}

$actualCommit = (& git -C $UpstreamDir rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $actualCommit -cne ([string]$manifest.upstream.commit).ToLowerInvariant()) {
    throw "Upstream commit '$actualCommit' differs from manifest '$($manifest.upstream.commit)'."
}

$controlPath = Join-Path $UpstreamDir "pg_permissions.control"
if (-not (Test-Path $controlPath -PathType Leaf)) {
    throw "Required pg_permissions.control was not found: $controlPath"
}
$control = Get-Content $controlPath -Raw
if ($control -notmatch "(?m)^default_version\s*=\s*'([^']+)'") {
    throw "Could not determine pg_permissions default_version from pg_permissions.control."
}
$sqlDefaultVersion = $Matches[1]
if ($sqlDefaultVersion -ne "1.6") {
    throw "Expected pg_permissions.control default_version '1.6', found '$sqlDefaultVersion'."
}

$sqlFiles = @(Get-ChildItem -Path $UpstreamDir -File -Filter "pg_permissions--*.sql")
if ($sqlFiles.Count -ne 12) {
    throw "Expected 12 upstream pg_permissions SQL files, found $($sqlFiles.Count)."
}

$pgConfig = Join-Path $PgRoot "bin\pg_config.exe"
$pgVersionText = (& $pgConfig --version).Trim()
if ($LASTEXITCODE -ne 0 -or $pgVersionText -notmatch '^PostgreSQL\s+(15|16|17|18|19)(?:\.|\s)') {
    throw "Unsupported or unrecognized PostgreSQL version from pg_config: '$pgVersionText'"
}

Write-Host "Verified SQL-only pg_permissions $($manifest.upstream.version) (SQL default_version $sqlDefaultVersion) for $pgVersionText; no DLL build required."
