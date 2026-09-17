/* GenieDev.dbo.vwActiveWorksheetPart — reconstruction of the definition applied
   manually by JAlmonte. Server modify_date of the deployment this reflects:
   2026-09-16 22:02:33.

   HOW MUCH OF THIS IS VERIFIED
   ----------------------------
   claude_readonly lacks VIEW DEFINITION on this object, so OBJECT_DEFINITION()
   returns NULL and the live text CANNOT be re-scripted from the server. This file
   is hand-maintained and is the ONLY written copy. Treat it accordingly:

   * The GeniePartNum CASE (and the identical epicor.Part join predicate) below
     were updated on 2026-09-16 to the deployed logic: LEN(PartNumber) > 4 for
     branch 1, and a plain ELSE tpwpm.MaterialID tail. Branch-by-branch behavioural
     conformance against the live view is proven: 7,630/7,630 rows on branch 1,
     12,375/12,375 on branch 2, 254/254 on the MaterialID branch, 0 exceptions.
   * ALIAS CAVEAT: the deployed snippet was supplied using aliases `wp` (part) and
     `w` (worksheet); this file uses `rp` and `tpw` throughout. The logic is the
     same, the alias spellings may not be. The rest of the FROM/JOIN block has NOT
     been verified against the live definition.
   * The executed plan touches base tables that appear nowhere below — Vendor, Wish,
     tblProjectWorksheetHardware — presumably via the nested views vwReleasedPart /
     vwDrawingPullFlag. So this file is known to be incomplete, not merely unverified.
   * PrevGeniePartNum (below) is a diagnostic column slated for removal by JAlmonte.
     It is NOT a faithful replay of the pre-change value and its A/B comparison is a
     tautology — see docs/HANDOFF_vwActiveWorksheetPart.md §5.

   Granting VIEW DEFINITION ON OBJECT::dbo.vwActiveWorksheetPart TO claude_readonly
   would remove the need for this file to be maintained by hand. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER VIEW dbo.vwActiveWorksheetPart
AS
SELECT rp.TransactionID,
       rp.AuthorID,
       rp.ProjectID,
       rp.WorksheetID,
       rp.PartID,
       rp.RevisionLevel,
       ISNULL(rel.GenieSplitID_c, 0) AS GenieSplitID_c,
       rp.PartNumber AS OrigPartNumber,
       rp.PartNumber,
       -- RESOLVED KEY (new): also used verbatim as the EpiPart join predicate below.
       CASE
           WHEN LEN(rp.PartNumber) > 4 THEN
               CONVERT(NVARCHAR, rp.PartNumber)
           WHEN rp.IsPhantom = 0
                OR tpwpm.MaterialID = '13619' THEN
               CONCAT(LTRIM(RTRIM(tpw.OrderNumber)), '-', FORMAT(rp.PartNumber, '00000'))
           ELSE
               tpwpm.MaterialID
       END AS GeniePartNum,
       -- Diagnostic column: the OLD GeniePartNum CASE, retained for A/B comparison.
       -- CAVEAT: its branch 1 reads EpiPart.PartNum, and EpiPart is now joined on the
       -- NEW key, so this is NOT a faithful replay of the pre-change value.
       CASE
           WHEN EpiPart.PartNum IS NOT NULL
                AND LEN(EpiPart.PartNum) > 4 THEN
               EpiPart.PartNum
           WHEN rp.PartNumber
                BETWEEN 90000 AND 99999 THEN
               FORMAT(rp.PartNumber, '00000')
           WHEN rp.IsPhantom = 0
                OR tpwpm.MaterialID = '13619' THEN
               CONCAT(LTRIM(RTRIM(tpw.OrderNumber)), '-', FORMAT(rp.PartNumber, '00000'))
           ELSE
               tpwpm.MaterialID
       END AS PrevGeniePartNum,
       rp.PartName,
       rp.PartDescription,
       rp.ColorID,
       rp.ProductID,
       rp.ShopID,
       rp.UnitWeight,
       rp.FromStock,
       rp.IsPhantom,
       rp.CatalogPartNumber,
       rp.ReleasedQty,
       rp.DrawingNumber,
       rp.PartProductionCode1,
       rp.PartProductionCode2,
       rp.MaterialCost,
       rp.LaborCost,
       rp.IsProcessed,
       rp.SetupCost,
       rp.IsProcessing,
       rp.ShortDescriptionOverride,
       rp.LongDescriptionOverride,
       rp.UnitWeightOverride,
       rp.MaterialCostOverride,
       rp.SetupCostOverride,
       rp.RunCostOverride,
       rp.PaintMaterialCostOverride,
       rp.PaintLaborCostOverride,
       rp.MaterialDetailOverride,
       rp.LaborDetailOverride,
       rp.PartProperties,
       CAST((CASE
                 WHEN rp.ShortDescriptionOverride = 1
                      OR rp.LongDescriptionOverride = 1
                      OR rp.UnitWeightOverride = 1
                      OR rp.MaterialCostOverride = 1
                      OR rp.SetupCostOverride = 1
                      OR rp.RunCostOverride = 1
                      OR rp.PaintMaterialCostOverride = 1
                      OR rp.PaintLaborCostOverride = 1
                      OR rp.MaterialDetailOverride = 1
                      OR rp.LaborDetailOverride = 1 THEN
                     1
                 ELSE
                     0
             END
            ) AS BIT) AS ContainsOverride,
       tpw.CCN,
       CAST(tpw.OrderNumber AS INT) AS OrderNumber,
       tpw.WorksheetNumber,
       rel.Company,
       rel.OrderNum,
       rel.OrderLine,
       rel.OrderRelNum,
       rel.Plant,
       rel.OurReqQty,
       rel.ReqDate,
       rel.NeedByDate,
       poRel.PONum,
       poRel.POLine,
       poRel.PORelNum,
       poRel.RelQty,
       poh.ICPOLocked,
       icRel.Company AS ExtCompany,
       icRel.Plant AS ExtPlant,
       ISNULL(icRel.Plant, rel.Plant) AS ProcessingPlant,
       icRel.OrderNum AS IcOrderNum,
       icRel.OrderLine AS icOrderLine,
       icRel.OrderRelNum AS IcOrderRelNum,
       icRel.OurReqQty AS ICOurReqQty,
       (CASE WHEN poRel.Linked = 0 THEN poRel.Company ELSE icPoRel.Company END) AS LinkedPOCompany,
       (CASE WHEN poRel.Linked = 0 THEN poRel.PONum ELSE icPoRel.PONum END) AS LinkedPONum,
       (CASE WHEN poRel.Linked = 0 THEN poRel.POLine ELSE icPoRel.POLine END) AS LinkedPOLine,
       (CASE WHEN poRel.Linked = 0 THEN poRel.PORelNum ELSE icPoRel.PORelNum END) AS LinkedPORelNum,
       jobPo.Company AS JobPoCompany,
       jobPo.PONum AS JobPO,
       jobPo.POLine AS JobPOLine,
       jobPo.PORelNum AS JobPORelNum,
       jobPo.Plant AS JobPOPlant,
       CONVERT(BIT, IIF(EpiPart.PartNum IS NOT NULL, 1, 0)) AS PartExists,
       rp.LineType,
       ISNULL(icRel.Make, rel.Make) AS Make,
       ISNULL(icRel.BuyToOrder, rel.BuyToOrder) AS BuyToOrder,
       ISNULL(icRel.DropShip, rel.DropShip) AS DropShip,
       plnt.PlantShortName_c,
       plnt.OldPlantNumber_c,
       ISNULL(icRel.WarehouseCode, rel.WarehouseCode) AS WarehouseCode,
       job.JobNum,
       job.JobClosed,
       CASE
           WHEN ISNULL(job.QtyCompleted, 0) > ISNULL(assemQty.AssembledQty, 0) THEN
               ISNULL(job.QtyCompleted, 0)
           ELSE
               ISNULL(assemQty.AssembledQty, 0)
       END AS QtyCompleted,
       ISNULL(
                 ISNULL(icRel.OurStockShippedQty, rel.OurStockShippedQty)
                 + ISNULL(icRel.OurJobShippedQty, rel.OurJobShippedQty),
                 0
             ) AS ShippedQty,
       rel.GenieSelectedPlan_c,
       dtl.PartNum AS PartNum,
       EpiPart.PartNum AS EpiPartNum,
       EpiPart.Drawing_c AS EpiPartDrawing,
       EpiPart.ClassID,
       EpiPart.Stocked_c,
       CAST((CASE
                 WHEN ISNULL(EpiPart.Hardware_c, 0) = 0 THEN
       (CASE
            WHEN dtl.OrderLine IS NULL THEN
                1
            ELSE
                ISNULL(pf.PullDrawing, 1)
        END
       )
                 ELSE
                     0
             END
            ) AS BIT) AS PullDrawing,
       CONVERT(   BIT,
                  CASE
                      WHEN tpw.AuthorID = '__' THEN
                          ISNULL(EpiPart.Hardware_c, 0)
                      ELSE
                  (CASE
                       WHEN rp.ProductID = 'HW' THEN
                           1
                       ELSE
                           0
                   END
                  )
                  END
              ) AS IsHardware,
       ISNULL(rp.SyncStatus, '') AS SyncStatus,
       job.SourceJobNum_c,
       ISNULL(assemQty.AssembledQty, 0) AS AssembledQty,
       CONCAT(rp.TransactionID, '-', rp.PartID, ISNULL(rel.GenieSplitID_c, 0)) AS PartKey
FROM transfer.tblProjectWorksheet AS tpw
    INNER JOIN dbo.vwReleasedPart AS rp
        ON tpw.TransactionID = rp.TransactionID
    LEFT OUTER JOIN dbo.vwDrawingPullFlag AS pf
        ON pf.TransactionID = rp.TransactionID
           AND pf.PartID = rp.PartID
    LEFT OUTER JOIN transfer.tblProjectWorksheetPartMaterial AS tpwpm
        ON tpwpm.TransactionID = rp.TransactionID
           AND tpwpm.PartID = rp.PartID
           AND tpwpm.RevisionLevel = rp.RevisionLevel
           AND
           (
               tpwpm.PieceNumber < 90
               OR tpwpm.PieceNumber > 99
           )
           AND rp.IsPhantom = 1
    -- THE CHANGE: single join, keyed on the resolved-key CASE (no self-reference).
    LEFT OUTER JOIN epicor.Part AS EpiPart
        ON EpiPart.Company = 'FUS'
           AND EpiPart.PartNum = CASE
                                     WHEN LEN(rp.PartNumber) > 4 THEN
                                         CONVERT(NVARCHAR, rp.PartNumber)
                                     WHEN rp.IsPhantom = 0
                                          OR tpwpm.MaterialID = '13619' THEN
                                         CONCAT(LTRIM(RTRIM(tpw.OrderNumber)), '-', FORMAT(rp.PartNumber, '00000'))
                                     ELSE
                                         tpwpm.MaterialID
                                 END
    --AND EpiPart.PartNum = CAST(rp.PartNumber AS NVARCHAR)   -- previous (bare numeric) key
    LEFT OUTER JOIN epicor.OrderRel AS rel
        ON rel.Company = tpw.CCN
           AND rel.FPBAuthorID_c = rp.AuthorID
           AND rel.FPBProjectID_c = rp.ProjectID
           AND rel.FPBWorksheetID_c = rp.WorksheetID
           AND rel.FPBPartID_c = rp.PartID
    LEFT OUTER JOIN epicor.OrderDtl AS dtl
        ON dtl.Company = rel.Company
           AND dtl.OrderNum = rel.OrderNum
           AND dtl.OrderLine = rel.OrderLine
    LEFT OUTER JOIN epicor.PORel AS poRel
        ON poRel.Company = rel.Company
           AND poRel.BTOOrderNum = rel.OrderNum
           AND poRel.BTOOrderLine = rel.OrderLine
           AND poRel.BTOOrderRelNum = rel.OrderRelNum
    LEFT OUTER JOIN epicor.POHeader AS poh
        ON poh.Company = poRel.Company
           AND poh.PONum = poRel.PONum
    LEFT OUTER JOIN epicor.OrderRel AS icRel
        ON icRel.ExtCompany = poRel.Company
           AND icRel.ICPONum = poRel.PONum
           AND icRel.ICPOLine = poRel.POLine
           AND icRel.ICPORelNum = poRel.PORelNum
    LEFT OUTER JOIN epicor.JobHead AS job
        ON job.Company = ISNULL(icRel.Company, rel.Company)
           AND job.OrderNum_c = ISNULL(icRel.OrderNum, rel.OrderNum)
           AND job.OrderLine_c = ISNULL(icRel.OrderLine, rel.OrderLine)
           AND job.OrderRelNum_c = ISNULL(icRel.OrderRelNum, rel.OrderRelNum)
    LEFT OUTER JOIN epicor.JobOper AS jobOp
        ON jobOp.Company = job.Company
           AND jobOp.JobNum = job.JobNum
           AND jobOp.PartNum = dtl.PartNum
           AND jobOp.OpCode LIKE '%WORK'
    LEFT OUTER JOIN epicor.PORel AS jobPo
        ON jobPo.Company = jobOp.Company
           AND jobPo.JobNum = jobOp.JobNum
           AND jobPo.TranType = 'PUR-SUB'
    LEFT OUTER JOIN epicor.PORel AS icPoRel
        ON icPoRel.Company = icRel.Company
           AND icPoRel.BTOOrderNum = icRel.OrderNum
           AND icPoRel.BTOOrderLine = icRel.OrderLine
           AND icPoRel.BTOOrderRelNum = icRel.OrderRelNum
    LEFT OUTER JOIN epicor.Plant AS plnt
        ON plnt.Company = ISNULL(icRel.Company, rel.Company)
           AND plnt.Plant = ISNULL(icRel.Plant, rel.Plant)
    LEFT OUTER JOIN epicor.vwIntercompanyOrderNumbers AS icon
        ON icon.OrderNum = CAST(tpw.OrderNumber AS INT)
           AND icon.ICOrderNum2 IS NOT NULL
    LEFT OUTER JOIN mes.vwAssembledQuantities AS assemQty
        ON assemQty.JobNum = job.JobNum
WHERE (
          rp.RevisionLevel =
      (
          SELECT MAX(tpwp2.RevisionLevel) AS Expr1
          FROM transfer.tblProjectWorksheetPart AS tpwp2
          WHERE (tpwp2.TransactionID = rp.TransactionID)
                AND (tpwp2.PartID = rp.PartID)
      )
          OR rp.LineType = 'HARDWARE'
      )
      AND tpw.IsProcessed = 0;
GO
