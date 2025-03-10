------------------------------------------------------------------------------
-- CASFRI - Flat table creation script for CASFRI v5
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
-- Build a Flat (denormalized) version of CASFRI50
-------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS casfri50_flat;
-------------------------------------------------------
-- Create samples of CASFRI50 for development purpose only
--DROP MATERIALIZED VIEW IF EXISTS casfri50_flat.cas_sample1 CASCADE;
--CREATE MATERIALIZED VIEW casfri50_flat.cas_sample1 AS
--SELECT * 
--FROM casfri50.cas_all cas
--TABLESAMPLE SYSTEM ((4000 * 100) / (SELECT count(*) FROM casfri50.cas_all)::double precision) REPEATABLE (1.2);

--DROP VIEW IF EXISTS casfri50_flat.dst_sample1;
--CREATE VIEW casfri50_flat.dst_sample1 AS
--SELECT dst.* 
--FROM casfri50.dst_all dst, casfri50_flat.cas_sample1 cas
--WHERE dst.cas_id = cas.cas_id;

--DROP VIEW IF EXISTS casfri50_flat.eco_sample1;
--CREATE VIEW casfri50_flat.eco_sample1 AS
--SELECT eco.* 
--FROM casfri50.eco_all eco, casfri50_flat.cas_sample1 cas
--WHERE eco.cas_id = cas.cas_id;

--DROP VIEW IF EXISTS casfri50_flat.lyr_sample1;
--CREATE VIEW casfri50_flat.lyr_sample1 AS
--SELECT lyr.* 
--FROM casfri50.lyr_all lyr, casfri50_flat.cas_sample1 cas
--WHERE lyr.cas_id = cas.cas_id;

--DROP VIEW IF EXISTS casfri50_flat.nfl_sample1;
--CREATE VIEW casfri50_flat.nfl_sample1 AS
--SELECT nfl.* 
--FROM casfri50.nfl_all nfl, casfri50_flat.cas_sample1 cas
--WHERE nfl.cas_id = cas.cas_id;

