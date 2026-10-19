# Handoff — `vwTpwpmChanges` dead-column fix (`MaterialSubstituted`)

**Written:** 2026-10-19 · **Owner:** JAlmonte · **Status (2026-10-19, evening):** **APPLIED and validated on
GenieDev** (FIC-SQL02, view `modify_date` 2026-10-19 17:40:01.560) — see §8. **Production (FIC-SQL01 `Genie`)
NOT applied**: it still had the column per the user 2026-10-19; `deploy/FixGenieTpwpmChangesDeadColumn.sql`
is ready for the user to run personally.

**Scope of the session that picks this up:** apply and validate the fix on **`sqlb` / `GenieDev` only**,
and produce a script the user will run on production **personally**. **Never connect to FIC-SQL01.**

Full background and the 09-30 review: memory file `genie-vwtpwpmchanges-dead-column`
(`C:\Users\jalmonte\.claude\projects\D--source-repos-genie\memory\`). This doc is self-contained for the work.

---

## 1. TL;DR

`dbo.vwTpwpmChanges` is `SELECT DISTINCT` and computes `MaterialSubstituted` with a per-row correlated
`SELECT TOP (1) PartNum FROM epicor.JobMtl ...`. No consumer reads the column, but `DISTINCT` forces the
optimizer to compute it anyway. Removing it measured **12.2x** faster on Query Store query_id 77
(`SELECT ... FROM dbo.vwDrawingPullByPlant WHERE TransactionID = @p0 AND PullDrawing = @p1`; worst 54.6 s).

**Decision: DROP the column** (not a `CAST(0 AS BIT)` stub). A stub collapses `DISTINCT` rows exactly
like a drop does, so it buys no safety — and for any unknown reader a drop fails loudly while a stub
returns silently wrong data. (An earlier review claimed the stub had "zero collapse risk"; that was wrong.)

## 2. Why the previous session could not do it

- No `sqlserver` MCP in that session, and the only saved login (`claude_readonly`) is read-only: it
  **cannot read view definitions** (`OBJECT_DEFINITION` returns NULL) and **cannot `ALTER VIEW`**.
- Auto mode blocked a `sqlcmd` call that read the `claude_readonly` password out of `~/.claude.json`.
- The current definition exists **nowhere on disk or in any git history** — only on the servers.

## 3. Access this session needs (user sets up BEFORE starting it)

Preferred — **Windows auth, no stored password:** the user's AD account must have, on `sqlb`/`GenieDev`:
`SELECT`, `VIEW DEFINITION` (database-wide, or at least the 5 objects in §5), and `ALTER` on
`dbo.vwTpwpmChanges`. `SHOWPLAN` is optional.

```
"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe" -S sqlb -E -d GenieDev -N -C -t 900 -W -s "|" -i "<WINDOWS\backslash\path.sql>"
```

- `-i` needs a **backslash** Windows path; forward slashes fail with `Access is denied`.
- Allow `sqlcmd` in the session's permission rules so auto mode doesn't stop it.
- Alternative: an MCP entry with a write-capable login. The `sqlserver` MCP is keyed to
  `D:\source\repos\genie` in `~/.claude.json` and only loads when the session **starts in that folder** —
  a session started in `genie-sql` gets no MCP.

First query of the session, to prove you are where you think you are:
`SELECT @@SERVERNAME, DB_NAME();` — expect `sqlb`-side server and `GenieDev`. Stop if it says FIC-SQL01.

## 4. Steps

### 4.1 Preflight (read-only)
1. Confirm the column exists in GenieDev and record the view's `modify_date`:
   ```sql
   SELECT o.modify_date,
          (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = o.object_id AND c.name = 'MaterialSubstituted') AS matsub,
          (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = o.object_id) AS total_cols
   FROM sys.objects o WHERE o.object_id = OBJECT_ID('dbo.vwTpwpmChanges');
   ```
2. Capture the **exact** current definition with `OBJECT_DEFINITION(OBJECT_ID('dbo.vwTpwpmChanges'))`
   and save it **verbatim** as `views/vwTpwpmChanges_rollback.sql` (change only `CREATE VIEW` → `ALTER VIEW`).
   Also record `HASHBYTES('SHA2_256', OBJECT_DEFINITION(OBJECT_ID('dbo.vwTpwpmChanges')))` — the production
   guard in §4.4 needs it.
3. Check for schema-bound dependents (an `ALTER` that drops a column fails if one exists):
   ```sql
   SELECT OBJECT_NAME(referencing_id) AS referrer, is_schema_bound_reference
   FROM sys.sql_expression_dependencies WHERE referenced_id = OBJECT_ID('dbo.vwTpwpmChanges');
   ```
   With `VIEW DEFINITION` this should list the four consumers in §5. **0 rows means the permission is
   still missing, not that there are no dependents.**

### 4.2 Prove the row-merge question across the WHOLE view (read-only)
Dropping a column from a `DISTINCT` can merge rows that differed only in it. Measure it directly, rather
than relying on the 6-parameter sample from September. Build the column list from `sys.columns` (every
column except `MaterialSubstituted`), then:
```sql
SELECT COUNT(*) FROM dbo.vwTpwpmChanges;                                   -- n_orig
SELECT COUNT(*) FROM (SELECT DISTINCT <all cols except MaterialSubstituted>
                      FROM dbo.vwTpwpmChanges) d;                          -- n_fixed
```
This is the expensive path (full view, every JobMtl lookup), so use a long `-t`. `n_orig - n_fixed` is
the number of rows the drop will merge on GenieDev data.

- **0** → no merge on current data; proceed.
- **> 0** → still fine **if** every consumer is itself `DISTINCT` or ignores row counts (§5). Read each
  consumer's definition and confirm it doesn't `COUNT`/`SUM`/`ROW_NUMBER` over raw `vwTpwpmChanges` rows.
  `vwDrawingPullByPlant` is already known to be `DISTINCT`. Report the number and what you found to the user before applying.

### 4.3 Apply on GenieDev, then validate
Do it in **one `sqlcmd -i` file** (one connection, so `#temp` tables survive across `GO`):
1. Baseline: for each test TransactionID, `SET STATISTICS IO, TIME ON` and run the query-77 shape
   (`SELECT COUNT(*) FROM dbo.vwDrawingPullByPlant WHERE TransactionID = @p0 AND PullDrawing = 1`), and
   `SELECT * INTO #before_<n>` for its full result. Test IDs from September's production tests (they may not exist in
   GenieDev; if not, pick 3–5 TransactionIDs with the most rows from the base table):
   `1B22A774-DFF4-4D2C-8E5D-8FBD66E47FC9` (169 rows in prod), `586335B9-10C1-4DB1-BB19-C92BE3317B10`,
   `4148BB24-5634-47B4-BBDD-69083A819414`, `193E7324-FE01-4C20-AAE0-CF33CD9BD8D4`,
   `489A1353-874A-4041-BAA9-CCE1D433837E`, `7C9B5785-372D-4DC3-BF12-1D9066C69EFF`.
