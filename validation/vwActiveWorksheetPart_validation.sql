SET NOCOUNT ON;

SELECT TransactionID, PartID, GenieSplitID_c, OrderNumber, PartNumber, PartName, IsPhantom,
       GeniePartNum, EpiPartNum, ClassID, PullDrawing, IsHardware, PartExists
INTO #v
FROM GenieDev.dbo.vwActiveWorksheetPart;
CREATE INDEX ix1 ON #v (PartNumber);

SELECT '== SNAPSHOT ==' AS q, COUNT(*) AS total_rows FROM #v;

/* ---------- Q3 : match rate ----------
   NOTE: the old 'genie_differs' column (GeniePartNum vs PrevGeniePartNum) is GONE ON PURPOSE.
   It was a tautology and could never be non-zero -- PrevGeniePartNum's branch 1 read
   EpiPart.PartNum while EpiPart was joined ON the new key. See docs/HANDOFF §5. */
SELECT '== Q3 ==' AS q, COUNT(*) AS total,
       SUM(CASE WHEN EpiPartNum IS NOT NULL THEN 1 ELSE 0 END) AS matched,
       SUM(CASE WHEN GeniePartNum IS NULL THEN 1 ELSE 0 END) AS genie_null
FROM #v;

/* ---------- Q1 : now keyed LEN>4, so test the whole bare-keyed set ---------- */
SELECT '== Q1 counts ==' AS q,
  (SELECT COUNT(*) FROM #v v
     LEFT JOIN E10Test.dbo.Part  bare ON bare.Company='FUS' AND bare.PartNum = CONVERT(NVARCHAR, v.PartNumber)
     LEFT JOIN E10Test.dbo.Part  proj ON proj.Company='FUS' AND proj.PartNum = CONCAT(v.OrderNumber,'-',FORMAT(v.PartNumber,'00000'))
   WHERE LEN(v.PartNumber)>4 AND bare.PartNum IS NULL AND proj.PartNum IS NOT NULL) AS misrouted_E10Test_LIVE,
  (SELECT COUNT(*) FROM #v v
     LEFT JOIN E10Test2.dbo.Part bare ON bare.Company='FUS' AND bare.PartNum = CONVERT(NVARCHAR, v.PartNumber)
     LEFT JOIN E10Test2.dbo.Part proj ON proj.Company='FUS' AND proj.PartNum = CONCAT(v.OrderNumber,'-',FORMAT(v.PartNumber,'00000'))
   WHERE LEN(v.PartNumber)>4 AND bare.PartNum IS NULL AND proj.PartNum IS NOT NULL) AS misrouted_E10Test2_ASWRITTEN;

SELECT TOP 50 '== Q1 sample (E10Test LIVE) ==' AS q, v.OrderNumber, v.PartNumber, v.PartName,
       v.GeniePartNum, v.EpiPartNum, proj.PartNum AS project_form_exists
FROM #v v
LEFT JOIN E10Test.dbo.Part bare ON bare.Company='FUS' AND bare.PartNum = CONVERT(NVARCHAR, v.PartNumber)
LEFT JOIN E10Test.dbo.Part proj ON proj.Company='FUS' AND proj.PartNum = CONCAT(v.OrderNumber,'-',FORMAT(v.PartNumber,'00000'))
WHERE LEN(v.PartNumber)>4 AND bare.PartNum IS NULL AND proj.PartNum IS NOT NULL;

