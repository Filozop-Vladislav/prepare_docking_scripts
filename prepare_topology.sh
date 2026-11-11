#!/bin/bash

# Step 1: Process lig.itp - remove specific sections correctly
sed -i 's/UNL/lig/g' lig.itp

# Remove [ defaults ] and next 2 lines
sed -i '/\[ *defaults *\]/,+2d' lig.itp

# Remove [ system ] and next line
sed -i '/\[ *system *\]/,+1d' lig.itp

# Remove [ molecules ] and next 2 lines
sed -i '/\[ *molecules *\]/,+2d' lig.itp

# Step 2: Process lig.gro
sed -i 's/UNL/lig/g' lig.gro

# Step 3: Combine protein.gro and lig.gro
# Get atom counts
protein_atoms=$(head -2 protein.gro | tail -1 | tr -d ' ')
lig_atoms=$(head -2 lig.gro | tail -1 | tr -d ' ')
total_atoms=$((protein_atoms + lig_atoms))

# Combine files
{
    # Protein header and coordinates
    head -n -1 protein.gro
    
    # Ligand coordinates without header or box
    tail -n +3 lig.gro | head -n -1
    
    # Box vector from protein
    tail -1 protein.gro
} > combined.gro

# Update atom count in combined file
sed -i "2s/.*/$total_atoms/" combined.gro
mv combined.gro protein.gro

# Step 4: Process protein.top
# Add ligand include after forcefield
if grep -q '#include ".*forcefield.*\.itp"' protein.top; then
    sed -i '/#include ".*forcefield.*\.itp"/a #include "lig.itp"' protein.top
else
    sed -i '1i #include "lig.itp"' protein.top
fi

# Add ligand to molecules section correctly
if grep -q '\[ *molecules *\]' protein.top; then
    # Find the last line of the molecules section and add after it
    awk '
        /\[ *molecules *\]/ {
            print
            in_block = 1
            next
        }
        in_block && /^$/ {
            print "lig     1"
            print ""
            in_block = 0
            next
        }
        in_block && /^\[/ {
            print "lig     1"
            print $0
            in_block = 0
            next
        }
        in_block && !/^;/ {
            last_non_comment = $0
        }
        { print }
        END {
            if (in_block) {
                if (last_non_comment) print last_non_comment
                print "lig     1"
            }
        }
    ' protein.top > temp.top && mv temp.top protein.top
else
    # Create molecules section if missing
    echo -e "\n[ molecules ]\nlig     1" >> protein.top
fi
sed -i '0,/Protein_chain_A     1/{//d;}' protein.top
echo "Processing completed successfully!"
