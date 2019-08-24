#!/bin/bash
# Post-process
# :PROPERTIES:
# :header-args: :tangle CARRA_post.sh
# :END:

# Run with:
# =grass74 -c ./GRASS_GREENLAND/PERMANENT --exec ./CARRA_post.sh /path/to/output/=




# Climatological mean for all years


out=$1

g.mapset -c climatology
mkdir ${out}/climatology
# d=060 # debug 
for d in $(seq -w 060 274); do
  g.remove -f type=raster pattern=*
  for year in $(seq 2000 2006); do
    fname=${out}/${year}/${year}_${d}.tif
    r.external input=${fname} output=year_${year} --o
  done

  addlist=$(g.list separator="+" type=raster pattern=year_[0-9]*)
  n=$(echo $addlist | tr '+' '\n' | wc -l)
  r.mapcalc "avg = float(${addlist})/${n}" --o
  r.out.gdal -cm input=avg output=${out}/climatology/2000-2006_${d}.tif type=Float32 createopt="COMPRESS=DEFLATE" --o
done

# Minimum value for each year

out=$1

g.mapset -c minimum
mkdir ${out}/min

for year in $(seq 2000 2017); do
  g.remove -f type=raster pattern=*

  seq -w 366 | parallel --bar r.external input=${out}/${year}/${year}_{.}.tif output=day_{.} --o

  minlist=$(g.list separator=comma type=raster pattern=day_[0-9]*)
  r.mapcalc "min = min(${minlist})" --o
  r.out.gdal input=min output=${out}/min/${year}.tif createopt="COMPRESS=DEFLATE" type=Float32 --o
done

# Age

out=$1

g.mapset -c age
mkdir ${out}/age
for year in $(seq 2000 2017); do
  g.remove -f type=raster pattern=*
  mkdir ${out}/age/${year}

  # read in all days for this year
  seq -w 060 274 | parallel --bar r.external input=${out}/${year}/${year}_{.}.tif output=day_{.} --o

  r.mapcalc "age = -1" --o # initial value everywhere
  for d in $(seq -w 061 274); do
    d0=$(echo "$d-1"|bc -l)
    d0=$(printf %03G $d0)

    # if the data changed from yesterday, set age to 0. Otherwise,
    # set it to age+1, unless it was -1 (no valid data yet) in which
    # case keep it at -1
    r.mapcalc "age = if(day_${d} != day_${d0}, 0, if(age == -1, -1, age+1))" --o
    r.out.gdal -cm input=age output=${out}/age/${year}/${year}_${d}.tif type=Int16 createopt="COMPRESS=DEFLATE" --o
  done
done