2. `ALTER VIEW dbo.vwTpwpmChanges` — the captured definition with **only** this block removed (it sits
   between `PieceNumber` and `PieceNameChanging`):
   ```sql
   CAST((CASE WHEN (SELECT TOP (1) PartNum FROM epicor.JobMtl AS jm
                    WHERE tpwpm.AuthorID = jm.FPBAuthorID_c AND tpwpm.ProjectID = jm.FPBProjectID_c
                      AND tpwpm.WorksheetID = jm.FPBWorksheetID_c AND tpwpm.PartID = jm.FPBPartID_c
                      AND tpwpm.PieceNumber = jm.FPBPieceNumber_c AND tpwpm.MaterialID = jm.PartNum) IS NULL
              THEN 1 ELSE 0 END) AS BIT) AS MaterialSubstituted,
   ```
   Everything else — the `DISTINCT`, the other five computed columns, all joins, the correlated `MAX()`
   predicates, `PieceNumber NOT BETWEEN 90 AND 98` — stays byte-identical.
3. `EXEC sp_refreshview` on each non-schema-bound **view** among the dependents (cheap insurance against
   stale metadata if any of them uses `*`).
4. Re-run step 1 into `#after_<n>`; report `EXCEPT` both directions (expect 0 / 0), row counts, elapsed
   time and logical reads. **`epicor.JobMtl` / `JobMtl_UD` should vanish from the IO output.**
   Compare **logical reads**, not ms — the second run benefits from a warm cache.
