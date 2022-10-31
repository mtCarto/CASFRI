#!/bin/bash -x

# This script loads the NWT FVI forest inventory (NT03) into PostgreSQL

# The format of the source dataset is a geodatabase with one table

# The year of photography is included in the REF_YEAR attribute

# Load into a target table in the schema defined in the config file.

# If the table already exists, it can be overwritten by setting the "overwriteFRI" variable
# in the configuration file.
######################################## Set variables #######################################

source ./common.sh

srcInventoryID=MB10

srcFileName=FRIFLI_FiveYearReports_2010_2016_2021
srcFullPath="$friDir/MB/$srcInventoryID/data/inventory/$srcFileName.gdb"

destInventoryID=MB12
gdbTableName=MB_FRIFLI_Updatedto2010_v9WDriveCopy
fullTargetTableName=$targetFRISchema.mb12


########################################## Process ######################################

# Run ogr2ogr to load all table
"$gdalFolder/ogr2ogr" \
-f "PostgreSQL" "$pg_connection_string" "$srcFullPath" "$gdbTableName" \
-nln $fullTargetTableName $layer_creation_options $other_options \
-nlt PROMOTE_TO_MULTI \
-sql "SELECT *, '$srcFileName' AS src_filename, '$destInventoryID' AS inventory_id, mu_id AS mu_fli,
            yearphoto as yearphoto_fli, mu_old as poly_id FROM $gdbTableName WHERE inv_type = 'FLI'" \
-progress $overwrite_tab