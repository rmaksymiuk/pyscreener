#!/bin/bash

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Get absolute path of input file and working directory
INPUT_FILE=$(readlink -f "$1")
WORK_DIR=$(dirname "${INPUT_FILE}")
cd "${WORK_DIR}"

log "Using absolute input file path: ${INPUT_FILE}"
log "Working directory: ${WORK_DIR}"

# Create scratch directory
export SCRATCH_DIR="${WORK_DIR}/scratch_3d"
mkdir -p "${SCRATCH_DIR}"

# Source the environment
source /nfs/soft/dock/versions/dock38/pipeline_3D_ligands/env.sh

# Set up environment variables with absolute paths
export INPUT_FILE  # This is now the absolute path
export OUTPUT_DEST="${WORK_DIR}/output_3d"
export TMPDIR="${SCRATCH_DIR}"
export SHRTCACHE="${SCRATCH_DIR}"
export LONGCACHE="${SCRATCH_DIR}"

# Settings for small molecule set
export LINES_PER_BATCH=20000    
export LINES_PER_JOB=50      
export MAX_BATCHES=1000         
#export SBATCH_ARGS="--time=05:00:00"  

# Create output directory
mkdir -p "${OUTPUT_DEST}"

# Print settings for verification
log "Settings:"
echo "Input file: ${INPUT_FILE}"
echo "Output directory: ${OUTPUT_DEST}"
echo "Scratch directory: ${SCRATCH_DIR}"
echo "Molecules per batch: ${LINES_PER_BATCH}"
echo "Molecules per job: ${LINES_PER_JOB}"
echo "Number of batches: ${MAX_BATCHES}"
echo "SLURM time limit: ${SBATCH_ARGS}"

# Print input file contents for verification
log "Input file contents (first 5 lines):"
echo "----------------------------------------"
head -n 5 "${INPUT_FILE}"
echo "----------------------------------------"
log "Total lines in input file: $(wc -l < "${INPUT_FILE}")"

# Submit jobs
log "Submitting jobs..."
submit-all-jobs-slurm.bash
