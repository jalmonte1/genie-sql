/* GenieDev.dbo.vwTpwpmChanges - ROLLBACK: the definition BEFORE the MaterialSubstituted drop.
   Captured verbatim with OBJECT_DEFINITION() from FIC-SQL02 (sqlb) / GenieDev on 2026-10-19.
   Server modify_date it reflects: 2023-11-22 09:32:09.860 (13 columns).
   SHA2_256 of OBJECT_DEFINITION at capture:
     0x941CA59074D53B2A79C1C76B0B2418587020759C123D7969206AF3226D12A7E5
   Only CREATE VIEW -> ALTER VIEW was changed. The text between the GOs is byte-exact, so running
   this restores the original hash (SQL Server stores ALTER as CREATE). Valid as a PRODUCTION rollback
   only if the hash guard in deploy/FixGenieTpwpmChangesDeadColumn.sql passed.
   This comment sits in its own batch so it does not become part of the stored definition. */
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
                 WHEN
                 (
                     SELECT TOP (1)
                            PartNum
                     FROM epicor.JobMtl AS jm
                     WHERE tpwpm.AuthorID = jm.FPBAuthorID_c
                           AND tpwpm.ProjectID = jm.FPBProjectID_c
                           AND tpwpm.WorksheetID = jm.FPBWorksheetID_c
                           AND tpwpm.PartID = jm.FPBPartID_c
                           AND tpwpm.PieceNumber = jm.FPBPieceNumber_c
                           AND tpwpm.MaterialID = jm.PartNum
                 ) IS NULL THEN
                     1
                 ELSE
                     0
             END
            ) AS BIT) AS MaterialSubstituted,
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
