# Handoff — `vwActiveWorksheetPart` EpiPart join fix

**Written:** 2026-09-16 · **Owner:** JAlmonte · **Status:** change is LIVE in `GenieDev`
(applied manually, server `modify_date` 2026-09-16 22:02:33) and **validated** — see §4.

Read this plus [`../views/vwActiveWorksheetPart.sql`](../views/vwActiveWorksheetPart.sql) and you
have the whole picture. These files moved out of `genie-api/SQL/` into this repo (`genie-sql`) on
2026-09-16 so database changes version independently of the API.

---

## 1. TL;DR

The `EpiPart` (`epicor.Part`) join in `GenieDev.dbo.vwActiveWorksheetPart` was keyed on the wrong
column, leaving `EpiPartNum` NULL for ~63% of rows. It is now keyed on a resolved-key CASE.

**The fix works.** Match rate is **19,761 / 20,928 = 94.4%**, up from 7,509 / 20,500 ≈ 37%.
All four validation queries from the original §5 have been run; none found a problem, and two of
the three "risks" turned out to be improvements or non-events.

**But almost none of the evidence originally proposed for the change was evidence about the
change.** Three things to carry forward:

1. `genie_differs = 0` is a **tautology** and can never be non-zero (§5). Do not cite it.
2. The two edits made on 2026-09-16 (`LEN = 5` → `LEN > 4`, and the `ELSE` simplification) are
   **behaviourally indistinguishable** from their predecessors on all current and historical data.
   A rollback would produce byte-identical output, so no query can confirm which text is installed.
3. Several **pre-existing** defects were found while validating (§6). None was caused by this
   change; all still bite today.

## 2. The original problem

Original join:

```sql
LEFT OUTER JOIN epicor.Part AS EpiPart
    ON EpiPart.Company = 'FUS'
       AND EpiPart.PartNum = CAST(rp.PartNumber AS NVARCHAR)   -- bare numeric
```

Epicor stores **engineered project parts** as `<OrderNumber>-<PartNumber>` (e.g. `111750-13232`),
but **catalog hardware/shim parts** under their bare number (e.g. `11997` = "ANCHR WDGE 5/8 X 6
ZINC"). Keying only on the bare numeric matched the catalog parts and missed every engineered part.

**Trap:** you cannot use the `GeniePartNum` CASE as the join key if its branch 1 reads
`EpiPart.PartNum` — the predicate collapses to `EpiPart.PartNum = EpiPart.PartNum` (TRUE) and
cross-joins ~119k FUS parts. The implemented key has no self-reference, so this is gone.

## 3. What is live now

A single **resolved-key CASE**, used both as the `GeniePartNum` output *and* as the join predicate:

```sql
CASE
    WHEN LEN(wp.PartNumber) > 4 THEN
        CONVERT(NVARCHAR, wp.PartNumber)                                           -- catalog: bare numeric
    WHEN wp.IsPhantom = 0 OR tpwpm.MaterialID = '13619' THEN
        CONCAT(LTRIM(RTRIM(w.OrderNumber)), '-', FORMAT(wp.PartNumber, '00000'))   -- project form
    ELSE
        tpwpm.MaterialID                                                           -- phantom
END
```

Each branch is **behaviourally conformant** against the live view, zero exceptions:

| Branch | Rows | Exceptions |
|---|--:|--:|
| 1 — bare numeric (`LEN > 4`) | 7,630 | 0 |
| 2 — project form (`LEN ≤ 4`, `IsPhantom = 0`) | 12,375 | 0 |
| 3 — `MaterialID` (phantom) | 254 | 0 |
| `GeniePartNum` NULL | 15 | — |

The `OR tpwpm.MaterialID = '13619'` disjunct is live and load-bearing: 654 phantom rows take the
project-form branch and **every one** has a `13619` material; zero phantoms take it without one.

The 15 NULL rows are all `IsPhantom = 1`, `LEN(PartNumber) = 4`, and NULL because the `tpwpm` join
yields no material row (11 have no material at all; 4 have only a `PieceNumber = 99` row). Both the
old and new CASE return NULL there.

### Diagnostic column `PrevGeniePartNum`

Slated for removal by JAlmonte. **Do not use it.** See §5.

## 4. Validation results — the original §5 queries, answered

Run 2026-09-16 against `GenieDev` on `sqlb` (`FIC-SQL02`) as `claude_readonly`. Snapshot 20,928 rows.

| | Query | Result | Verdict |
|---|---|--:|---|
| **Q1** | Does `LEN > 4` misroute engineered parts? | **0** | Risk retired |
| **Q2** | Previously-matching rows re-keyed | **41** (39 re-pointed, 2 lost) | Improvement, not regression |
| **Q3** | total / matched / `genie_differs` | **20,928 / 19,761 / 0** | 94.4% match; the `0` is meaningless |
| **Q4** | Newly-matched hardware (`PullDrawing` flip) | **3** | Negligible — and see §6.3 |

**Q1 is dead, harder than "zero misroutes".** Not one of the 7,630 branch-1 rows has a bare part
missing from Epicor — under `LEN = 5` or `LEN > 4`, in either `E10Test` or `E10Test2`.

**Q2's 41 rows are a fix.** 39 re-pointed to the project form; 2 lost the match outright (both
`PartNumber` 126 → `206020-00126`, two distinct transactions). The bare parts they used to match are
junk: `126` = "GENIE TEST PART # 2", `444` = "GENIE TEST PART", `1018` = "Charger", against Genie
rows named Upright, PRBeam, GIBeam, Custom. Those were coincidental collisions with low-numbered
catalog parts. Original risk #2 is **inverted**.

