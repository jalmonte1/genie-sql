SELECT *
INTO #worksheet
FROM dbo.vwWorksheet;


SELECT *
INTO #worksheetPart
FROM dbo.vwWorksheetPart
WHERE EXISTS
(
    SELECT *
    FROM #worksheet AS w
    WHERE w.TransactionID = vwWorksheetPart.TransactionID
);

SELECT *
FROM #worksheet AS w
    JOIN #worksheetPart AS wp
        ON w.TransactionID = wp.TransactionID

--WHERE w.TransactionID = '7c146a9c-1e3f-4896-adfc-90a05f948c4a';
WHERE wp.IsHardware <> CONVERT(BIT, IIF(wp.LineType = 'HARDWARE', 1, 0))
      AND wp.LineType = 'HARDWARE'
      AND w.AuthorID = '__'
ORDER BY w.ReleasedDate DESC,
         w.OrderNumber,
         w.WorksheetNumber,
         w.RevisionLevel,
         wp.PartNumber;
