#!/bin/bash -x

# This script dumps the random test tables from the database.

# When test tables rightfully differ from original tables they have to be 
# dumped with this script and pushed back in the source tree.

# #################################### Set variables ######################################

source ../../conversion/sh/common.sh

# ########################################## Process ######################################

# Run ogr2ogr

rm ./testtables/test*.csv

"$gdalFolder/ogr2ogr" -f "CSV" ".\testtables\test_0_without_validity.csv" "$pg_connection_string" -lco STRING_QUOTING=IF_NEEDED "casfri50_history_test.test_0_without_validity_new"

"$gdalFolder/ogr2ogr" -f "CSV" ".\testtables\test_0_with_validity.csv"    "$pg_connection_string" -lco STRING_QUOTING=IF_NEEDED "casfri50_history_test.test_0_with_validity_new"

"$gdalFolder/ogr2ogr" -f "CSV" ".\testtables\test_2_without_validity.csv" "$pg_connection_string" -lco STRING_QUOTING=IF_NEEDED "casfri50_history_test.test_2_without_validity_new"

"$gdalFolder/ogr2ogr" -f "CSV" ".\testtables\test_2_with_validity.csv"    "$pg_connection_string" -lco STRING_QUOTING=IF_NEEDED "casfri50_history_test.test_2_with_validity_new"

"$gdalFolder/ogr2ogr" -f "CSV" ".\testtables\test_3_without_validity.csv" "$pg_connection_string" -lco STRING_QUOTING=IF_NEEDED "casfri50_history_test.test_3_without_validity_new"

"$gdalFolder/ogr2ogr" -f "CSV" ".\testtables\test_3_with_validity.csv"    "$pg_connection_string" -lco STRING_QUOTING=IF_NEEDED "casfri50_history_test.test_3_with_validity_new"

"$gdalFolder/ogr2ogr" -f "CSV" ".\testtables\test_4_without_validity.csv" "$pg_connection_string" -lco STRING_QUOTING=IF_NEEDED "casfri50_history_test.test_4_without_validity_new"

"$gdalFolder/ogr2ogr" -f "CSV" ".\testtables\test_4_with_validity.csv"    "$pg_connection_string" -lco STRING_QUOTING=IF_NEEDED "casfri50_history_test.test_4_with_validity_new"
