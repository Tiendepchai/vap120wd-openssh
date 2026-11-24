#!/bin/sh

# Source directory
src_dir="/tmp/log"

# Iterate through all files in the source directory
for file in "$src_dir"/*; do
    if [ -f "$file" ]; then
        # Check if it's a regular file
        file_name=$(basename "$file")
        new_file="$src_dir/${file_name}.old"
        
        # Copy the file to a new file with the .old extension
        cp "$file" "$new_file"
        
        if [ $? -eq 0 ]; then
            echo "Copied $file to $new_file"
        else
            echo "Error copying $file"
        fi

        /usr/sbin/backup_log "$file"
        logger "backup log success for downloading $file"
        rm -f ${new_file}
        echo "rm $new_file"
    fi
done
