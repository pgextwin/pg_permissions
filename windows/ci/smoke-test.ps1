[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PgRoot,

    [Parameter(Mandatory = $true)]
    [int]$PgPort,

    [Parameter(Mandatory = $true)]
    [int]$PostgreSqlMajor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PostgreSqlMajor -notin @(15, 16, 17, 18)) {
    throw "Unsupported PostgreSQL major for pg_permissions: $PostgreSqlMajor"
}

$initdb = Join-Path $PgRoot "bin\initdb.exe"
$pgCtl = Join-Path $PgRoot "bin\pg_ctl.exe"
$pgIsReady = Join-Path $PgRoot "bin\pg_isready.exe"
$psql = Join-Path $PgRoot "bin\psql.exe"

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$dataDir = Join-Path $tempRoot "pg_permissions-pg$PostgreSqlMajor-data"
$logFile = Join-Path $tempRoot "pg_permissions-pg$PostgreSqlMajor.log"
$setupSql = Join-Path $tempRoot "pg_permissions-pg$PostgreSqlMajor-setup.sql"

if (Test-Path $dataDir) {
    Remove-Item $dataDir -Recurse -Force
}
if (Test-Path $logFile) {
    Remove-Item $logFile -Force
}

& $initdb -D $dataDir -U postgres -A trust --encoding=UTF8 --no-locale
if ($LASTEXITCODE -ne 0) {
    throw "initdb failed."
}

function Show-PostgresLog {
    if (Test-Path $logFile) {
        Write-Host "----- PostgreSQL log -----"
        Get-Content $logFile -Tail 300
        Write-Host "--------------------------"
    }
}

function Wait-Postgres {
    for ($i = 0; $i -lt 45; $i++) {
        & $pgIsReady -h 127.0.0.1 -p $PgPort -q
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Start-Sleep -Seconds 2
    }
    Show-PostgresLog
    throw "Temporary PostgreSQL cluster did not become ready."
}

$started = $false
try {
    $serverOptions = "-p $PgPort -c listen_addresses=127.0.0.1"
    & $pgCtl -D $dataDir -l $logFile -o $serverOptions start
    if ($LASTEXITCODE -ne 0) {
        Show-PostgresLog
        throw "Failed to start PostgreSQL for pg_permissions smoke test."
    }
    $started = $true

    Wait-Postgres

    @'
CREATE EXTENSION pg_permissions SCHEMA public;

CREATE ROLE pgextwin_perm_u1 NOLOGIN;
CREATE ROLE pgextwin_perm_u2 NOLOGIN;

CREATE SCHEMA pgextwin_perm_schema;
CREATE TABLE pgextwin_perm_schema.t1 (
    id integer PRIMARY KEY,
    val text
);

INSERT INTO public.permission_target
    (role_name, permissions, object_type, schema_name, object_name, column_name)
VALUES
    ('pgextwin_perm_u1', ARRAY['USAGE']::public.perm_type[], 'SCHEMA', 'pgextwin_perm_schema', NULL, NULL),
    ('pgextwin_perm_u1', ARRAY['SELECT','INSERT']::public.perm_type[], 'TABLE', 'pgextwin_perm_schema', 't1', NULL);

GRANT USAGE ON SCHEMA pgextwin_perm_schema TO pgextwin_perm_u1;
GRANT SELECT ON TABLE pgextwin_perm_schema.t1 TO pgextwin_perm_u1;
GRANT SELECT ON TABLE pgextwin_perm_schema.t1 TO pgextwin_perm_u2;
'@ | Set-Content -Path $setupSql -Encoding utf8

    & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -v ON_ERROR_STOP=1 -f $setupSql
    if ($LASTEXITCODE -ne 0) {
        Show-PostgresLog
        throw "pg_permissions functional setup failed."
    }

    $totalDiffs = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT count(*) FROM public.permission_diffs() WHERE role_name IN ('pgextwin_perm_u1', 'pgextwin_perm_u2');") | Select-Object -Last 1).Trim()
    $missingInsert = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT count(*) FROM public.permission_diffs() WHERE missing = true AND role_name = 'pgextwin_perm_u1' AND object_type = 'TABLE' AND schema_name = 'pgextwin_perm_schema' AND object_name = 't1' AND permission = 'INSERT';") | Select-Object -Last 1).Trim()
    $extraSelect = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT count(*) FROM public.permission_diffs() WHERE missing = false AND role_name = 'pgextwin_perm_u2' AND object_type = 'TABLE' AND schema_name = 'pgextwin_perm_schema' AND object_name = 't1' AND permission = 'SELECT';") | Select-Object -Last 1).Trim()
    $schemaUsageGranted = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT granted FROM public.schema_permissions WHERE role_name = 'pgextwin_perm_u1' AND schema_name = 'pgextwin_perm_schema' AND permission = 'USAGE';") | Select-Object -Last 1).Trim()
    $tableSelectGranted = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT granted FROM public.table_permissions WHERE role_name = 'pgextwin_perm_u1' AND schema_name = 'pgextwin_perm_schema' AND object_name = 't1' AND permission = 'SELECT';") | Select-Object -Last 1).Trim()
    $tableInsertGranted = ((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -Atqc "SELECT granted FROM public.table_permissions WHERE role_name = 'pgextwin_perm_u1' AND schema_name = 'pgextwin_perm_schema' AND object_name = 't1' AND permission = 'INSERT';") | Select-Object -Last 1).Trim()

    if ($totalDiffs -ne "2") {
        throw "Expected 2 rows from public.permission_diffs() for smoke-test roles, got $totalDiffs"
    }
    if ($missingInsert -ne "1") {
        throw "permission_diffs() did not report missing INSERT for pgextwin_perm_u1: $missingInsert"
    }
    if ($extraSelect -ne "1") {
        throw "permission_diffs() did not report extra SELECT for pgextwin_perm_u2: $extraSelect"
    }
    if ($schemaUsageGranted -ne "t") {
        throw "schema_permissions did not report USAGE granted=t for pgextwin_perm_u1: $schemaUsageGranted"
    }
    if ($tableSelectGranted -ne "t" -or $tableInsertGranted -ne "f") {
        throw "table_permissions mismatch for pgextwin_perm_u1: SELECT=$tableSelectGranted INSERT=$tableInsertGranted"
    }

    & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -v ON_ERROR_STOP=1 -c "DROP SCHEMA pgextwin_perm_schema CASCADE; DROP ROLE pgextwin_perm_u1; DROP ROLE pgextwin_perm_u2; DROP EXTENSION pg_permissions;"
    if ($LASTEXITCODE -ne 0) {
        throw "pg_permissions smoke-test cleanup failed."
    }

    Write-Host "PASS: pg_permissions PG$PostgreSqlMajor functional smoke test"
}
catch {
    Show-PostgresLog
    throw
}
finally {
    if ($started -or (Test-Path (Join-Path $dataDir "postmaster.pid"))) {
        & $pgCtl -D $dataDir -m fast stop
    }
    if (Test-Path $dataDir) {
        Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
