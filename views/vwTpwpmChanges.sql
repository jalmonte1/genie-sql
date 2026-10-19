/* dbo.vwTpwpmChanges - NEW definition: MaterialSubstituted dropped (dead column; its correlated
   TOP (1) into epicor.JobMtl was computed for every row because of the DISTINCT). Otherwise identical
   to views/vwTpwpmChanges_rollback.sql (one trailing blank line fewer).
   Server modify_date it reflects: GenieDev (FIC-SQL02) 2026-10-19 17:40:01.560 - applied there 2026-10-19.
   NOT applied on production (FIC-SQL01 Genie) as of 2026-10-19. 12 columns.
   SHA2_256 of the stored OBJECT_DEFINITION after apply:
     0x39DEA55A4F355C1EB9C341AAE5EEFED382108564D28F1757B0773662D6B3E7F8
   The text between the GOs is byte-exact with what GenieDev stored.
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
