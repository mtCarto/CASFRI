#!/bin/bash -x

#echo "######################## Begin load_metadata.sh ########################################"

thisScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source $thisScriptDir/../common.sh

# Load inventory metadata table
thisScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo "Loading inventory_metadata.csv table into the database..."
"$ogrCmd" -f PostgreSQL "$gdalConnectionString" $thisScriptDir/inventory_metadata.csv $overwriteTable
  -nln $targetTranslationFileSchema.inventory_metadata

# Load layer metadata table
echo "Loading layer_metadata.csv table into the database..."
"$ogrCmd" -f PostgreSQL "$gdalConnectionString" $thisScriptDir/layer_metadata.csv $overwriteTable \
  -nln $targetTranslationFileSchema.layer_metadata


#echo "######################## End load_metadata.sh ########################################"
