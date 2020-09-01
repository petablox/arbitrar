#!/bin/sh

temp_folder="a2bc_temp"
ar="$1"
base=$(basename "$ar" .a)
bca="$base.bca"
abc="$base.a.bc"

echo "Making temporary folder"
mkdir -p $temp_folder

echo "Generating $temp_folder/$bca from $ar"
extract-bc $ar
mv $bca $temp_folder/$bca

echo "Going into the temp folder"
cd $temp_folder

echo "Unarchiving $bca"
llvm-ar x $bca

echo "Linking all bc files into $abc"
find . -iname "*.o.bc" -print0 | xargs -0 llvm-link -o $abc

cd ../

mv $temp_folder/$abc $abc
rm -rf $temp_folder
