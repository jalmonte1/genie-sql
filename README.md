# genie-sql

Database objects and validation harnesses for Genie. Sits alongside `genie-api`,
`genie-vue` and `genie-deployment` under `D:\source\repos\genie`.

These files used to live in `genie-api/SQL/`. They were moved here so that database
changes version independently of the API — the API and the view schema are deployed
by different routes and on different cadences.

## Layout

| Path | Contents |
|---|---|
| `views/` | Definitions of database objects, as applied |
| `docs/` | Handoff / design notes for in-flight database work |
| `validation/` | Re-runnable query harnesses that prove a change behaves as intended |

## Environment

| | |
|---|---|
| Server | `sqlb` (resolves to `FIC-SQL02`) |
| Database | `GenieDev` |
| Read-only login | `claude_readonly` (credentials in `~/.claude.json`, project scope `D:\source\repos\genie`) |

**`epicor.*` are synonyms into `[E10Test]`** — all 40 of them, including `epicor.Part`
→ `[E10Test].[dbo].[Part]`. `E10Test2` is a near-identical but *separate* snapshot
(188 FUS parts exist only in `E10Test2`, 2 only in `E10Test`). Queries that must reflect
what a view actually joins to have to use `E10Test`. Re-confirm the synonym target before
trusting any cross-database query:

```sql
SELECT name, base_object_name FROM sys.synonyms WHERE SCHEMA_NAME(schema_id) = 'epicor';
```

## Running a validation harness

`sqlcmd` ships at `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe`.
Pass the script with `-i` and a **Windows** path — a forward-slash path fails with
`Access is denied`.

```bash
sqlcmd -S sqlb -U claude_readonly -P '<password>' -d GenieDev -N -C -t 540 -W -s "|" \
  -i 'D:\source\repos\genie\genie-sql\validation\vwActiveWorksheetPart_validation.sql'
```

`claude_readonly` can create `#temp` tables but **lacks `VIEW DEFINITION`** — `OBJECT_DEFINITION`
returns NULL, so view DDL cannot be re-scripted from the server. That is why `views/` holds
definitions captured by hand, and why they must be updated in the same change that alters the
database. Granting `VIEW DEFINITION ON OBJECT::dbo.vwActiveWorksheetPart TO claude_readonly`
would remove the friction.

## Conventions

- `vwActiveWorksheetPart` is slow (~34 s per full scan, 20,928 active rows). Harnesses
  materialise it **once** into a `#temp` table and query that, so every number in a run
  describes the same snapshot.
- A view definition in `views/` is the *as-applied* state, not a proposal. Update it in the
  same commit as the database change.
