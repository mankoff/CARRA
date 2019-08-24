#!/bin/bash
# Pre-process: Setup Environment
# :PROPERTIES:
# :header-args: :tangle CARRA_pre.sh
# :END:

# Run this setup code 1x as:

# Generic example:
# =grass74 -c <projection> <GRASS_FOLDER> --exec ./CARRA_pre.sh=

# Specific example:
# =grass74 -c EPSG:3413 ./GRASS_GREENLAND --exec ./CARRA_pre.sh=




# Convert (lon,lat) to (x,y)

if [[ ! -e xy.txt ]]; then
  time paste -d"|" lon.csv lat.csv | m.proj -i input=- | cut -d"|" -f1,2 > xy.txt
  # real 2m20.927s
  # user 3m32.692s
  # sys	1m4.286s
  head xy.txt
fi

# Set the region to the bounds of the provided data

# =r.in.xyz= requires a 3rd column (z), so I just replicate the file and give it 4 colums: x|y|x|y. It uses the 2nd =x= as =z= (but ignores it) and ignores the 2nd =y=.


# paste -d"|" xy.txt xy.txt | r.in.xyz -sg input=-         # print 
time eval $(paste -d"|" xy.txt xy.txt | r.in.xyz -sg input=-) # set e,w,n,s variables in the shell
g.region e=$e w=$w s=$s n=$n                             # set bounds in GRASS
g.region res=500 -pal                                    # set resolution and print
g.region -s                                              # save as default region

# Generate an ocean mask based on the data

# We generate an ocean mask because we will fill in small missing parts (holes in the data due to the reprojection - not everything is actually at 5 km x 5 km, some cells have 2 points averaged and others have 0 points) with a 3x3 smooth. But we don't want to grow all land masses into the sea, so we build an ocean mask here and then apply it after the smooth, pushing the expanded land back to the coast.

# + read in one day of data
# + set 0 to null
# + clump
# + find largest clump (the ocean)
# + build mask equal to largest clump
# + export for use elsewhere maybe

time paste -d"|" xy.txt xy.txt | r.in.xyz --q input=- output=mask_MODIS --o
r.mapcalc "mask_MODIS = if(isnull(mask_MODIS), 0, 1)" --o
time r.clump input=mask_MODIS output=clumps --o
# manual inspect
# r.stats -c clumps sort=desc | head
time clump_ID_largest=$(r.stats -c clumps sort=desc | head -n1 | cut -d" " -f1)
r.mapcalc "mask_ocean = if(clumps == ${clump_ID_largest}, null(), 1)" --o
# r.out.gdal -cm input=mask_ocean output=mask_ocean.tif type=Byte createopt="COMPRESS=DEFLATE" --o

# Generate a filter

# We do a 3x3 smooth to fill in small missing parts before we do the big gap-filling. Here is the kernel for the 3x3 smooth.


cat << EOF > ./filter.txt
TITLE     See r.mfilter manual
    MATRIX    3
    1 1 1
    1 1 1
    1 1 1
    DIVISOR   0
    TYPE      P
EOF

# Apply the filter on the MODIS mask
# Fill in all the small holes just as we would on the daily data. Then the "missing" regions should only be the big holes.

r.null map=mask_MODIS setnull=0
r.mfilter -z input=mask_MODIS output=mask_MODIS_fill filter=./filter.txt --o
r.mapcalc "mask_MODIS = mask_MODIS_fill * mask_ocean" --o

# Find missing regions
# NASA data is missing over some regions. In order to fill in the missing albedo we find the regions, and for each region find a 100 km buffer around it. When processing the daily data we will find valid albedo in this 100 km buffer, correlate it with elevation, and then fill in the missing data based on its elevation.

# We'll do this work in a different mapset


g.mapset -c missing

# Read in the land/sea/ice mask and elevation
time r.import input=netCDF:./BedMachineGreenland-2017-09-20.nc:mask output=mask_BedMachine --o
r.colors map=mask_BedMachine color=random
r.import input=netCDF:./BedMachineGreenland-2017-09-20.nc:surface output=z_s

# find where there is no albedo data but there is land or ice
r.mapcalc "missing = if(isnull(mask_MODIS) & (! isnull(mask_BedMachine)), 1, null())" --o
r.colors map=missing color=blue
r.clump input=missing output=missing_clumps --o

# remove all small missing areas, less than X hectares
# frink "5 km * 5 km -> hectare"
# 2500
# Lets limit to 25 grid cells; 2500*25 = 62500
# Lets limit to 10 grid cells; 2500*10 = 25000

r.reclass.area -c input=missing_clumps output=missing_clumps_area value=25000 mode=greater method=reclass --o

# In the loop below, for each missing clump number <n>, generate a clump_<n> and a clump_<n>_buffer mask. Later (each day), we'll loop over each of the clump_<n>_buffer, find the relationship for that day and area between albedo and elevation, and apply it to the clump_<n> for that day.

g.region -d
for a in $(r.stats -n missing_clumps_area); do # for each (large) area
  r.mapcalc "clump_${a} = if(missing_clumps_area == ${a}, 1, null())" --o
  g.region zoom=clump_${a}
  g.region e=e+100000 w=w-100000 s=s-100000 n=n+100000 # expand by +- 100 km
  r.buffer input=clump_${a} output=clump_${a}_buffer distances=100 units=kilometers --o --verbose --o
  g.region -d
done
g.mapset PERMANENT
