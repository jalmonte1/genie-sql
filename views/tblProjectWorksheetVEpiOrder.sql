SELECT  dbo.tblProjectWorksheetPartV.TransactionID ,
        dbo.tblProjectWorksheetPartV.AuthorID ,
        dbo.tblProjectWorksheetPartV.ProjectID ,
        dbo.tblProjectWorksheetPartV.WorksheetID ,
        dbo.tblProjectWorksheetPartV.PartID ,
        dbo.tblProjectWorksheetPartV.RevisionLevel ,
        dbo.tblProjectWorksheetPartV.PartNumber ,
        ( CASE WHEN tblProjectWorksheetPartV.LineType = 'HARDWARE'
               THEN 'XXHardware'
               ELSE tblProjectWorksheetPartV.PartName
          END ) AS PartName ,
        dbo.tblProjectWorksheetPartV.PartDescription ,
        dbo.tblProjectWorksheetPartV.ColorID ,
        ( CASE WHEN tblProjectWorksheetPartV.LineType = 'HARDWARE' THEN 'HW'
               ELSE dbo.tblProjectWorksheetPartV.ProductID
          END ) AS ProductID ,
        dbo.tblProjectWorksheetPartV.ShopID ,
        ( CASE WHEN ISNULL(PartV.NetWeight, 0) > 0 THEN PartV.NetWeight
               ELSE dbo.tblProjectWorksheetPartV.UnitWeight
          END ) AS UnitWeight ,
        dbo.tblProjectWorksheetPartV.FromStock ,
        dbo.tblProjectWorksheetPartV.CatalogPartNumber ,
        ( CASE WHEN PhantomedPartsVEpiOrder.ReleasedQty IS NOT NULL
               THEN PhantomedPartsVEpiOrder.ReleasedQty
               ELSE dbo.tblProjectWorksheetPartV.ReleasedQty
          END ) AS ReleasedQty ,
        dbo.tblProjectWorksheetPartV.DrawingNumber ,
        dbo.tblProjectWorksheetPartV.IsProcessed ,
        dbo.tblProjectWorksheetPartV.IsPhantom ,
        dbo.tblProjectWorksheetPartV.MultiCompany ,
        dbo.tblProjectWorksheetPartV.LineType ,
        dbo.tblProjectWorksheetPartV.MaterialCost ,
        dbo.tblProjectWorksheetPartV.LaborCost ,
        dbo.OrderHeadV.Company ,
        dbo.OrderHeadV.OrderNum ,
        dbo.OrderRelV.OrderLine ,
        dbo.OrderRelV.OrderRelNum ,
        pp.PhaseID ,
        dbo.OrderRelV.OurReqQty ,
        dbo.OrderRelV.WBSPhaseID_c ,
        dbo.OrderRelV.ReqDate ,
        dbo.PORelV.PONum ,
        dbo.PORelV.POLine ,
        dbo.PORelV.PORelNum ,
        icorder.Company AS ExtCompany ,
        icorder.Plant AS ExtPlant ,
        icorder.OrderNum AS ICOrderNum ,
        icorder.OrderLine AS ICOrderLine ,
        icorder.OrderRelNum AS ICOrderRelNum ,
        ( CASE WHEN icorder.DropShip IS NULL THEN OrderRelV.DropShip
               ELSE icorder.DropShip
          END ) AS DropShip ,
        ( CASE WHEN icPlant.Plant IS NULL THEN PlantV.Plant
               ELSE icPlant.Plant
          END ) AS Plant ,
        ( CASE WHEN icPlant.Name IS NULL THEN PlantV.Name
               ELSE icPlant.Name
          END ) AS PlantName ,
        ( CASE WHEN icorder.WarehouseCode IS NULL THEN OrderRelV.WarehouseCode
               ELSE icorder.WarehouseCode
          END ) AS WarehouseCode ,
        ( CASE WHEN icorder.BuyToOrder IS NULL THEN OrderRelV.BuyToOrder
               ELSE icorder.BuyToOrder
          END ) AS BuyToOrder ,
        ( CASE WHEN icorder.Make IS NULL THEN OrderRelV.Make
               ELSE icorder.Make
          END ) AS Make ,
        ( CASE WHEN icJobProd.JobNum IS NULL THEN JobProdV.JobNum
               ELSE icJobProd.JobNum
          END ) AS JobNum ,
        ( CASE WHEN icJobHead.QtyCompleted IS NOT NULL
               THEN icJobHead.QtyCompleted
               WHEN JobHeadV.QtyCompleted IS NOT NULL
               THEN icJobHead.QtyCompleted
               ELSE 0
          END ) AS QtyCompleted ,
        ( CASE WHEN icJobProd.ShippedQty IS NOT NULL THEN icJobProd.ShippedQty
               WHEN JobProdV.ShippedQty IS NOT NULL THEN JobProdV.ShippedQty
               ELSE 0
          END )
        + ( CASE WHEN icorder.OurStockShippedQty IS NOT NULL
                 THEN icorder.OurStockShippedQty
                 WHEN OrderRelV.OurStockShippedQty IS NOT NULL
                 THEN OrderRelV.OurStockShippedQty
                 ELSE 0
            END ) AS ShippedQty ,
        dbo.PartV.PartNum AS EpiPart ,
        ( CASE WHEN ISNULL(PartV.PartNum, '') <> '' THEN PartV.PartNum
               ELSE ( CASE WHEN ISNULL(OrderRelV.PartNum, '') <> ''
                           THEN OrderRelV.PartNum
                           ELSE CAST(tblProjectWorksheetPartV.PartNumber AS NVARCHAR)
                      END )
          END ) AS PartNum ,
        PhantomedPart.PartNum AS PhantomedPart ,
        ( CASE WHEN tblProjectWorksheetPartV.PartDescription = ''
               THEN PartV.PartDescription
               ELSE tblProjectWorksheetPartV.PartDescription
          END ) AS PartDesc
