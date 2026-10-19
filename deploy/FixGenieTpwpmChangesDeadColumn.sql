/* FixGenieTpwpmChangesDeadColumn.sql - drop the dead MaterialSubstituted column from dbo.vwTpwpmChanges.
   For JAlmonte to run PERSONALLY on FIC-SQL01 / Genie, in plain SSMS (no SQLCMD mode needed).
   Validated on GenieDev (FIC-SQL02) 2026-10-19: 0 rows merged over the whole view (958,332), before/after
   EXCEPT 0/0 on vwDrawingPullByPlant, vwDrawingPull, vwDrawingPullFlag; JobMtl reads gone.
   Run at a quiet moment: ALTER VIEW takes a brief Sch-M lock and can queue behind an in-flight
   35-55 s drawing-pull query.

   GUARD: aborts unless the server is FIC-SQL01 AND production's current view text hashes to the same
   value as GenieDev's pre-change text (captured 2026-10-19). A mismatch may be only whitespace -
   DIFF production's definition against views/vwTpwpmChanges_rollback.sql before overriding the guard.
   Do not just delete the guard. views/vwTpwpmChanges_rollback.sql is a valid prod rollback only if
   the guard passed. The last SELECT confirms prod now holds exactly GenieDev's new text.

   Afterwards, query_id 77 keeps its id; compare its runtime stats before/after the change:
     SELECT rsi.start_time, p.plan_id, rs.count_executions,
            CAST(rs.avg_duration/1000.0 AS decimal(18,1)) AS avg_ms, CAST(rs.avg_logical_io_reads AS bigint) AS avg_reads
     FROM sys.query_store_plan p
     JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
     JOIN sys.query_store_runtime_stats_interval rsi ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
     WHERE p.query_id = 77 ORDER BY rsi.start_time DESC;
*/
USE [Genie];
GO
IF @@SERVERNAME NOT LIKE '%FIC-SQL01%'
   OR HASHBYTES('SHA2_256', OBJECT_DEFINITION(OBJECT_ID('dbo.vwTpwpmChanges'))) <> 0x941CA59074D53B2A79C1C76B0B2418587020759C123D7969206AF3226D12A7E5
BEGIN
    RAISERROR('Wrong server, or production definition differs from GenieDev - diff before applying.', 16, 1);
    SET NOEXEC ON;   -- persists across GO, so the ALTER below never runs
END
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
SET NOEXEC OFF;
GO
SELECT COUNT(*) AS matsub_should_be_0 FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.vwTpwpmChanges') AND name = 'MaterialSubstituted';
SELECT COUNT(*) AS total_cols_should_be_12 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.vwTpwpmChanges');
SELECT CASE WHEN HASHBYTES('SHA2_256', OBJECT_DEFINITION(OBJECT_ID('dbo.vwTpwpmChanges'))) = 0x39DEA55A4F355C1EB9C341AAE5EEFED382108564D28F1757B0773662D6B3E7F8
            THEN 'MATCHES GenieDev' ELSE 'DIFFERS from GenieDev - investigate' END AS new_definition_check;
GO
