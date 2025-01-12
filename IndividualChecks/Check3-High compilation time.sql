/*
Check3 - High query plan compilation time
Description:
Check 3 - Do I have plans with high compilation time due to an auto update/create stats?
Check if statistic used in a query plan caused a long query plan compilation and optimization time.
If last update timestamp of statistic is close to the query plan creation time, then, it is very likely that the update/create stat caused a higher query plan creation duration.
Estimated Benefit:
High
Estimated Effort:
High
Recommendation:
Quick recommendation:
Review queries with high compilation due to auto update/create statistic.
Detailed recommendation:
- If this is happening, I recommend to enable auto update stats asynchronous option. With asynchronous statistics updates, queries compile with existing statistics even if the existing statistics are out-of-date. The Query Optimizer could choose a suboptimal query plan if statistics are out-of-date when the query compiles. Statistics are typically updated soon thereafter and queries that compile after the stats updates complete will benefit from using the updated statistics. 
- Another option to avoid the high compilation time is to deal with case by case and update the statistic causing the problem using no_recompute, then create a job to update it manually and don't rely on auto update stat. 
- Check if statistic causing high compilation time is new, if so, it may be an auto created stat and not auto updated, avoid those cases are harder as there is no easy way to disable auto update stats for a specific table/column. An option you have is to pre-create the statistic with no_recompute and update it using a job.
- If problem is happening with an important query that you need achieve a more predictable query response time, consider to use OPTION (KEEPFIXED PLAN) query hint.
Note 1: Keep in mind that this check is an attempt to identify those cases based on what we've in the plan cache. Ideally, if you want to identify all those cases you may want to create an extended event to capture sqlserver.auto_stats event with duration > 0 (or maybe 100ms). In my opinion, use the extended event is a safer and a good practice.

Note 2: https://techcommunity.microsoft.com/t5/azure-sql/diagnostic-data-for-synchronous-statistics-update-blocking/ba-p/386280 

Note 3: Ideally, this check should be executed several hours after the maintenance plan, as the idea is to capture long plan compilations due to the auto update/create stats.

*/

-- Fabiano Amorim
-- http:\\www.blogfabiano.com | fabianonevesamorim@hotmail.com
SET NOCOUNT ON; 
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/* Preparing tables with statistic info */
EXEC sp_GetStatisticInfo @database_name_filter = N'', @refreshdata = 0

IF OBJECT_ID('dbo.tmpStatisticCheck3') IS NOT NULL
  DROP TABLE dbo.tmpStatisticCheck3

IF OBJECT_ID('tempdb.dbo.#tmp1') IS NOT NULL
  DROP TABLE #tmp1

;WITH XMLNAMESPACES('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS p)
SELECT  qp.*,
        associated_stats_update_datetime = (SELECT TOP 1 CONVERT(VARCHAR, a.last_updated, 21)
                                            FROM dbo.tmpStatisticCheck_stats AS a
                                            WHERE a.last_updated >= exec_plan_creation_start_datetime
                                            ORDER BY a.last_updated ASC),
        /* Creation time plus the compilation time in milliseconds is the datetime the plan finished to compile */
        exec_plan_creation_end_datetime = CONVERT(VARCHAR, DATEADD(ms, x.value('sum(..//p:QueryPlan/@CompileTime)', 'float'), exec_plan_creation_start_datetime), 21),
        associated_stats_name = (SELECT TOP 1 a.stats_name
                                 FROM dbo.tmpStatisticCheck_stats AS a
                                 WHERE a.last_updated >= exec_plan_creation_start_datetime
                                 ORDER BY a.last_updated ASC),
        statistic_associated_with_compile = (SELECT TOP 1
                                                    'Statistic ' + a.stats_name + 
                                                    ' on table ' + a.database_name + '.' + a.table_name + ' ('+ CONVERT(VARCHAR, a.current_number_of_rows) +' rows)' +
                                                    ' was updated about the same time (' + CONVERT(VARCHAR, a.last_updated, 21) + ') that the plan was created, that may be the reason of the high compile time.'
                                             FROM dbo.tmpStatisticCheck_stats AS a
                                             WHERE a.last_updated >= exec_plan_creation_start_datetime
                                             ORDER BY a.last_updated ASC)
INTO #tmp1
FROM dbo.tmpStatsCheckCachePlanData qp
OUTER APPLY statement_plan.nodes('//p:Batch') AS Batch(x)
WHERE x.value('sum(..//p:QueryPlan/@CompileTime)', 'float') >= 200 /* Only plans taking more than 200ms to create */
OPTION (RECOMPILE);

SELECT 'Check 3 - Do I have plans with high compilation time due to an auto update/create stats?' AS [info], 
       * 
INTO dbo.tmpStatisticCheck3
FROM #tmp1
WHERE 1=1
/* 
   Adding 50ms on exec_plan_creation_end_datetime because I've seen some cases where there 
   was a small diff between the last update stats datetime and the time it took to create 
   the plan. Maybe due to a rounding issue? Anyway, add 50ms should be enough to fix this.
*/
AND associated_stats_update_datetime <= DATEADD(ms, 50, exec_plan_creation_end_datetime)
AND CONVERT(VarChar(MAX), statement_plan) COLLATE Latin1_General_BIN2 LIKE '%' + REPLACE(REPLACE(associated_stats_name, '[', ''), ']', '') + '%'
/* OR associated_stats_name IS NULL */ -- Uncomment this if you want to see info about all plans, I mean, including plans where an associated stat was not found

SELECT * FROM dbo.tmpStatisticCheck3
ORDER BY compile_time_sec DESC

/*
  Script to test the check:

USE Northwind
GO
IF OBJECT_ID('TabTestStats') IS NOT NULL
  DROP TABLE TabTestStats
GO
CREATE TABLE TabTestStats (ID Int IDENTITY(1,1) PRIMARY KEY,
                   Col1 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())),  5)) ,
                   Col2 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())),  5)) ,
                   Col3 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())),  5)) ,
                   Col4 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())),  5)) ,
                   Col5 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())),  5)) ,
                   Col6 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())),  5)) ,
                   Col7 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())),  5)) ,
                   Col8 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())),  5)) ,
                   Col9 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())),  5)) ,
                   Col10 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col11 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col12 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col13 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col14 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col15 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col16 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col17 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col18 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col19 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col20 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col21 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col22 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col23 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col24 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col25 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col26 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col27 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col28 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col29 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col30 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col31 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col32 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col33 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col34 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col35 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col36 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col37 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col38 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col39 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col40 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col41 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col42 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col43 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col44 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col45 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col46 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col47 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col48 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col49 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5)) ,
                   Col50 VarBinary(MAX) DEFAULT CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5000)) ,
                   ColFoto VarBinary(MAX))
GO

-- 5 seconds to run
INSERT INTO TabTestStats (Col1)
SELECT TOP 5000
       CONVERT(VarBinary(MAX),REPLICATE(CONVERT(VarBinary(MAX), CONVERT(VarChar(250), NEWID())), 5000)) AS Col1
  FROM sysobjects a, sysobjects b, sysobjects c, sysobjects d
GO

-- 4 seconds to run
SELECT COUNT(*) FROM TabTestStats
WHERE Col50 IS NULL
AND 1 = (SELECT 1)
GO

--EXEC sp_helpstats TabTestStats
--GO

--DROP STATISTICS TabTestStats.[_WA_Sys_00000033_3FD07829]
--GO
*/