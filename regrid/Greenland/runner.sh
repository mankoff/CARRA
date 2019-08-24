#!/bin/bash
# Runner


# setup
grass74 -c EPSG:3413 ./GRASS_GREENLAND --exec ./CARRA_pre.sh

# # Run 2012 and 2017
# find /mnt/ice/Jason/MOD10A1/Greenland/to_regrid/2012/ -name "*.txt" | parallel --bar grass74 -c ./GRASS_GREENLAND/{%} --exec ./CARRA_daily.sh {.} /mnt/ice/Ken/CARRA/Greenland

# find /mnt/ice/Jason/MOD10A1/Greenland/to_regrid/2017/ -name "*.txt" | parallel --bar grass74 -c ./GRASS_GREENLAND/{%} --exec ./CARRA_daily.sh {.} /mnt/ice/Ken/CARRA/Greenland

# Run the rest
for y in $(seq 2003 2016 | grep -v 2012); do 
    find /mnt/ice/Jason/MOD10A1/Greenland/to_regrid/${y}/ -name "*.txt" | parallel --bar grass74 -c ./GRASS_GREENLAND/{%} --exec ./CARRA_daily.sh {.} /mnt/ice/Ken/CARRA/Greenland
done

grass74 -c ./GRASS_GREENLAND/PERMANENT --exec ./CARRA_post.sh /mnt/ice/Ken/CARRA/Greenland
