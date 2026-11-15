# pg_permissions — Windows x64

pgextwin is the issuer for **unofficial Windows x64 builds** of [pg_permissions](https://github.com/cybertec-postgresql/pg_permissions), packaged from the official upstream source (`REL_1_4_1`, commit `3360447e0668fed2b9db6a0ae1d086533781f9bd`). pg_permissions provides views and functions to review PostgreSQL object permissions and compare them against desired targets.

## Compatibility

Target PostgreSQL majors for this repository: **15–18** (`windows-x64`).

`pg_permissions` is a **SQL-only extension** (SQL `default_version = '1.4'`, upstream package version `1.4.1`) with no native DLL and no `shared_preload_libraries` requirement.

## Installation

1. Back up your installation and review the [upstream pg_permissions documentation](https://github.com/cybertec-postgresql/pg_permissions).
2. Extract the ZIP matching your PostgreSQL major and copy `share/extension/` contents (`pg_permissions.control` and `pg_permissions--*.sql`) into your PostgreSQL `share/extension/` directory.
3. Run `CREATE EXTENSION pg_permissions;` in each database that needs the extension.

## License

This is an independent, unofficial Windows package; see [LICENSE](LICENSE) for the upstream license notice.
