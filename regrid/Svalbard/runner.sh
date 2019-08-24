#!/bin/bash
# Runner


# setup
grass74 -c EPSG:32635 ./GRASS_Svalbard --exec ./CARRA_pre.sh

# Run 2012 and 2017
find /mnt/ice/Jason/MOD10A1/Svalbard_and_Russian_Islands/to_regrid/2012/ -name "*.txt" | parallel --bar grass74 -c ./GRASS_Svalbard/{%} --exec ./CARRA_daily.sh {.} /mnt/ice/Ken/CARRA/Svalbard

find /mnt/ice/Jason/MOD10A1/Svalbard_and_Russian_Islands/to_regrid/2017/ -name "*.txt" | parallel --bar grass74 -c ./GRASS_Svalbard/{%} --exec ./CARRA_daily.sh {.} /mnt/ice/Ken/CARRA/Svalbard

# Run the rest
for y in $(seq 2000 2016 | grep -v 2012); do 
    find /mnt/ice/Jason/MOD10A1/Svalbard_and_Russian_Islands/to_regrid/${y}/ -name "*.txt" | parallel --bar grass74 -c ./GRASS_Svalbard/{%} --exec ./CARRA_daily.sh {.} /mnt/ice/Ken/CARRA/Svalbard
done

grass74 -c ./GRASS_Svalbard/PERMANENT --exec ./CARRA_post.sh /mnt/ice/Ken/CARRA/Svalbard
