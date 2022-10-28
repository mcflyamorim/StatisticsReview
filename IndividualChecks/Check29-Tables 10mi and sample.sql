/*
Check 29 - Check if there are tables with more than 10mi rows

< ---------------- Description ----------------- >
The bigger the table, the smaller the auto-update sample. That means, those big objects
will probably require a special attention. 

< -------------- What to look for and recommendations -------------- >
- Make sure the number or rows sampled is enough to provide good statistics

- Review queries using those objects and make sure cardinality estimates are good
*/

-- Fabiano Amorim
-- http:\\www.blogfabiano.com | fabianonevesamorim@hotmail.com
SET NOCOUNT ON; SET ARITHABORT OFF; SET ARITHIGNORE ON; SET ANSI_WARNINGS OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/* Preparing tables with statistic info */
EXEC sp_GetStatisticInfo @database_name_filter = N'', @refreshdata = 0

IF OBJECT_ID('tempdb.dbo.tmpStatisticCheck29') IS NOT NULL
  DROP TABLE tempdb.dbo.tmpStatisticCheck29

SELECT 'Check 29 - Check if there are tables with more than 10mi rows' AS [info],
       a.database_name,
       a.schema_name,
       a.table_name,
       a.stats_name,
       a.key_column_name,
       a.statistic_type,
       a.last_updated AS last_updated_datetime,
       a.current_number_of_rows,
       a.rows_sampled AS number_of_rows_sampled_on_last_update_create_statistic,
       a.statistic_percent_sampled,
       CASE
           WHEN a.current_number_of_rows > 10000000 /*10mi*/ THEN 
                'Warning - Table has more than 10 million rows, estimated density of [' + CONVERT(VARCHAR, ISNULL(b.all_density,0)) + 
                '] and [' + CONVERT(VARCHAR, CONVERT(BigInt, 1.0 / CASE b.all_density WHEN 0 THEN 1 ELSE b.all_density END)) + '] unique values on column [' + a.key_column_name + '],' + 
                ' the bigger the number of unique values, bigger is the chance of having poor histogram distribution. Make sure queries are not having bad estimates because of it.' 
           ELSE 'OK'
         END AS number_of_rows_comment,
       dbcc_command
INTO tempdb.dbo.tmpStatisticCheck29
FROM tempdb.dbo.tmp_stats a
INNER JOIN tempdb.dbo.tmp_density_vector b
ON b.rowid = a.rowid
AND b.density_number = 1
WHERE a.current_number_of_rows > 0 /* Ignoring empty tables */
  AND a.current_number_of_rows >= 1000000 /*1mi*/

SELECT * FROM tempdb.dbo.tmpStatisticCheck29
ORDER BY current_number_of_rows DESC, 
         database_name,
         table_name,
         key_column_name,
         stats_name