FROM    dbo.tblProjectWorksheetPartV
        INNER JOIN dbo.tblProjectWorksheetVEpiOrder ON dbo.tblProjectWorksheetVEpiOrder.AuthorID = dbo.tblProjectWorksheetPartV.AuthorID
                                                       AND dbo.tblProjectWorksheetVEpiOrder.ProjectID = dbo.tblProjectWorksheetPartV.ProjectID
                                                       AND dbo.tblProjectWorksheetVEpiOrder.WorksheetID = dbo.tblProjectWorksheetPartV.WorksheetID
                                                       AND dbo.tblProjectWorksheetVEpiOrder.TransactionID = dbo.tblProjectWorksheetPartV.TransactionID
        LEFT OUTER JOIN dbo.PhantomedPartsVEpiOrder ON dbo.PhantomedPartsVEpiOrder.AuthorID = dbo.tblProjectWorksheetPartV.AuthorID
                                                       AND dbo.PhantomedPartsVEpiOrder.ProjectID = dbo.tblProjectWorksheetPartV.ProjectID
                                                       AND dbo.PhantomedPartsVEpiOrder.WorksheetID = dbo.tblProjectWorksheetPartV.WorksheetID
                                                       AND dbo.PhantomedPartsVEpiOrder.PartID = dbo.tblProjectWorksheetPartV.PartID
                                                       AND dbo.PhantomedPartsVEpiOrder.RevisionLevel = dbo.tblProjectWorksheetPartV.RevisionLevel
                                                       AND dbo.PhantomedPartsVEpiOrder.TransactionID = dbo.tblProjectWorksheetPartV.TransactionID
        LEFT OUTER JOIN dbo.OrderRelV ON dbo.tblProjectWorksheetPartV.AuthorID = dbo.OrderRelV.AuthorID_c
                                         AND dbo.tblProjectWorksheetPartV.ProjectID = dbo.OrderRelV.ProjectID_c
                                         AND dbo.tblProjectWorksheetPartV.WorksheetID = dbo.OrderRelV.WorksheetID_c
                                         AND dbo.OrderRelV.PartID_c = dbo.tblProjectWorksheetPartV.PartID
                                         AND dbo.OrderRelV.Linked = 0
        LEFT OUTER JOIN dbo.OrderHeadV ON dbo.tblProjectWorksheetPartV.AuthorID = dbo.OrderHeadV.FPBAuthorID_c
                                          AND dbo.OrderHeadV.FPBProjectID_c = dbo.tblProjectWorksheetPartV.ProjectID
                                          AND dbo.OrderHeadV.Linked = 0
        LEFT OUTER JOIN E10DEV_THREE.dbo.ProjPhase AS pp ON dbo.OrderRelV.WBSPhaseID_c = pp.PhaseID
                                                             AND pp.ProjectID = CONVERT(NVARCHAR(8), dbo.OrderRelV.OrderNum)
        LEFT OUTER JOIN dbo.PlantV ON dbo.PlantV.Plant = dbo.OrderRelV.Plant
                                      AND dbo.PlantV.Company = dbo.OrderRelV.Company
        LEFT OUTER JOIN dbo.JobProdV ON dbo.JobProdV.Company = dbo.OrderRelV.Company
                                        AND dbo.JobProdV.OrderNum = dbo.OrderRelV.OrderNum
                                        AND dbo.JobProdV.OrderLine = dbo.OrderRelV.OrderLine
                                        AND dbo.JobProdV.OrderRelNum = dbo.OrderRelV.OrderRelNum
        LEFT OUTER JOIN dbo.JobHeadV ON dbo.JobHeadV.Company = dbo.JobProdV.Company
                                        AND dbo.JobHeadV.JobNum = dbo.JobProdV.JobNum
        LEFT OUTER JOIN dbo.PartV AS PhantomedPart ON PhantomedPart.Company = 'FUS'
                                                      AND PhantomedPart.PartNum = CAST(dbo.PhantomedPartsVEpiOrder.MaterialID AS NVARCHAR)
        LEFT OUTER JOIN dbo.PartV ON dbo.PartV.Company = 'FUS'
                                     AND dbo.PartV.PartNum = CAST(dbo.tblProjectWorksheetPartV.PartNumber AS NVARCHAR)
        LEFT OUTER JOIN dbo.PORelV ON dbo.PORelV.Company = dbo.OrderRelV.Company
                                      AND dbo.PORelV.PONum = dbo.OrderRelV.PONum
                                      AND dbo.PORelV.POLine = dbo.OrderRelV.POLine
                                      AND dbo.PORelV.PORelNum = dbo.OrderRelV.OrderRelNum
        LEFT OUTER JOIN dbo.OrderRelV AS icorder ON icorder.Company = dbo.PORelV.ExtCompany
                                                    AND icorder.OrderNum = dbo.PORelV.OrderNum
                                                    AND icorder.OrderLine = dbo.PORelV.OrderLine
                                                    AND icorder.OrderRelNum = dbo.PORelV.OrderRelNum
                                                    AND icorder.Linked = 1
        LEFT OUTER JOIN dbo.PlantV AS icPlant ON icorder.Company = icPlant.Company
                                                 AND icorder.Plant = icPlant.Plant
        LEFT OUTER JOIN dbo.JobProdV AS icJobProd ON icJobProd.Company = icorder.Company
                                                     AND icJobProd.OrderNum = icorder.OrderNum
                                                     AND icJobProd.OrderLine = icorder.OrderLine
                                                     AND icJobProd.OrderRelNum = icorder.OrderRelNum
        LEFT OUTER JOIN dbo.JobHeadV AS icJobHead ON icJobHead.Company = icJobProd.Company
                                                     AND icJobHead.JobNum = icJobProd.JobNum
WHERE   ( dbo.tblProjectWorksheetPartV.MultiCompany = 0 )
        AND ( dbo.tblProjectWorksheetPartV.RevisionLevel = ( SELECT
                                                              MAX(RevisionLevel) AS Expr1
                                                             FROM
                                                              dbo.tblProjectWorksheetPartV
                                                              AS sub
                                                             WHERE
                                                              ( dbo.tblProjectWorksheetPartV.AuthorID = AuthorID )
                                                              AND ( dbo.tblProjectWorksheetPartV.ProjectID = ProjectID )
                                                              AND ( dbo.tblProjectWorksheetPartV.WorksheetID = WorksheetID )
                                                           ) )
        AND ( ( CASE WHEN ISNULL(PartV.PartNum, '') <> '' THEN PartV.PartNum
                     ELSE ( CASE WHEN ISNULL(OrderRelV.PartNum, '') <> ''
                                 THEN OrderRelV.PartNum
                                 ELSE ( CASE WHEN tblProjectWorksheetPartV.IsPhantom = 1
                                             THEN PhantomedPartsVEpiOrder.MaterialID
                                             ELSE ''
                                        END )
                            END )
                END ) IS NOT NULL );