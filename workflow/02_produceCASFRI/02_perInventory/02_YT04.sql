------------------------------------------------------------------------------
-- CASFRI - YT04 translation script for CASFRI v5
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
-- Translate all YT04. XXhXXm
--------------------------------------------------------------------------
-- CAS
------------------------
SELECT TT_Prepare('translation', 'yt_yvi01_cas', '_yt04_cas', 'ab_avi01_cas');

SELECT TT_CreateMappingView('rawfri', 'yt04', 'yt');

-- Delete existing entries
-- DELETE FROM casfri50.cas_all WHERE left(cas_id, 4) = 'YT04';

-- Add translated ones
INSERT INTO casfri50.cas_all -- 
SELECT * FROM TT_Translate_yt04_cas('rawfri', 'yt04_l1_to_yt_l1_map');


------------------------
-- DST
------------------------
SELECT TT_Prepare('translation', 'yt_yvi03_dst', '_yt04_dst', 'ab_avi01_dst');

SELECT TT_CreateMappingView('rawfri', 'yt04', 1, 'yt', 1);

-- Delete existing entries
-- DELETE FROM casfri50.dst_all WHERE left(cas_id, 4) = 'YT04';

-- Add translated ones
INSERT INTO casfri50.dst_all -- 
SELECT * FROM TT_Translate_yt04_dst('rawfri', 'yt04_l1_to_yt_l1_map');


------------------------
-- ECO
------------------------
SELECT TT_Prepare('translation', 'yt_yvi03_eco', '_yt04_eco', 'ab_avi01_eco');

SELECT TT_CreateMappingView('rawfri', 'yt04', 'yt');

-- Delete existing entries
-- DELETE FROM casfri50.eco_all WHERE left(cas_id, 4) = 'YT04';

-- Add translated ones
INSERT INTO casfri50.eco_all -- 
SELECT * FROM TT_Translate_yt04_eco('rawfri', 'yt04_l1_to_yt_l1_map');


------------------------
-- LYR
------------------------
-- Check the uniqueness of YT species codes
CREATE UNIQUE INDEX IF NOT EXISTS species_code_mapping_yt01_species_codes_idx
ON translation.species_code_mapping (yt_species_codes)
WHERE TT_NotEmpty(yt_species_codes);

-- Prepare the translation function
SELECT TT_Prepare('translation', 'yt_yvi03_lyr', '_yt04_lyr', 'ab_avi01_lyr'); 

SELECT TT_CreateMappingView('rawfri', 'yt04', 1, 'yt', 1);

-- Delete existing entries
-- DELETE FROM casfri50.lyr_all WHERE left(cas_id, 4) = 'YT04';

-- Add translated ones
INSERT INTO casfri50.lyr_all -- 
SELECT * FROM TT_Translate_yt04_lyr('rawfri', 'yt04_l1_to_yt_l1_map');


------------------------
-- NFL
------------------------
SELECT TT_Prepare('translation', 'yt_yvi03_nfl', '_yt04_nfl', 'ab_avi01_nfl');

SELECT TT_CreateMappingView('rawfri', 'yt04', 2, 'yt', 1);

-- Delete existing entries
-- DELETE FROM casfri50.nfl_all WHERE left(cas_id, 4) = 'YT04';

-- Add translated ones
INSERT INTO casfri50.nfl_all -- 
SELECT * FROM TT_Translate_yt04_nfl('rawfri', 'yt04_l2_to_yt_l1_map');


------------------------
-- GEO
------------------------
SELECT TT_Prepare('translation', 'yt_yvi01_geo', '_yt04_geo', 'ab_avi01_geo');

SELECT TT_CreateMappingView('rawfri', 'yt04', 1, 'yt', 1);

-- Delete existing entries
-- DELETE FROM casfri50.geo_all WHERE left(cas_id, 4) = 'YT04';

-- Add translated ones
INSERT INTO casfri50.geo_all -- 
SELECT * FROM TT_Translate_yt04_geo('rawfri', 'yt04_l1_to_yt_l1_map');

--------------------------------------------------------------------------
-- Check

SELECT 'cas_all' AS table, count(*) nb
FROM casfri50.cas_all
WHERE left(cas_id, 4) = 'YT04'
UNION ALL
SELECT 'dst_all', count(*) nb
FROM casfri50.dst_all
WHERE left(cas_id, 4) = 'YT04'
UNION ALL
SELECT 'eco_all', count(*) nb
FROM casfri50.eco_all
WHERE left(cas_id, 4) = 'YT04'
UNION ALL
SELECT 'lyr_all', count(*) nb
FROM casfri50.lyr_all
WHERE left(cas_id, 4) = 'YT04'
UNION ALL
SELECT 'nfl_all', count(*) nb
FROM casfri50.nfl_all
WHERE left(cas_id, 4) = 'YT04'
UNION ALL
SELECT 'geo_all', count(*) nb
FROM casfri50.geo_all
WHERE left(cas_id, 4) = 'YT04';

--------------------------------------------------------------------------
