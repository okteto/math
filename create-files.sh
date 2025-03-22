#!/bin/bash

# Create directory to store the files
mkdir -p test_files

# Set the file size (1MB = 1048576 bytes)
file_size=1048576

# Use /dev/zero as the source for faster file creation
# dd is much faster than using a loop with echo/printf

for i in {1..1000}; do
  dd if=/dev/zero of="test_files/file_$i.dat" bs=$file_size count=1 2>/dev/null

  # Print progress every 100 files
  if (( i % 100 == 0 )); then
    echo "Created $i files..."
  fi
done

echo "Done! Created 1000 files of 1MB each in the test_files directory."
