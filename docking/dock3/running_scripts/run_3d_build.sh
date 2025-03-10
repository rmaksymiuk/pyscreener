# #!/bin/bash

# # Check if input file is provided
# if [ "$#" -ne 1 ]; then
#     echo "Usage: $0 input_smiles.txt"
#     exit 1
# fi

# # Set input file from command line argument
# input_file="$1"



# # Check if input file exists
# if [ ! -f "$input_file" ]; then
#     echo "Error: Input file $input_file not found"
#     exit 1
# fi

# # Create personal scratch directory
# export SCRATCH_DIR=$PWD/scratch_3d
# mkdir -p $SCRATCH_DIR

# # Source the environment
# source /nfs/soft/dock/versions/dock38/pipeline_3D_ligands/env.sh

# #DEBUGGING _________________________________________________________
# # After sourcing env.sh
# log "Checking environment:"
# log "SOFT_HOME: ${SOFT_HOME}"
# log "LICENSE_HOME: ${LICENSE_HOME}"
# log "DOCK_VERSION: ${DOCK_VERSION}"
# log "JCHEM_VERSION: ${JCHEM_VERSION}"
# log "PYENV_VERSION: ${PYENV_VERSION}"
# #DEBUGGING _________________________________________________________

# # Set up environment variables
# export INPUT_FILE=$input_file
# export OUTPUT_DEST=$PWD/output_3d
# export TMPDIR=$SCRATCH_DIR
# export SHRTCACHE=$SCRATCH_DIR
# export LONGCACHE=$SCRATCH_DIR

# # Settings for small molecule set
# export LINES_PER_BATCH=100    
# export LINES_PER_JOB=25      
# export MAX_BATCHES=1         
# export SBATCH_ARGS="--time=02:00:00"  

# # Create output directory
# mkdir -p $OUTPUT_DEST

# #DEBUGGING _________________________________________________________
# log "Input file contents (first 5 lines):"
# echo "----------------------------------------"
# head -n 5 "${INPUT_FILE}"
# echo "----------------------------------------"
# echo "Total lines in input file: $(wc -l < "${INPUT_FILE}")"
# #DEBUGGING _________________________________________________________

# # Print settings for verification
# echo "Settings:"
# echo "Input file: $INPUT_FILE"
# echo "Output directory: $OUTPUT_DEST"
# echo "Scratch directory: $SCRATCH_DIR"
# echo "Molecules per batch: $LINES_PER_BATCH"
# echo "Molecules per job: $LINES_PER_JOB"
# echo "Number of batches: $MAX_BATCHES"
# echo "SLURM time limit: $SBATCH_ARGS"

# # Submit jobs
# echo "Submitting jobs..."
# submit-all-jobs-slurm.bash

# echo "Jobs submitted. Monitor progress with: squeue -u \$USER"


# #DEBUGGING _________________________________________________________
# # Get the job ID and check its status
# JOB_ID=$(squeue -h -u $USER -n batch_3d -o "%A" | tail -1)
# if [ -n "${JOB_ID}" ]; then
#     log "Job submitted with ID: ${JOB_ID}"
    
#     # Wait a few seconds for job to start
#     sleep 5
    
#     # Check job status
#     STATUS=$(squeue -h -j "${JOB_ID}" -o "%t")
#     if [ -n "${STATUS}" ]; then
#         log "Job status: ${STATUS}"
#     else
#         log "ERROR: Job not found in queue. Checking completion status..."
#         COMPLETION_STATUS=$(sacct -j "${JOB_ID}" --format=State -n | head -1 | tr -d ' ')
#         log "Job completion status: ${COMPLETION_STATUS}"
        
#         # Check error logs
#         ERR_FILES="${OUTPUT_DEST}/input.smi.batch-3d.d/log/aaa.d/*.err"
#         for err_file in ${ERR_FILES}; do
#             if [ -f "${err_file}" ]; then
#                 log "Contents of error file ${err_file}:"
#                 cat "${err_file}"
#             fi
#         done
#         exit 1
#     fi
#     echo "job_id=${JOB_ID}"
# else
#     log "ERROR: Failed to submit job"
#     exit 1
# fi
# #DEBUGGING _________________________________________________________



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