Length distribution (`LEN(PartNumber)` → rows / matched): 1 → 354/270 · 2 → 1,276/1,142 ·
3 → 5,537/5,294 · 4 → 6,131/5,425 · 5 → 7,630/**7,630**. The 1,167 unmatched rows sit entirely at
`LEN` 1–4. No `LEN ≥ 6` rows exist.

### Closed: the two items the original handoff left open

**`epicor.Part` is a SEEK.** `Scan count 0, logical reads 81` for a single-transaction query — a scan
of 119,129 FUS rows would be thousands of reads. `FORMAT` in the predicate did not force a scan.
(`SET SHOWPLAN_ALL ON` → `Msg 262, SHOWPLAN permission denied`, so there is no graphical plan.)

**The `FORMAT`-is-slow nit is retired.** The key CASE is not where this view's cost lives. One 26-row
transaction burns **1.5 s CPU**: Worktable 1,306,850 logical reads · `OrderRel_UD` 112,476 ·
`JobHead_UD` 19,799 · `Vendor` 12,366 · `Part` **81**. `Part` is the cheapest object touched. The
proposed `CROSS APPLY (VALUES (CASE … END))` would optimise a rounding error.

## 5. Why `genie_differs = 0` proves nothing

`PrevGeniePartNum`'s branch 1 is `WHEN EpiPart.PartNum IS NOT NULL AND LEN(EpiPart.PartNum) > 4
THEN EpiPart.PartNum` — and `EpiPart` is joined **on the new key**. So on every matched row
`PrevGeniePartNum ≡ EpiPartNum ≡ GeniePartNum` by construction:

| `PrevGeniePartNum` branch | Rows | Differs |
|---|--:|--:|
| 1 — `EpiPart.PartNum` (**tautology**) | 19,761 | 0 |
| 2 — `BETWEEN 90000 AND 99999` | **0** (shadowed by branch 1) | — |
| 3 — project-form CONCAT | 876 | 0 |
| 4 — phantom tail | 291 | 0 |

94.4% of rows compare a value with itself; the remaining 1,167 are exactly the unmatched rows, where
the other branches coincide with the new CASE **by text**. The one branch that could have
distinguished them fires on zero rows. `genie_differs` is arithmetically incapable of being non-zero.

### The 2026-09-16 edits cannot be validated behaviourally either

`LEN = 5` → `LEN > 4` can only change a row with `LEN(PartNumber) ≥ 6`: **0 rows** in the view, and
**0 in 6.4 years of history** (`tblProjectWorksheetPart`, 294,320 rows, max `PartNumber` 99,056).

`WHEN NOT(…) THEN MaterialID ELSE NULL` → `ELSE MaterialID` can only differ when
`IsPhantom = 0 OR MaterialID = '13619'` evaluates to UNKNOWN, i.e. when `IsPhantom IS NULL`:
**0 rows**. And this is **structural, not data luck** — the `tpwpm` join carries
`AND rp.IsPhantom = 1` in its ON clause, so a NULL `IsPhantom` produces no material row at all,
`MaterialID` is NULL, and `ELSE MaterialID` returns NULL exactly as `ELSE NULL` did.

Direct replay of both CASE texts over all 923 phantom/`LEN ≤ 4` rows: 0 rows where they disagree.

**Consequence:** both edits are safe, and both are unfalsifiable on this data. The only evidence that
the new text is installed is the server's `modify_date`.

### The one live consequence of `LEN > 4`

It only bites at `PartNumber ≥ 100000`. Max today is **96,522**, with 1,273 rows already ≥ 90,000 and
175 ≥ 95,000 — about 3,478 short of the ceiling. When that day comes, `LEN > 4` keys them bare while
the old rule would have sent them to the project form.

⚠ **The C# will diverge at the same moment.** `GenieSharedModels/vwActiveWorksheetPartRec.cs`
(`DefaultPlanEnum`) forces Make when `PartNumber.ToString().StartsWith("9") && …Length == 5`. That is
an `== 5` test against SQL's `> 4`. A 6-digit `9xxxxx` part would be keyed bare by SQL but no longer
forced to Make by C#. Fix both or neither.

## 6. Pre-existing defects found while validating

**None of these were caused by this change. All bite today.**

### 6.1 The view emits duplicates on the exact key the app calls `.Single()` on

`vwActiveWorksheetPartRec.cs:234` does:

```csharp
db.Genie.vwActiveWorksheetParts.Single(p => p.TransactionID == transactionId
    && p.PartID == partId && p.GenieSplitID_c == (splitId ?? 0))
```

Grouping the view on exactly that key: **18 groups / 40 rows across 11 transactions.** Those 18
records throw `InvalidOperationException` in the constructor. Adding `RevisionLevel` to the grouping
does not help — still 18/40.

### 6.2 `GeniePartNum` is nondeterministic on 8 rows

The `MaterialID` branch has no tie-break, so a phantom part with several material rows is emitted
once per material — each with a **different Epicor key and ClassID**:

| Project / WS | PartID | PartNumber | Resolves to | ClassIDs |
|---|--:|--:|---|---|
| 521 / 1 | 11 | 8001 | 11143, 11145, 11580 | FLT, FLT, PLAT |
| 521 / 1 | 12 | 8002 | 11140, 11157, 11580, 12050, 13932 | FLT, STRP, PLAT, ANGL, HSS |

All 8 match a real Epicor part, so every one is a plausible-looking wrong answer. Which one a
`.First()` / `.Single()` consumer gets is arbitrary. (`PullDrawing` and `Stocked_c` agree within each
group, so only the part identity and class vary.)

### 6.3 §7's consumer table was wrong about the drawing puller

`GenieDrawingPuller/Puller.cs:223` gates on **`dbo.vwDrawingPullByPlant.PullDrawing`** — a different
view — and reads `vwActiveWorksheetPart` only for `GeniePartNum` / `PartID`:

```csharp
var pullDrawings = _db.Genie.vwDrawingPullByPlants
    .Where(p => p.TransactionID == _transactionId && p.PullDrawing == true).ToList();
var parts = _db.Genie.vwActiveWorksheetParts.Where(p => p.TransactionID == _transactionId).ToList();
```

So **this view's `PullDrawing` column does not drive the puller**, and any measurement of it says
nothing about puller workload. Whether `vwDrawingPullByPlant.PullDrawing` moves with this change is
**unverified** — `claude_readonly` cannot read that view's definition or dependencies either.

## 7. Downstream consumers of the affected columns

Verified on branch `bugfix/worksheets/drawings` in `genie-api`.

| Consumer | Reads | Note |
|---|---|---|
| `GenieSharedModels/vwActiveWorksheetPartRec.cs:52` | `EpiPartNum == null` → `DefaultPlanEnum` (Make) | also the `Length == 5` rule, §5 |
| `GenieSharedModels/vwActiveWorksheetPartRec.cs:393` | `ClassID` → `IsShimPart` → BuyAndCrossShip | affected by §6.2 nondeterminism |
| `GenieSharedModels/vwActiveWorksheetPartRec.cs:318,324` | `GeniePartNum` → Epicor `Parts`/`PartPlants` | |
| `GenieSharedModels/vwActiveWorksheetPartRec.cs:234` | `.Single()` on TransactionID+PartID+GenieSplitID_c | **throws on 18 records**, §6.1 |
| `GenieDrawingPuller/Puller.cs:223` | `vwDrawingPullByPlant.PullDrawing` — **not this view** | corrected, §6.3 |
| `…/EpicorImportData/WorksheetOrderDtl.cs:93` | `EpiPartNum` → writes Epicor `OrderDtl.PartExists` | |
| Hardware matching | `EpiPartNum == hw.PartNum` in `WorksheetInsert.cs`, `WorksheetManager.cs`, `WorksheetDataSyncAnalyzer.cs` | |

The view's own `PartExists` column is **write-only** — nothing branches on it. Vue (`genie-vue`)
reads only `IsHardware`, `PullDrawing`, `GeniePartNum`.

## 8. Environment notes

- ⚠ **`epicor.Part` is a SYNONYM to `[E10Test].[dbo].[Part]`, NOT `E10Test2`.** All 40 `epicor.*`
  synonyms resolve into `E10Test`. An earlier revision of this document said `E10Test2` and hardcoded
  it in all four §5 queries — that was **wrong**. The two are near-twins (188 FUS parts only in
  `E10Test2`, 2 only in `E10Test`) which is why the error survived; it changes Q2 from 41 to 22.
  Always re-confirm:
  ```sql
  SELECT name, base_object_name FROM sys.synonyms WHERE SCHEMA_NAME(schema_id) = 'epicor';
  ```
- `E10Test.dbo.Part` has 119,129 FUS rows, **unique on `PartNum`** (119,129 distinct) — so the key
  join cannot fan out. Local base table, no linked-server cost.
- **`claude_readonly` lacks `VIEW DEFINITION`.** `OBJECT_DEFINITION` returns NULL and the live DDL
  cannot be re-scripted — that is why `views/` is hand-maintained. It also means
  `sys.sql_expression_dependencies` returns **0 rows for this view, which is a permission artifact,
  not an absence of dependents.** Any other view/function/proc embedding this key could still be on
  the old expression and there is no way to tell. `SHOWPLAN` is denied too.
  Granting `VIEW DEFINITION` (ideally `VIEW ANY DEFINITION`) and `SHOWPLAN` closes all three gaps.
- The view is slow: **~34 s per full scan**, 20,928 active rows. Validation harnesses materialise it
  **once** into a `#temp` table — `claude_readonly` can create those. `TOP … WHERE` over computed
  columns can blow past a 60 s timeout.
- **MCP server `sqlserver`** is configured project-scoped in `~/.claude.json` under
  `D:\source\repos\genie`, pointing at `GenieDev`. It initialises only at session start and **only if
  the session cwd is `D:\source\repos\genie`** — not `genie-api`, and **not `genie-sql`**. Working in
  this repo, use `sqlcmd` directly (see [`../README.md`](../README.md)).
- `genie-api`, `genie-vue`, `genie-deployment` and `genie-sql` are **separate git repos**; the parent
  `D:\source\repos\genie` is not a repo.
- Earlier drafts are in `git stash` in `genie-api`: `stash@{1}` and `stash@{4}`, both containing the
  superseded **two-alias `EpiPartProj`** proposal. Not what was implemented.

## 9. Open items

1. **Drop `PrevGeniePartNum`** — JAlmonte to apply. It is a tautology (§5), not a control.
2. **Decide on `vwDrawingPullByPlant`** (§6.3) — does this change move the column the puller
   actually gates on? Needs `VIEW DEFINITION`.
3. **Fix the `.Single()` duplicates** (§6.1) — 18 records throw today.
4. **Give the `MaterialID` branch a tie-break** (§6.2) — 8 rows resolve to arbitrary Epicor parts.
5. **Align the C# `Length == 5` rule with SQL's `LEN > 4`** (§5) — dormant, but they will diverge.
6. **Request `VIEW DEFINITION` + `SHOWPLAN` for `claude_readonly`** — unblocks 2, the dependency
   audit, and real query plans.

## 10. Rejected alternative (don't re-litigate)

A two-alias approach (keep the numeric join, add a guarded `EpiPartProj` on the project-form key,
`COALESCE` every output) was drafted and reviewed. It worked but is strictly more complex, and left
`GeniePartNum` coupled to match success. The implemented single-key design supersedes it. A
collation-conflict concern about the new key was **refuted**: the original CASE already combined
`epicor.Part.PartNum`, `tpw.OrderNumber` and `tpwpm.MaterialID` in one expression in production.