--DROP VIEW IF EXISTS casfri50_flat.geo_sample1;
--CREATE VIEW casfri50_flat.geo_sample1 AS
--SELECT geo.* 
--FROM casfri50.geo_all geo, casfri50_flat.cas_sample1 cas
--WHERE geo.cas_id = cas.cas_id;
-------------------------------------------------------
-- Create a flat table
--
-- This version has one row per LYR and NFL layers, 
-- so many rows per CAS_ID.
-- DST info is always joined to row with layer = 1.
-- NB01 dst on layer 2 are left out.
-- 10h18
-------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS casfri50_flat.cas_flat_one_layer_per_row;
CREATE MATERIALIZED VIEW casfri50_flat.cas_flat_one_layer_per_row AS
WITH lyr_nfl AS (
  -- Create a LYR_NFL table containing only LYR (707) and NFL (846) rows
  -- SELECT count(*) FROM casfri50_flat.lyr_sample1;
  SELECT cas_id,
         soil_moist_reg, structure_per, structure_range, layer, layer_rank,
         crown_closure_lower, crown_closure_upper, height_lower, height_upper, productivity, productivity_type,
         species_1, species_per_1, species_2, species_per_2, species_3, species_per_3, 
         species_4, species_per_4, species_5, species_per_5, species_6, species_per_6,
         origin_lower, origin_upper, site_class, site_index,
         'NOT_APPLICABLE' nat_non_veg,
         'NOT_APPLICABLE' non_for_anth,
         'NOT_APPLICABLE' non_for_veg
  --FROM casfri50_flat.lyr_sample1
  FROM casfri50.lyr_all
  UNION ALL
  -- SELECT count(*) FROM casfri50_flat.nfl_sample1;
  SELECT cas_id, 
         soil_moist_reg, structure_per, -8887 structure_range, layer, layer_rank,
         crown_closure_lower, crown_closure_upper, height_lower, height_upper, 
         'NOT_APPLICABLE' productivity,
         'NOT_APPLICABLE' productivity_type,
         'NOT_APPLICABLE' species_1,
         -8887 species_per_1,
         'NOT_APPLICABLE' species_2,
          -8887 species_per_2,
         'NOT_APPLICABLE' species_3,
         -8887 species_per_3,
         'NOT_APPLICABLE' species_4,
         -8887 species_per_4,
         'NOT_APPLICABLE' species_5,
         -8887 species_per_5,
         'NOT_APPLICABLE' species_6,
         -8887 species_per_6,
         -8887 origin_lower,
         -8887 origin_upper,
         'NOT_APPLICABLE' site_class,
         -8887 site_index,
         nat_non_veg,
         non_for_anth,
         non_for_veg
  --FROM casfri50_flat.nfl_sample1
  FROM casfri50.nfl_all
), cas_lyr_nfl AS (
  -- LEFT JOIN the cas table (1010 rows) with the lyr_nfl 
  -- table in order to get all cas rows.
  -- Defaulting non-joining rows to NOT_APPLICABLE (-8887).
  SELECT cas.*,
         coalesce(soil_moist_reg, 'NOT_APPLICABLE') soil_moist_reg,
         coalesce(structure_per, -8887) structure_per,
         coalesce(structure_range, -8887) structure_range,
         coalesce(layer, 1) layer,
         coalesce(layer_rank, -8887) layer_rank,
         coalesce(crown_closure_lower, -8887) crown_closure_lower,
         coalesce(crown_closure_upper, -8887) crown_closure_upper,
         coalesce(height_lower, -8887) height_lower,
         coalesce(height_upper, -8887) height_upper,
         coalesce(productivity, 'NOT_APPLICABLE') productivity,
         coalesce(productivity_type, 'NOT_APPLICABLE') productivity_type,
         coalesce(species_1, 'NOT_APPLICABLE') species_1,
         coalesce(species_per_1, -8887) species_per_1,
         coalesce(species_2, 'NOT_APPLICABLE') species_2,
         coalesce(species_per_2, -8887) species_per_2,
         coalesce(species_3, 'NOT_APPLICABLE') species_3,
         coalesce(species_per_3, -8887) species_per_3,
         coalesce(species_4, 'NOT_APPLICABLE') species_4,
         coalesce(species_per_4, -8887) species_per_4,
         coalesce(species_5, 'NOT_APPLICABLE') species_5,
         coalesce(species_per_5, -8887) species_per_5,
         coalesce(species_6, 'NOT_APPLICABLE') species_6,
         coalesce(species_per_6, -8887) species_per_6,
         coalesce(origin_lower, -8887) origin_lower,
         coalesce(origin_upper, -8887) origin_upper,
         coalesce(site_class, 'NOT_APPLICABLE') site_class,
         coalesce(site_index, -8887) site_index,
         coalesce(nat_non_veg, 'NOT_APPLICABLE') nat_non_veg,
         coalesce(non_for_anth, 'NOT_APPLICABLE') non_for_anth,
         coalesce(non_for_veg, 'NOT_APPLICABLE') non_for_veg
  --FROM casfri50_flat.cas_sample1 cas 
  FROM casfri50.cas_all cas 
  LEFT OUTER JOIN lyr_nfl
  USING (cas_id)
  --ORDER BY cas.cas_id, layer
), cas_lyr_nfl_dst AS (
  -- Add dst rows defaulting non-joining rows to NOT_APPLICABLE (-8887)
  SELECT cas_lyr_nfl.*, 
         coalesce(dist_type_1, 'NOT_APPLICABLE') dist_type_1,
         coalesce(dist_year_1, -8887) dist_year_1,
         coalesce(dist_ext_lower_1, -8887) dist_ext_lower_1, 
         coalesce(dist_ext_upper_1, -8887) dist_ext_upper_1,
         coalesce(dist_type_2, 'NOT_APPLICABLE') dist_type_2,
         coalesce(dist_year_2, -8887) dist_year_2,
         coalesce(dist_ext_lower_2, -8887) dist_ext_lower_2,
         coalesce(dist_ext_upper_2, -8887) dist_ext_upper_2,
         coalesce(dist_type_3, 'NOT_APPLICABLE') dist_type_3,
         coalesce(dist_year_3, -8887) dist_year_3,
         coalesce(dist_ext_lower_3, -8887) dist_ext_lower_3,
         coalesce(dist_ext_upper_3, -8887) dist_ext_upper_3
  FROM cas_lyr_nfl
  --LEFT JOIN casfri50_flat.dst_sample1 dst 
  LEFT JOIN casfri50.dst_all dst 
  ON (cas_lyr_nfl.cas_id = dst.cas_id AND dst.layer < 2)
), cas_lyr_nfl_dst_eco AS (
  -- Add eco rows defaulting non-joining rows to NOT_APPLICABLE (-8887)
  SELECT cas_lyr_nfl_dst.*,
         coalesce(wetland_type, 'NOT_APPLICABLE') wetland_type,
         coalesce(wet_veg_cover, 'NOT_APPLICABLE') wet_veg_cover,
         coalesce(wet_landform_mod, 'NOT_APPLICABLE') wet_landform_mod,
         coalesce(wet_local_mod, 'NOT_APPLICABLE') wet_local_mod,
         coalesce(eco_site, 'NOT_APPLICABLE') eco_site
  FROM cas_lyr_nfl_dst
  --LEFT JOIN casfri50_flat.eco_sample1 eco 
  LEFT JOIN casfri50.eco_all eco 
  USING (cas_id)
)
-- Add geo rows
SELECT cas_lyr_nfl_dst_eco.*,
       geometry
FROM cas_lyr_nfl_dst_eco
--LEFT JOIN casfri50_flat.geo_sample1 geo 
LEFT JOIN casfri50.geo_all geo 
USING (cas_id);