/* ---------- Q2 ---------- */
SELECT '== Q2 ==' AS q,
  (SELECT COUNT(*) FROM #v v JOIN E10Test.dbo.Part  p ON p.Company='FUS' AND p.PartNum=CONVERT(NVARCHAR,v.PartNumber) WHERE LEN(v.PartNumber)<=4) AS lost_E10Test_LIVE,
  (SELECT COUNT(*) FROM #v v JOIN E10Test2.dbo.Part p ON p.Company='FUS' AND p.PartNum=CONVERT(NVARCHAR,v.PartNumber) WHERE LEN(v.PartNumber)<=4) AS lost_E10Test2_ASWRITTEN;

SELECT '== Q2 breakdown ==' AS q,
       CASE WHEN v.EpiPartNum IS NULL THEN 'LOST match entirely' ELSE 'still matches (project form)' END AS outcome,
       COUNT(*) AS rows_
FROM #v v JOIN E10Test.dbo.Part p ON p.Company='FUS' AND p.PartNum=CONVERT(NVARCHAR,v.PartNumber)
WHERE LEN(v.PartNumber)<=4
GROUP BY CASE WHEN v.EpiPartNum IS NULL THEN 'LOST match entirely' ELSE 'still matches (project form)' END;

/* ---------- Q4 ---------- */
SELECT '== Q4 ==' AS q,
  (SELECT COUNT(*) FROM #v v JOIN E10Test.dbo.Part  p ON p.Company='FUS' AND p.PartNum=v.GeniePartNum WHERE ISNULL(p.Hardware_c,0)=1 AND LEN(v.PartNumber)<=4) AS newly_matched_hw_E10Test_LIVE,
  (SELECT COUNT(*) FROM #v v JOIN E10Test2.dbo.Part p ON p.Company='FUS' AND p.PartNum=v.GeniePartNum WHERE ISNULL(p.Hardware_c,0)=1 AND LEN(v.PartNumber)<=4) AS newly_matched_hw_E10Test2_ASWRITTEN;

/* ---------- NEW-CASE-SPECIFIC deltas ---------- */
-- D1: LEN>4 only differs from LEN=5 if 6+ digit part numbers exist
SELECT '== D1 len distribution ==' AS q, LEN(PartNumber) AS len_partnum, COUNT(*) AS rows_,
       SUM(CASE WHEN EpiPartNum IS NOT NULL THEN 1 ELSE 0 END) AS matched,
       MIN(PartNumber) AS min_pn, MAX(PartNumber) AS max_pn
FROM #v GROUP BY LEN(PartNumber) ORDER BY LEN(PartNumber);

-- D2: ELSE MaterialID vs ELSE NULL only differs when IsPhantom IS NULL
SELECT '== D2 isphantom null ==' AS q, COUNT(*) AS isphantom_null_rows FROM #v WHERE IsPhantom IS NULL;

-- D3: negative PartNumbers (LEN counts the minus sign)
SELECT '== D3 negative partnum ==' AS q, COUNT(*) AS negative_rows FROM #v WHERE PartNumber < 0;

-- D4: current flag distribution
SELECT '== D4 PullDrawing/IsHardware ==' AS q, PullDrawing, IsHardware, COUNT(*) AS rows_
FROM #v GROUP BY PullDrawing, IsHardware ORDER BY PullDrawing, IsHardware;

-- D5: unmatched rows by length, to characterise the remaining gap
SELECT '== D5 unmatched by len ==' AS q, LEN(PartNumber) AS len_partnum, COUNT(*) AS unmatched
FROM #v WHERE EpiPartNum IS NULL GROUP BY LEN(PartNumber) ORDER BY LEN(PartNumber);

/* ---------- D6 : duplicates on the key the app calls .Single() on (HANDOFF 6.1) ---------- */
SELECT '== D6 dup .Single() key ==' AS q,
       COUNT(*) AS dup_groups, SUM(n) AS dup_rows, COUNT(DISTINCT TransactionID) AS transactions
FROM (SELECT TransactionID, PartID, GenieSplitID_c, COUNT(*) AS n
      FROM #v GROUP BY TransactionID, PartID, GenieSplitID_c HAVING COUNT(*) > 1) x;

/* ---------- D7 : nondeterministic GeniePartNum on phantom multi-material parts (HANDOFF 6.2) ---------- */
SELECT '== D7 nondeterministic key ==' AS q,
       COUNT(*) AS affected_groups, SUM(n) AS affected_rows
FROM (SELECT TransactionID, PartID, GenieSplitID_c, COUNT(*) AS n
      FROM #v GROUP BY TransactionID, PartID, GenieSplitID_c
      HAVING COUNT(DISTINCT GeniePartNum) > 1) y;

DROP TABLE #v;
