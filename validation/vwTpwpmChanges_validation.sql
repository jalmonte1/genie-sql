/* vwTpwpmChanges dead-column fix - validation used on GenieDev (FIC-SQL02), 2026-10-19.
   Section A = handoff 4.2 (row-merge count, read-only). Section B = handoff 4.3 (apply + before/after
   diff over 6 TransactionIDs, run as ONE sqlcmd -i file so #temp tables survive GO).
   Section A result on 2026-10-19: n_orig = n_fixed = 958332, merged = 0.
   Section B result on 2026-10-19 (applied 17:40:01.560): EXCEPT 0/0 on vwDrawingPullByPlant (1035 rows),
   vwDrawingPull (1313), vwDrawingPullFlag (542); query-77 counts identical; JobMtl/JobMtl_UD gone from IO;
   total logical reads e.g. 56.1M -> 0.58M (4148BB24), 51.6M -> 0.41M (586335B9), 27.1M -> 0.25M (1B22A774).
   Section B's ALTER has ALREADY run on GenieDev - its hash guard will now abort a re-run, by design. */

/* ===== Section A ===== */
SET NOCOUNT ON;
SELECT @@SERVERNAME AS srv, DB_NAME() AS db, SYSDATETIME() AS started;
DECLARE @t0 datetime2 = SYSDATETIME();
DECLARE @n_orig bigint, @n_fixed bigint;
SELECT @n_orig = COUNT_BIG(*) FROM dbo.vwTpwpmChanges;
DECLARE @t1 datetime2 = SYSDATETIME();
SELECT @n_fixed = COUNT_BIG(*) FROM (
    SELECT DISTINCT TransactionID, AuthorID, ProjectID, WorksheetID, PartID, RevisionLevel, PieceNumber,
           MaterialIDChanging, PieceNameChanging, CutLengthChanging, PieceQtyChanging, ReferenceChanging
    FROM dbo.vwTpwpmChanges) d;
DECLARE @t2 datetime2 = SYSDATETIME();
SELECT @n_orig AS n_orig, @n_fixed AS n_fixed, @n_orig - @n_fixed AS merged,
       DATEDIFF(second, @t0, @t1) AS orig_s, DATEDIFF(second, @t1, @t2) AS fixed_s;
GO

/* ===== Section B ===== */
:on error exit
SET NOCOUNT ON;
IF @@SERVERNAME <> 'FIC-SQL02' OR DB_NAME() <> 'GenieDev'
    RAISERROR('Not FIC-SQL02/GenieDev - aborting.', 16, 1);
IF HASHBYTES('SHA2_256', OBJECT_DEFINITION(OBJECT_ID('dbo.vwTpwpmChanges'))) <> 0x941CA59074D53B2A79C1C76B0B2418587020759C123D7969206AF3226D12A7E5
    RAISERROR('vwTpwpmChanges changed since capture - aborting.', 16, 1);
