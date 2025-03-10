#!/usr/bin/env python3
"""
OUTDOCK Parser - Extracts ZINC IDs and their best (most negative) docking scores
from DOCK3.8 OUTDOCK files.

Usage:
    python parse_outdock.py <outdock_file> [output_file]

If output_file is not specified, results are printed to stdout.
"""

import re
import sys
from collections import defaultdict

def parse_outdock(file_path):
    """
    Parse OUTDOCK file and extract ZINC IDs with their best (most negative) scores.
    
    Args:
        file_path: Path to the OUTDOCK file
        
    Returns:
        Dictionary mapping ZINC IDs to their best scores
    """
    # Dictionary to store best score for each ZINC ID
    best_scores = defaultdict(lambda: 0.0)  # Default to 0 (worse than any negative score)
    
    # Regular expressions for matching
    zinc_pattern = re.compile(r'/ZINC([^/\.]+)')
    score_pattern = re.compile(r'^\s+\d+\s+\S+\s+\d+\s+\d+\s+\d+')
    
    current_zinc_id = None
    
    with open(file_path, 'r') as f:
        for line in f:
            # Check for ZINC ID line
            if '/ZINC' in line:
                zinc_match = zinc_pattern.search(line)
                if zinc_match:
                    current_zinc_id = "ZINC" + zinc_match.group(1)
                continue
            
            # Check for score line (starts with whitespace followed by numbers)
            if score_pattern.match(line):
                fields = line.split()
                if len(fields) >= 21:  # Ensure we have enough fields
                    try:
                        # The total score is the last field
                        score = float(fields[20])
                        if current_zinc_id and score < best_scores[current_zinc_id]:
                            best_scores[current_zinc_id] = score
                    except (ValueError, IndexError):
                        pass  # Skip lines with parsing errors
    
    return best_scores

def main():
    """Main function to handle command line arguments and process the file."""
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <outdock_file> [output_file]")
        sys.exit(1)
    
    outdock_file = sys.argv[1]
    
    try:
        # Parse the OUTDOCK file
        results = parse_outdock(outdock_file)
        
        # Sort results by ZINC ID
        sorted_results = sorted(results.items())
        
        # Prepare output
        output_lines = [f"{zinc_id},{score}" for zinc_id, score in sorted_results]
        output_text = "\n".join(output_lines)
        
        # Write to output file or stdout
        if len(sys.argv) > 2:
            output_file = sys.argv[2]
            with open(output_file, 'w') as f:
                f.write(output_text)
                f.write("\n")  # Add final newline
            print(f"Results written to {output_file}")
        else:
            print(output_text)
            
    except Exception as e:
        print(f"Error processing file {outdock_file}: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()