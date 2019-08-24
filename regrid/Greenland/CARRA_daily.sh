#!/bin/bash
# Daily work
# :PROPERTIES:
# :header-args: :tangle CARRA_daily.sh
# :END:

# Run one day like this (generic example):
# =grass74 -c <GRASS_FOLDER>/<MAPSET> --exec ./CARRA_daily.sh </path/to/input/YYYY/YYYY_DOY.txt> </path/to/output/=

# Use the same =<GRASS_FOLDER>= you created when running =./CARRA_pre.sh=. A specific example is:

# =grass74 -c ./GRASS_GREENLAND/DAILY --exec ./CARRA_daily.sh ./input/2016/2016_060.txt ./out/=

# And =./out/2016/2016_060.tif= will be created.

# Run all days in parallel like this (pipe list of files to =parallel=):

# =find ./input -name "*.txt" | parallel --bar grass74 -c ./GRASS_GREENLAND/{%} --exec ./CARRA_daily.sh {.} ./out/=

# Run one year in parallel like this (same as above but =grep= for the year):

# =find ./input -name "*.txt" | grep 2016 | parallel --bar grass74 -c ./GRASS_GREENLAND/{%} --exec ./CARRA_daily.sh {.} ./out/=




# Generate GeoTIFFs for one day
# + Read in each day
# + Apply quick filter
# + Fill gaps
# + Export

### DEBUGGING. COMMENT OUT WHEN RUNNING
# input=./input/2016/2016_060.txt
### WHEN RUNNING, GET VARS FROM CLI ARGS
input=${1}
out=${2}
f=$(dirname ${input} | rev | cut -d"/" -f2- | rev) # input folder
y=$(basename ${input} | cut -d"_" -f1)
d=$(basename ${input} .txt | cut -d"_" -f2)

g.region -d  # use default resolution
r.mask -r

mkdir -p ${out}/${y}

# Project data
echo "reading in data (~30-60s)..."
paste -d"|" xy.txt ${f}/${y}/${y}_${d}.txt | r.in.xyz --q input=- output=day type=CELL --o

# Fill in small holes
r.null map=day setnull=0
r.mfilter -z input=day output=day_fill filter=./filter.txt --o
# undo the coastline growth
r.mapcalc "day = (day_fill / 10000) * mask_ocean" --o


# fill in large clumps
# MCB = "missing clump buffer"
# MC = "missing clump"
# mcb=clump_1477_buffer # DEBUG
# mcb=clump_972_buffer # DEBUG
for mcb in $(g.list type=raster mapset=missing pattern="clump_*_buffer"); do
  mc=$(echo $mcb | cut -d"_" -f1,2)
  r.mask -r --q
  g.region raster=${mcb}@missing
  g.region zoom=${mcb}@missing
  r.mask raster=${mcb}@missing --o
  # r.mapcalc "MASK = ${mcb}@missing * (day > 0.3)" --o
  # r.regression.line mapx=z_s mapy=${y}_${d} --verbose
  eval $(r.regression.line -g mapx=z_s@missing mapy=day --verbose)
  echo "Correlation: $R"
  r.mapcalc "patch_${mc} = if(isnull(${mc}@missing), day, ((${a})+(${b}*z_s@missing)))" --o
done
  
g.region -d
r.mask -r

r.patch -s --o input=day,$(g.list type=raster pattern=patch_* separator=,) output=day_filled
r.mfilter -z input=day_filled output=day_filled_filter filter=./filter.txt --o
r.out.gdal --q -fcm input=day_filled_filter output=${out}/${y}/${y}_${d}.tif type=Float32 createopt="COMPRESS=DEFLATE" --o
