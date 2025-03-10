------------------------------------------------------------------------------
-- CASFRI - QC02 translation development script for CASFRI v5
-- For use with PostgreSQL Table Tranlation Framework v2.0.1 for PostgreSQL 13.x
-- https://github.com/CASFRI/PostgreSQL-Table-Translation-Framework
-- https://github.com/CASFRI/CASFRI
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- Copyright (C) 2018-2021 Pierre Racine <pierre.racine@sbf.ulaval.ca>, 
--                         Marc Edwards <medwards219@gmail.com>,
--                         Pierre Vernier <pierre.vernier@gmail.com>
--                         Melina Houle <melina.houle@sbf.ulaval.ca>
-------------------------------------------------------------------------------
-- No not display debug messages.
SET tt.debug TO TRUE;
SET tt.debug TO FALSE;

--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- Create test translation tables
--------------------------------------------------------------------------
--------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS translation_devel;
-------------------------------------------------------
-- Display translation tables
SELECT * FROM translation.qc_ini03_cas; 
SELECT * FROM translation.qc_ini03_dst; 
SELECT * FROM translation.qc_ini03_eco; 
SELECT * FROM translation.qc_ini03_lyr; 
SELECT * FROM translation.qc_ini03_nfl;
SELECT * FROM translation.qc_ini03_geo;
----------------------------
-- Create subsets of translation tables if necessary
----------------------------
-- cas
DROP TABLE IF EXISTS translation_devel.qc_ini03_cas_devel;
CREATE TABLE translation_devel.qc_ini03_cas_devel AS
SELECT * FROM translation.qc_ini03_cas
--WHERE rule_id::int < 1
;
-- display
SELECT * FROM translation_devel.qc_ini03_cas_devel;
----------------------------
-- dst
DROP TABLE IF EXISTS translation_devel.qc_ini03_dst_devel;
CREATE TABLE translation_devel.qc_ini03_dst_devel AS
SELECT * FROM translation.qc_ini03_dst
--WHERE rule_id::int = 2
;
-- display
SELECT * FROM translation_devel.qc_ini03_dst_devel;
----------------------------
-- eco
DROP TABLE IF EXISTS translation_devel.qc_ini03_eco_devel;
CREATE TABLE translation_devel.qc_ini03_eco_devel AS
SELECT * FROM translation.qc_ini03_eco
--WHERE rule_id::int = 1
;
-- display
SELECT * FROM translation_devel.qc_ini03_eco_devel;
----------------------------
-- lyr
DROP TABLE IF EXISTS translation_devel.qc_ini03_lyr_devel;
CREATE TABLE translation_devel.qc_ini03_lyr_devel AS
SELECT * FROM translation.qc_ini03_lyr
--WHERE rule_id::int <13 AND rule_id::int <19
;
-- display
SELECT * FROM translation_devel.qc_ini03_lyr_devel;
----------------------------
-- nfl
DROP TABLE IF EXISTS translation_devel.qc_ini03_nfl_devel;
CREATE TABLE translation_devel.qc_ini03_nfl_devel AS
SELECT * FROM translation.qc_ini03_nfl
--WHERE rule_id::int = 1
;
-- display
SELECT * FROM translation_devel.qc_ini03_nfl_devel;
----------------------------
-- geo
DROP TABLE IF EXISTS translation_devel.qc_ini03_geo_devel;
CREATE TABLE translation_devel.qc_ini03_geo_devel AS
SELECT * FROM translation.qc_ini03_geo
--WHERE rule_id::int = 2
;
-- display
SELECT * FROM translation_devel.qc_ini03_geo_devel;

--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- Check the uniqueness of QC species codes
--------------------------------------------------------------------------
--------------------------------------------------------------------------
CREATE UNIQUE INDEX ON translation.species_code_mapping (qc_species_codes)
WHERE TT_NotEmpty(qc_species_codes);

--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- Translate the sample table
--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- Create translation functions
SELECT TT_Prepare('translation_devel', 'qc_ini03_cas_devel', '_qc02_cas_devel');
SELECT TT_Prepare('translation_devel', 'qc_ini03_dst_devel', '_qc02_dst_devel');
SELECT TT_Prepare('translation_devel', 'qc_ini03_eco_devel', '_qc02_eco_devel');
SELECT TT_Prepare('translation_devel', 'qc_ini03_lyr_devel', '_qc02_lyr_devel');
SELECT TT_Prepare('translation_devel', 'qc_ini03_nfl_devel', '_qc02_nfl_devel');
SELECT TT_Prepare('translation_devel', 'qc_ini03_geo_devel', '_qc02_geo_devel');

-- Translate the samples
SELECT TT_CreateMappingView('rawfri', 'qc02', 1, 'qc_ini03', 1, 200);
SELECT * FROM TT_Translate_qc02_cas_devel('rawfri', 'qc02_l1_to_qc_ini03_l1_map_200'); -- 6 s.

SELECT * FROM TT_Translate_qc02_dst_devel('rawfri', 'qc02_l1_to_qc_ini03_l1_map_200'); -- 7 s.

SELECT * FROM TT_Translate_qc02_eco_devel('rawfri', 'qc02_l1_to_qc_ini03_l1_map_200'); -- 7 s.

SELECT * FROM TT_Translate_qc02_lyr_devel('rawfri', 'qc02_l1_to_qc_ini03_l1_map_200'); -- 7 s.

-- LYR layer 2
SELECT TT_CreateMappingView('rawfri', 'qc02', 2, 'qc_ini03', 1, 200);
SELECT * FROM TT_Translate_qc02_lyr_devel('rawfri', 'qc02_l2_to_qc_ini03_l1_map_200'); -- 7 s.

SELECT TT_CreateMappingView('rawfri', 'qc02', 3, 'qc_ini03', 1, 200);
SELECT * FROM TT_Translate_qc02_nfl_devel('rawfri', 'qc02_l3_to_qc_ini03_l1_map_200'); -- 7 s.

SELECT * FROM TT_Translate_qc02_geo_devel('rawfri', 'qc02_l1_to_qc_ini03_l1_map_200'); -- 7 s.

--------------------------------------------------------------------------
SELECT TT_DeleteAllLogs('translation_devel');
