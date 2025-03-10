------------------------------------------------------------------------------
-- CASFRI - AB16 translation script for CASFRI v5
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
-- Translate all AB16. XXhXXm
--------------------------------------------------------------------------
-- CAS
------------------------
SELECT TT_Prepare('translation', 'ab_avi01_cas', '_ab16_cas'); -- used for both AB06 and AB16

SELECT TT_CreateMappingView('rawfri', 'ab16', 'ab');

-- Delete existing entries
-- DELETE FROM casfri50.cas_all WHERE left(cas_id, 4) = 'AB16';

-- Add translated ones
INSERT INTO casfri50.cas_all -- 37m35s
SELECT * FROM TT_Translate_ab16_cas('rawfri', 'ab16_l1_to_ab_l1_map');


------------------------
-- DST
------------------------
SELECT TT_Prepare('translation', 'ab_avi01_dst', '_ab16_dst'); -- used for both AB06 and AB16

SELECT TT_CreateMappingView('rawfri', 'ab16', 1, 'ab', 1);

-- Delete existing entries
-- DELETE FROM casfri50.dst_all WHERE left(cas_id, 4) = 'AB16';

-- Add translated ones
INSERT INTO casfri50.dst_all -- 1m50s
SELECT * FROM TT_Translate_ab16_dst('rawfri', 'ab16_l1_to_ab_l1_map');


------------------------
-- ECO
------------------------
SELECT TT_Prepare('translation', 'ab_avi01_eco', '_ab16_eco'); -- used for both AB06 and AB16

SELECT TT_CreateMappingView('rawfri', 'ab16', 'ab');

-- Delete existing entries
-- DELETE FROM casfri50.eco_all WHERE left(cas_id, 4) = 'AB16';

-- Add translated ones
INSERT INTO casfri50.eco_all -- 6m2s
SELECT * FROM TT_Translate_ab16_eco('rawfri', 'ab16_l1_to_ab_l1_map');


------------------------
-- LYR
------------------------
-- Check the uniqueness of AB species codes
CREATE UNIQUE INDEX IF NOT EXISTS species_code_mapping_ab16_species_codes_idx
ON translation.species_code_mapping (ab_species_codes)
WHERE TT_NotEmpty(ab_species_codes);

SELECT TT_Prepare('translation', 'ab_avi01_lyr', '_ab16_lyr'); -- used for both AB06 and AB16 layer 1 and 2

-- Delete existing entries
-- DELETE FROM casfri50.lyr_all WHERE left(cas_id, 4) = 'AB16';

-- Add translated ones
-- Layer 1

SELECT TT_CreateMappingView('rawfri', 'ab16', 1, 'ab', 1);

INSERT INTO casfri50.lyr_all -- 46m20s
SELECT * FROM TT_Translate_ab16_lyr('rawfri', 'ab16_l1_to_ab_l1_map');


-- Layer 2

SELECT TT_CreateMappingView('rawfri', 'ab16', 2, 'ab', 1);

INSERT INTO casfri50.lyr_all -- 3m56s
SELECT * FROM TT_Translate_ab16_lyr('rawfri', 'ab16_l2_to_ab_l1_map');


------------------------
-- NFL
------------------------
SELECT TT_Prepare('translation', 'ab_avi01_nfl', '_ab16_nfl'); -- used for both AB06 and AB16

-- Delete existing entries
-- DELETE FROM casfri50.nfl_all WHERE left(cas_id, 4) = 'AB16';

-- Add translated ones
-- Layer 1

SELECT TT_CreateMappingView('rawfri', 'ab16', 3, 'ab', 1);

INSERT INTO casfri50.nfl_all -- 23m43s
SELECT * FROM TT_Translate_ab16_nfl('rawfri', 'ab16_l3_to_ab_l1_map');


-- Layer 2 reusing AB16 layer 1 translation table

SELECT TT_CreateMappingView('rawfri', 'ab16', 4, 'ab', 1);

INSERT INTO casfri50.nfl_all -- 
SELECT * FROM TT_Translate_ab16_nfl('rawfri', 'ab16_l4_to_ab_l1_map');


------------------------
-- GEO
------------------------
SELECT TT_Prepare('translation', 'ab_avi01_geo', '_ab16_geo'); -- used for both AB06 and AB16

SELECT TT_CreateMappingView('rawfri', 'ab16', 1, 'ab', 1);

-- Delete existing entries
-- DELETE FROM casfri50.geo_all WHERE left(cas_id, 4) = 'AB16';

-- Add translated ones
INSERT INTO casfri50.geo_all -- 7m30s
SELECT * FROM TT_Translate_ab16_geo('rawfri', 'ab16_l1_to_ab_l1_map'); 

--------------------------------------------------------------------------
-- Check
/*
SELECT 'cas_all' AS table, count(*) nb
FROM casfri50.cas_all
WHERE left(cas_id, 4) = 'AB16'
UNION ALL
SELECT 'dst_all', count(*) nb
FROM casfri50.dst_all
WHERE left(cas_id, 4) = 'AB16'
UNION ALL
SELECT 'eco_all', count(*) nb
FROM casfri50.eco_all
WHERE left(cas_id, 4) = 'AB16'
UNION ALL
SELECT 'lyr_all', count(*) nb
FROM casfri50.lyr_all
WHERE left(cas_id, 4) = 'AB16'
UNION ALL
SELECT 'nfl_all', count(*) nb
FROM casfri50.nfl_all
WHERE left(cas_id, 4) = 'AB16'
UNION ALL
SELECT 'geo_all', count(*) nb
FROM casfri50.geo_all
WHERE left(cas_id, 4) = 'AB16';
*/
--------------------------------------------------------------------------
