#!/bin/bash -x

source ../../conversion/sh/common.sh

bashCmd="/c/program files/git/git-bash.exe"

leaveOpenCmd=
if [ ${leaveConvShellOpen}x == Truex ]; then
  leaveOpenCmd="/bin/bash"
fi

 
declare -n L

# Iterate over the list of list always making the last command a waiting one (the following ones wait for it to finish before proceeding)
for L in "${fullList[@]}"; do
  for F in "${L[@]}"; do
    if [ $F == ${L[-1]} ]; then
      "$bashCmd" -c "$pgFolder/bin/psql -p $pgport -U $pguser -w -d $pgdbname -P pager=off -c \"SELECT TT_ProduceInvGeoHistory('${F}');\""
    else
      "$bashCmd" -c "$pgFolder/bin/psql -p $pgport -U $pguser -w -d $pgdbname -P pager=off -c \"SELECT TT_ProduceInvGeoHistory('${F}');\";$leaveOpenCmd" &
    fi
  done
done

"$bashCmd" -c "$pgFolder/bin/psql -p $pgport -U $pguser -w -d $pgdbname -P pager=off -c \"CREATE INDEX ON casfri50_history.geo_history USING btree(left(cas_id, 2));\""
"$bashCmd" -c "$pgFolder/bin/psql -p $pgport -U $pguser -w -d $pgdbname -P pager=off -c \"CREATE INDEX ON casfri50_history.geo_history USING btree(left(cas_id, 4));\""
"$bashCmd" -c "$pgFolder/bin/psql -p $pgport -U $pguser -w -d $pgdbname -P pager=off -c \"CREATE INDEX ON casfri50_history.geo_history USING gist(geom);\""
