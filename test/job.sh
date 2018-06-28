#!/bin/bash
set -x
old_file=$1
new_file=$2
mkdir -p $SGE_DATA_OUT
if [ ! -z "$new_file" ]; then
  touch $SGE_DATA_OUT/$new_file
fi
if [ ! -z "$old_file" ]; then
  cp $SGE_DATA_IN/$old_file $SGE_DATA_OUT
fi
# copy all input file to output directory
#cp $SGE_DATA_IN/* 
