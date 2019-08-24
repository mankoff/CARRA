#!/bin/bash
# Pre-process: Setup Environment
# :PROPERTIES:
# :header-args: :tangle CARRA_pre.sh
# :END:

# Run this setup code 1x as:

# Generic example:
# =grass74 -c <projection> <GRASS_FOLDER> --exec ./CARRA_pre.sh=

# Specific example:
# =grass74 -c EPSG:32635 ./GRASS_Svalbard --exec ./CARRA_pre.sh=




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