5. Re-run the §4.1 sys.columns check: `matsub = 0`, `total_cols` one lower.

Note: GenieDev's `epicor.*` objects are **synonyms into `E10Test`** (not `E10Test2`), so its numbers
won't match production's. Use dev for correctness, not for re-quoting the 12.2x.

### 4.4 Production script for the user (do NOT run it)
Write `deploy/FixGenieTpwpmChangesDeadColumn.sql`, runnable in plain SSMS (no SQLCMD mode needed):
```sql
USE [Genie];
GO
IF @@SERVERNAME NOT LIKE '%FIC-SQL01%'
   OR HASHBYTES('SHA2_256', OBJECT_DEFINITION(OBJECT_ID('dbo.vwTpwpmChanges'))) <> 0x<GenieDev pre-change hash>
BEGIN
    RAISERROR('Wrong server, or production definition differs from GenieDev - diff before applying.', 16, 1);
    SET NOEXEC ON;   -- persists across GO, so the ALTER below never runs
END
GO
ALTER VIEW dbo.vwTpwpmChanges AS ...   -- identical text to what was applied in GenieDev
GO
-- sp_refreshview on the same dependents as in dev
GO
SET NOEXEC OFF;
GO
SELECT COUNT(*) AS matsub_should_be_0 FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.vwTpwpmChanges') AND name = 'MaterialSubstituted';
```
- The hash guard prevents a bad copy-over: if production's view differs from GenieDev's, applying dev's
  text would silently replace production's version. A mismatch can also just be whitespace (dev and prod
  may have been scripted separately), so the user must **diff** the two before overriding the guard,
  not delete the guard.
- `views/vwTpwpmChanges_rollback.sql` is only a valid **production** rollback if the guard passed.
- `ALTER VIEW` takes a brief schema-modification lock and can queue behind an in-flight 35–55 s
  drawing-pull query. Tell the user to run it at a quiet moment.
- **Verifying in production afterwards:** the query keeps **query_id 77** (the app's query text doesn't change);
  the ALTER only forces new plans. Compare 77's runtime stats from intervals after the change against before:
  ```sql
  SELECT rsi.start_time, p.plan_id, rs.count_executions,
         CAST(rs.avg_duration/1000.0 AS decimal(18,1)) AS avg_ms, CAST(rs.avg_logical_io_reads AS bigint) AS avg_reads
  FROM sys.query_store_plan p
  JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
  JOIN sys.query_store_runtime_stats_interval rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
  WHERE p.query_id = 77 ORDER BY rsi.start_time DESC;
  ```

## 5. Consumers of `vwTpwpmChanges`
`vwDrawingPullByPlant` (DISTINCT — immune to row merging), `vwDrawingPull`, `vwDrawingPullFlag`,
`spWorksheetLookup`. None selects `MaterialSubstituted` (checked 08-13 and again 09-30). No Genie app
code references the view; `MaterialSubstituted` appears in source only as a local C# variable in
`genie-api/.../WorksheetJob/WorksheetJobProcess.cs`.

## 6. Deliverables and bookkeeping
- `genie-sql`: `views/vwTpwpmChanges.sql` (new definition), `views/vwTpwpmChanges_rollback.sql` (original,
  verbatim), `validation/vwTpwpmChanges_validation.sql` (the §4.2/§4.3 queries),
  `deploy/FixGenieTpwpmChangesDeadColumn.sql`, and this doc updated with the results. Repo convention:
  `views/` files are hand-maintained and go stale silently. Head each one with the server
  `modify_date` it reflects.