SELECT @@SERVERNAME AS srv, DB_NAME() AS db, SYSDATETIME() AS started;
GO
CREATE TABLE #ids (id uniqueidentifier PRIMARY KEY);
INSERT #ids VALUES ('1B22A774-DFF4-4D2C-8E5D-8FBD66E47FC9'),('586335B9-10C1-4DB1-BB19-C92BE3317B10'),('4148BB24-5634-47B4-BBDD-69083A819414'),('193E7324-FE01-4C20-AAE0-CF33CD9BD8D4'),('489A1353-874A-4041-BAA9-CCE1D433837E'),('7C9B5785-372D-4DC3-BF12-1D9066C69EFF');
GO
PRINT '===== before - timed query-77 shape =====';
SET STATISTICS IO, TIME ON;
PRINT '--- before 1B22A774-DFF4-4D2C-8E5D-8FBD66E47FC9';
SELECT 'before' AS phase, '1B22A774-DFF4-4D2C-8E5D-8FBD66E47FC9' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '1B22A774-DFF4-4D2C-8E5D-8FBD66E47FC9' AND PullDrawing = 1;
PRINT '--- before 586335B9-10C1-4DB1-BB19-C92BE3317B10';
SELECT 'before' AS phase, '586335B9-10C1-4DB1-BB19-C92BE3317B10' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '586335B9-10C1-4DB1-BB19-C92BE3317B10' AND PullDrawing = 1;
PRINT '--- before 4148BB24-5634-47B4-BBDD-69083A819414';
SELECT 'before' AS phase, '4148BB24-5634-47B4-BBDD-69083A819414' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '4148BB24-5634-47B4-BBDD-69083A819414' AND PullDrawing = 1;
PRINT '--- before 193E7324-FE01-4C20-AAE0-CF33CD9BD8D4';
SELECT 'before' AS phase, '193E7324-FE01-4C20-AAE0-CF33CD9BD8D4' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '193E7324-FE01-4C20-AAE0-CF33CD9BD8D4' AND PullDrawing = 1;
PRINT '--- before 489A1353-874A-4041-BAA9-CCE1D433837E';
SELECT 'before' AS phase, '489A1353-874A-4041-BAA9-CCE1D433837E' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '489A1353-874A-4041-BAA9-CCE1D433837E' AND PullDrawing = 1;
PRINT '--- before 7C9B5785-372D-4DC3-BF12-1D9066C69EFF';
SELECT 'before' AS phase, '7C9B5785-372D-4DC3-BF12-1D9066C69EFF' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '7C9B5785-372D-4DC3-BF12-1D9066C69EFF' AND PullDrawing = 1;
SET STATISTICS IO, TIME OFF;
GO
SELECT p.* INTO #before_pbp FROM dbo.vwDrawingPullByPlant p JOIN #ids i ON i.id = p.TransactionID;
SELECT p.* INTO #before_dp FROM dbo.vwDrawingPull p JOIN #ids i ON i.id = p.TransactionID;
SELECT p.* INTO #before_dpf FROM dbo.vwDrawingPullFlag p JOIN #ids i ON i.id = p.TransactionID;
SELECT 'before' AS phase, (SELECT COUNT(*) FROM #before_pbp) pbp_rows, (SELECT COUNT(*) FROM #before_dp) dp_rows, (SELECT COUNT(*) FROM #before_dpf) dpf_rows;
GO
PRINT '===== ALTER VIEW =====';
GO

ALTER VIEW [dbo].[vwTpwpmChanges]
AS
SELECT DISTINCT
       tpwpm.TransactionID,
       tpwpm.AuthorID,
       tpwpm.ProjectID,
       tpwpm.WorksheetID,
       tpwpm.PartID,
       tpwpm.RevisionLevel,
       tpwpm.PieceNumber,
       CAST((CASE
                 WHEN tpwpm.MaterialID <> ISNULL(prev_tpwpm.MaterialID, '') THEN
                     1
                 ELSE
                     0
             END
            ) AS BIT) AS MaterialIDChanging,
       CAST((CASE
                 WHEN tpwpm.PieceName <> ISNULL(prev_tpwpm.PieceName, '') THEN
                     1
                 ELSE
                     0
             END
            ) AS BIT) AS PieceNameChanging,
       CAST((CASE
                 WHEN tpwpm.CutLength <> ISNULL(prev_tpwpm.CutLength, 0) THEN
                     1
                 ELSE
                     0
             END
            ) AS BIT) AS CutLengthChanging,
       CAST((CASE
                 WHEN tpwpm.PieceQty <> ISNULL(prev_tpwpm.PieceQty, 0) THEN
                     1
                 ELSE
                     0
             END
            ) AS BIT) AS PieceQtyChanging,
       CAST((CASE
                 WHEN tpwpm.Reference <> ISNULL(prev_tpwpm.Reference, '') THEN
                     1
                 ELSE
                     0
             END
            ) AS BIT) AS ReferenceChanging
FROM transfer.tblProjectWorksheetPartMaterial AS tpwpm
    JOIN transfer.tblProjectWorksheet AS tpw
        ON tpwpm.TransactionID = tpw.TransactionID
    LEFT JOIN dbo.vwProcessedWorksheets AS pw
        ON tpw.AuthorID = pw.AuthorID
           AND tpw.ProjectID = pw.ProjectID
           AND tpw.WorksheetID = pw.WorksheetID
           AND pw.RevisionLevel =
           (
               SELECT MAX(_pw.RevisionLevel) RevLevel
               FROM dbo.vwProcessedWorksheets _pw
               WHERE pw.AuthorID = _pw.AuthorID
                     AND pw.ProjectID = _pw.ProjectID
                     AND pw.WorksheetID = _pw.WorksheetID
                     AND tpw.TransactionID <> _pw.TransactionID
           )
           AND pw.ReleasedDate =
           (
               SELECT MAX(_pw.ReleasedDate) RevLevel
               FROM dbo.vwProcessedWorksheets _pw
               WHERE pw.AuthorID = _pw.AuthorID
                     AND pw.ProjectID = _pw.ProjectID
                     AND pw.WorksheetID = _pw.WorksheetID
                     AND pw.RevisionLevel = _pw.RevisionLevel
           )
    LEFT JOIN transfer.tblProjectWorksheetPartMaterial AS prev_tpwpm
        ON prev_tpwpm.PartID = tpwpm.PartID
           AND prev_tpwpm.PieceNumber = tpwpm.PieceNumber
           AND prev_tpwpm.TransactionID = pw.TransactionID
WHERE (
          prev_tpwpm.RevisionLevel IS NULL
          OR prev_tpwpm.RevisionLevel =
          (
              SELECT MAX(prev_tpwpm2.RevisionLevel) RevisionLevel
              FROM transfer.tblProjectWorksheetPartMaterial prev_tpwpm2
              WHERE prev_tpwpm.PartID = prev_tpwpm2.PartID
                    AND prev_tpwpm.PieceNumber = prev_tpwpm2.PieceNumber
                    AND prev_tpwpm.TransactionID = prev_tpwpm2.TransactionID
          )
      )
      AND (tpwpm.RevisionLevel =
          (
              SELECT MAX(tpwpm2.RevisionLevel) RevisionLevel
              FROM transfer.tblProjectWorksheetPartMaterial tpwpm2
              WHERE tpwpm.PartID = tpwpm2.PartID
                    AND tpwpm.TransactionID = tpwpm2.TransactionID
          )
          )
      AND tpwpm.PieceNumber NOT
      BETWEEN 90 AND 98;
GO
EXEC sp_refreshview 'dbo.vwDrawingPullByPlant';
EXEC sp_refreshview 'dbo.vwDrawingPull';
EXEC sp_refreshview 'dbo.vwDrawingPullFlag';
GO
PRINT '===== after - timed query-77 shape =====';
SET STATISTICS IO, TIME ON;
PRINT '--- after 1B22A774-DFF4-4D2C-8E5D-8FBD66E47FC9';
SELECT 'after' AS phase, '1B22A774-DFF4-4D2C-8E5D-8FBD66E47FC9' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '1B22A774-DFF4-4D2C-8E5D-8FBD66E47FC9' AND PullDrawing = 1;
PRINT '--- after 586335B9-10C1-4DB1-BB19-C92BE3317B10';
SELECT 'after' AS phase, '586335B9-10C1-4DB1-BB19-C92BE3317B10' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '586335B9-10C1-4DB1-BB19-C92BE3317B10' AND PullDrawing = 1;
PRINT '--- after 4148BB24-5634-47B4-BBDD-69083A819414';
SELECT 'after' AS phase, '4148BB24-5634-47B4-BBDD-69083A819414' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '4148BB24-5634-47B4-BBDD-69083A819414' AND PullDrawing = 1;
PRINT '--- after 193E7324-FE01-4C20-AAE0-CF33CD9BD8D4';
SELECT 'after' AS phase, '193E7324-FE01-4C20-AAE0-CF33CD9BD8D4' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '193E7324-FE01-4C20-AAE0-CF33CD9BD8D4' AND PullDrawing = 1;
PRINT '--- after 489A1353-874A-4041-BAA9-CCE1D433837E';
SELECT 'after' AS phase, '489A1353-874A-4041-BAA9-CCE1D433837E' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '489A1353-874A-4041-BAA9-CCE1D433837E' AND PullDrawing = 1;
PRINT '--- after 7C9B5785-372D-4DC3-BF12-1D9066C69EFF';
SELECT 'after' AS phase, '7C9B5785-372D-4DC3-BF12-1D9066C69EFF' AS tid, COUNT(*) AS pull_rows FROM dbo.vwDrawingPullByPlant WHERE TransactionID = '7C9B5785-372D-4DC3-BF12-1D9066C69EFF' AND PullDrawing = 1;
SET STATISTICS IO, TIME OFF;
GO
SELECT p.* INTO #after_pbp FROM dbo.vwDrawingPullByPlant p JOIN #ids i ON i.id = p.TransactionID;
SELECT p.* INTO #after_dp FROM dbo.vwDrawingPull p JOIN #ids i ON i.id = p.TransactionID;
SELECT p.* INTO #after_dpf FROM dbo.vwDrawingPullFlag p JOIN #ids i ON i.id = p.TransactionID;
SELECT 'after' AS phase, (SELECT COUNT(*) FROM #after_pbp) pbp_rows, (SELECT COUNT(*) FROM #after_dp) dp_rows, (SELECT COUNT(*) FROM #after_dpf) dpf_rows;
GO
PRINT '===== EXCEPT both directions (expect all 0) =====';
SELECT 'pbp' v, (SELECT COUNT(*) FROM (SELECT * FROM #before_pbp EXCEPT SELECT * FROM #after_pbp) x) before_minus_after,
                (SELECT COUNT(*) FROM (SELECT * FROM #after_pbp EXCEPT SELECT * FROM #before_pbp) x) after_minus_before
UNION ALL SELECT 'dp', (SELECT COUNT(*) FROM (SELECT * FROM #before_dp EXCEPT SELECT * FROM #after_dp) x),
                (SELECT COUNT(*) FROM (SELECT * FROM #after_dp EXCEPT SELECT * FROM #before_dp) x)
UNION ALL SELECT 'dpf', (SELECT COUNT(*) FROM (SELECT * FROM #before_dpf EXCEPT SELECT * FROM #after_dpf) x),
                (SELECT COUNT(*) FROM (SELECT * FROM #after_dpf EXCEPT SELECT * FROM #before_dpf) x);
SELECT o.modify_date,
       (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = o.object_id AND c.name = 'MaterialSubstituted') AS matsub,
       (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = o.object_id) AS total_cols,
       CONVERT(varchar(100), HASHBYTES('SHA2_256', OBJECT_DEFINITION(o.object_id)), 1) AS new_def_hash,
       LEFT(LTRIM(REPLACE(REPLACE(OBJECT_DEFINITION(o.object_id), CHAR(13), ''), CHAR(10), ' ')), 40) AS def_head
FROM sys.objects o WHERE o.object_id = OBJECT_ID('dbo.vwTpwpmChanges');
GO