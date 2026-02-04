#!/usr/bin/env bash

#!/bin/bash

# Define the output file name
OUTPUT_FILE="gpg-list.asc"

for file in ./gpg/*.asc; do
    # Check if it is a regular file
    # Exclude the output file itself and the script itself to prevent recursion/errors
    if [ -f "$file" ]; then
        
        # Append content to output
        cat "$file" >> "$OUTPUT_FILE"

        # $(tail -c 1 "$file") gets the last byte. 
        # If it was a newline, Bash strips it -> string is empty.
        # If it was text, the string is NOT empty.
        if [ -n "$(tail -c 1 "$file")" ]; then
            # If not empty, it means the file didn't end with \n, so we add one.
            echo "" >> "$OUTPUT_FILE"
        fi
    fi
done

echo "Done! All ASC files merged into $OUTPUT_FILE"

# Update checksum file
sha256sum ./gpg-list.asc ./configs/* ./scripts/* >checksum.sha256