- Commit on a branch (`claude/perf/drawings/tpwpm-dead-column`), staging only these paths. **Don't push**
  unless the user says so. Write files with Write/Edit, not `sed -i` (it strips CRLF).
- Update the memory file `genie-vwtpwpmchanges-dead-column` (body **and** its `description:` line) and the
  `MEMORY.md` index line. Add a dated one-liner under `## Inbox` in `C:\Users\jalmonte\.claude\fleet\FLEET.md`
  for board item **#54** (re-read it first; stage only `FLEET.md`).

## 7. Out of scope — re-measure before touching
After the fix, the rest of query 77's cost is structural: the `PullDrawing` filter is a `CASE` across
two views and can't be pushed below the nested-`DISTINCT` join; `vwTpwpChanges` (no "m") calls `FORMAT()`
per row and does another correlated `TOP (1)` into `epicor.OrderRel`; `vwProcessedWorksheets` joins
`dbo.Wish` (835 MB). 12.2x may be enough.

## 8. Results — GenieDev, 2026-10-19
Connected as `FRDOMAIN\Jalmonte` (Windows auth); `sqlb` resolves to **`@@SERVERNAME = FIC-SQL02`**. FIC-SQL01
was never contacted. Server is SQL Server 2016 (13.0.6300.2, compat 130) — no `STRING_AGG`.

**Preflight (§4.1).** Pre-change `modify_date` 2023-11-22 09:32:09.860; 13 columns incl. `MaterialSubstituted`.
Pre-change hash `0x941CA59074D53B2A79C1C76B0B2418587020759C123D7969206AF3226D12A7E5` (the prod guard).
Dependents: `vwDrawingPullByPlant`, `vwDrawingPull`, `vwDrawingPullFlag` — all views, none schema-bound, all
`SELECT DISTINCT`, no `COUNT`/`SUM`/`ROW_NUMBER`/`*`. **`spWorksheetLookup` is not a live consumer:** it
mentions the view only in commented-out code, so it has no dependency row.

**Row merge (§4.2).** `n_orig = n_fixed = 958,332` → **0 rows merged** on GenieDev data (6–7 s each).

**Apply + validate (§4.3).** All six September TransactionIDs exist in GenieDev (1471/1011/1296/1283/3/20
base rows). Before/after `SELECT *` over the six IDs: `EXCEPT` 0/0 on all three consumers (1035 / 1313 / 542
rows); query-77 counts identical (169, 2, 67, 67, 2, 0). `JobMtl` and `JobMtl_UD` vanish from the IO output.
After: `matsub = 0`, 12 columns, new hash `0x39DEA55A4F355C1EB9C341AAE5EEFED382108564D28F1757B0773662D6B3E7F8`.

| TransactionID | logical reads before → after | elapsed before → after (warm cache; indicative only) |
|---|---|---|
| 4148BB24… | 56,136,684 → 581,250 | 48.6 s → 2.3 s |
| 193E7324… | 55,679,944 → 464,790 | 10.5 s (parallel) → 0.5 s |
| 586335B9… | 51,571,998 → 413,467 | 44.7 s → 1.7 s |
| 1B22A774… | 27,129,909 → 245,105 | 35.7 s → 1.0 s |
| 489A1353… | 657,796 → 5,537 | 0.6 s → 0.1 s |
| 7C9B5785… | 128,086 → 89,773 | 0.8 s → 0.4 s |

Dev's `epicor.*` points at E10Test, so these are correctness numbers, not a re-quote of production's 12.2x.

**Stored-text gotcha (matters for the hash guard).** SQL Server stores everything from after the `GO` line
break through the last CRLF before the next `GO`, and stores `ALTER` as `CREATE`. The captured definition starts
with a blank line and ends `;CRLF CRLF`; dev's new text ends `;CRLF` (one trailing blank line fewer than the
original). The repo files are written so their batches are byte-exact: running the rollback restores
`0x941C…`, and the deploy script reproduces `0x39DE…` and checks for it in its last `SELECT`.
Don't reformat those files: any whitespace change breaks the comparison.
