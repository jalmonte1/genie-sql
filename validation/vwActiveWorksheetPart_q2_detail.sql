SET NOCOUNT ON;
SELECT OrderNumber, PartNumber, PartName, GeniePartNum, EpiPartNum, IsHardware, PullDrawing
INTO #v FROM GenieDev.dbo.vwActiveWorksheetPart;

/* The 41 rows Q2 flags: LEN<>5 but a bare Epicor part DOES exist.
   Did they actually lose the match, or just re-point to the project form? */
SELECT '== Q2 breakdown ==' AS q,
       CASE WHEN v.EpiPartNum IS NULL THEN 'LOST match entirely'
            ELSE 'still matches (re-pointed to project form)' END AS outcome,
       COUNT(*) AS rows_
FROM #v v
JOIN E10Test.dbo.Part p ON p.Company='FUS' AND p.PartNum = CONVERT(NVARCHAR, v.PartNumber)
WHERE LEN(v.PartNumber) <> 5
GROUP BY CASE WHEN v.EpiPartNum IS NULL THEN 'LOST match entirely'
              ELSE 'still matches (re-pointed to project form)' END;

SELECT TOP 50 '== Q2 rows ==' AS q, v.OrderNumber, v.PartNumber, v.PartName,
       v.GeniePartNum, v.EpiPartNum AS now_matches,
       p.PartNum AS bare_part_exists, p.PartDescription AS bare_desc,
       ISNULL(p.Hardware_c,0) AS bare_hw
FROM #v v
JOIN E10Test.dbo.Part p ON p.Company='FUS' AND p.PartNum = CONVERT(NVARCHAR, v.PartNumber)
WHERE LEN(v.PartNumber) <> 5
ORDER BY v.EpiPartNum, v.OrderNumber, v.PartNumber;
DROP TABLE #v;
