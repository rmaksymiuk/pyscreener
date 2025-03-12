#!/bin/bash

set -euo pipefail

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup_scratch() {
    local scratch_path="${WORK_DIR}/scratch_3d"
    
    if [[ -d "$scratch_path" ]]; then
        log "Removing scratch directory: $scratch_path"
        rm -rf "$scratch_path" || {
            log "WARNING: rm -rf failed, trying alternative cleanup"
            find "$scratch_path" -depth -type f -delete
            find "$scratch_path" -depth -type d -delete
        }
    fi
    
    log "Creating fresh scratch directory"
    mkdir -p "$scratch_path"
    export SCRATCH_DIR="$scratch_path"
}

# Define variables
INPUT_FILE=$1 #"test_zinc22i.smi"
DOCKFILES=$2
WORK_DIR=$(pwd)

export -f log

# #INPUT_FILE=$(realpath "${INPUT_FILE}")  # Convert to absolute path
# INPUT_BASENAME=$(basename "${INPUT_FILE}")


INPUT_FILE="${WORK_DIR}/${INPUT_FILE}"  # Make it absolute path
INPUT_BASENAME=$(basename "${INPUT_FILE}")


echo "WORK_DIR: ${WORK_DIR}"
echo "DOCKFILES: ${DOCKFILES}"
DATE_STAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="pipeline_log.log"
mkdir -p "${WORK_DIR}/tarballs_repacked"

main() {
    log "Starting pipeline with input file: ${INPUT_FILE}"
    
    # Step 1: Run 3D build - this submits SLURM jobs
    log "Running 3D build step"
    ./run_3d_build.sh "${INPUT_BASENAME}"

    # Wait for 3D build jobs to complete
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for 3D build jobs to complete..."
    sleep 60  # Give jobs time to enter the queue

    # Set a counter for resubmission checks
    resubmit_counter=0
    # Track requeued jobs to avoid infinite loops
    declare -A requeued_jobs
    max_requeue_attempts=3

    # Wait for all batch_3d jobs to complete
    while true; do
        # Check for jobs in any state (including CG)
        running_jobs=$(squeue -u $USER -n batch_3d -h | wc -l)
        
        # Specifically check for jobs in CG state
        completing_jobs=$(squeue -u $USER -n batch_3d -t COMPLETING -h | wc -l)
        
        # Count jobs in RUNNING state
        active_running_jobs=$(squeue -u $USER -n batch_3d -t RUNNING -h | wc -l)
        
        # If there are only completing jobs and they've been there for a while, we might need to force cleanup
        if [ $running_jobs -eq $completing_jobs ] && [ $completing_jobs -gt 0 ]; then
            # Track how long jobs have been in CG state
            if [ -z "${cg_wait_start:-}" ]; then
                cg_wait_start=$(date +%s)
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detected ${completing_jobs} jobs in COMPLETING state, starting timer"
            else
                current_time=$(date +%s)
                cg_wait_duration=$((current_time - cg_wait_start))
                
                # If jobs have been in CG state for more than 10 minutes (600 seconds), try to force cleanup
                if [ $cg_wait_duration -gt 600 ]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Jobs stuck in COMPLETING state for >10 minutes. Attempting force cleanup..."
                    
                    # Get list of jobs in CG state
                    cg_job_ids=$(squeue -u $USER -n batch_3d -t COMPLETING -h -o "%i")
                    
                    for job_id in $cg_job_ids; do
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempting to force cleanup of job ${job_id}"
                        # Try scancel with --signal=KILL for more forceful termination
                        scancel --signal=KILL $job_id
                    done
                    
                    # Reset timer and wait a bit to see if it worked
                    unset cg_wait_start
                    sleep 60
                    
                    # Check if jobs are still in CG state
                    still_completing=$(squeue -u $USER -n batch_3d -t COMPLETING -h | wc -l)
                    if [ $still_completing -gt 0 ]; then
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${still_completing} jobs still stuck in COMPLETING state"
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Will proceed with pipeline anyway, but this may cause issues"
                        break  # Proceed with pipeline even if jobs are stuck
                    fi
                else
                    # Report how long we've been waiting
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for ${completing_jobs} jobs in COMPLETING state (${cg_wait_duration} seconds so far)"
                fi
            fi
        else
            # Reset CG wait timer if there are no completing jobs or there are other job states
            unset cg_wait_start
            
            # Every 30 minutes, check for stuck jobs that have been running too long
            if [ $((resubmit_counter % 30)) -eq 0 ] && [ $resubmit_counter -gt 0 ] && [ $active_running_jobs -gt 0 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking for stuck jobs..."
                
                # Find jobs running for more than 1 hour (3600 seconds)
                # Format: JobID StartTime
                stuck_jobs=$(squeue -u $USER -n batch_3d -t RUNNING -h -o "%i %S" | 
                             while read job_id start_time; do
                                 start_epoch=$(date -d "$start_time" +%s)
                                 current_epoch=$(date +%s)
                                 runtime=$((current_epoch - start_epoch))
                                 
                                 # If running more than 1 hour and hasn't been requeued too many times
                                 if [ $runtime -gt 3600 ] && [ "${requeued_jobs[$job_id]:-0}" -lt $max_requeue_attempts ]; then
                                     echo "$job_id"
                                 fi
                             done)
                
                if [ -n "$stuck_jobs" ]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Requeuing stuck jobs running for >1 hour: $stuck_jobs"
                    for job in $stuck_jobs; do
                        # Increment requeue counter for this job
                        requeued_jobs[$job]=$((${requeued_jobs[$job]:-0} + 1))
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Requeuing job $job (attempt ${requeued_jobs[$job]}/$max_requeue_attempts)"
                        scontrol requeue $job
                    done
                fi
            fi
        fi
        
        # Check if all jobs are done
        if [ $running_jobs -eq 0 ]; then
            # Double check after a short wait to avoid race conditions
            sleep 10
            running_jobs=$(squeue -u $USER -n batch_3d -h | wc -l)
            if [ $running_jobs -eq 0 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] All 3D build jobs completed."
                break
            fi
        fi
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${running_jobs} batch_3d jobs still running, waiting..."
        sleep 60
        resubmit_counter=$((resubmit_counter + 1))
    done
  



    # Step 2: Make tarballs
    log "Creating tarballs"
    OUTPUT_3D_DIR="${WORK_DIR}/output_3d/${INPUT_BASENAME}.batch-3d.d/out"
    log "Checking output directory: ${OUTPUT_3D_DIR}"
    if [ ! -d "${OUTPUT_3D_DIR}" ]; then
        log "Output directory contents:"
        ls -la "${WORK_DIR}/output_3d"
        exit 1
    fi

    OUTPUT_3D_DIR="${WORK_DIR}/output_3d/${INPUT_BASENAME}.batch-3d.d/out"
    ./make_tarballs.bash "${OUTPUT_3D_DIR}" "${WORK_DIR}/tarballs_repacked"

    # Step 2.5: Aggregating all db2.tar.gz files into a single file
    log "Aggregating tarballs"
    find ${WORK_DIR}/tarballs_repacked -type f -name '*.db2.tar.gz' > 3d_mols_inputs.sdi
    
    echo "Sleeping for 60 second before running subdock"
    sleep 60
    # Step 3: Run subdock - this submits SLURM jobs
    log "Running subdock"
    if [ -s "${WORK_DIR}/3d_mols_inputs.sdi" ]; then
        # Debug output
        log "Content of 3d_mols_inputs.sdi:"
        cat "${WORK_DIR}/3d_mols_inputs.sdi"
        
        # Run subdock with absolute path
        cd "${WORK_DIR}"  # Make sure we're in the right directory
        ./run_subdock.sh "3d_mols_inputs.sdi" "${DOCKFILES}"  # Use relative path here
    else
        log "ERROR: No .db2.tar.gz files found in tarballs_repacked"
        exit 1
    fi
    
    # Wait for subdock jobs to complete
    log "Waiting for subdock jobs to complete..."
    while squeue -h -u $USER | grep -q "dock"; do
        sleep 60
    done
    
    # Add additional wait time and file existence check
    log "SLURM jobs completed. Waiting for output files to be written..."
    MAX_WAIT=600  # 5 minutes
    WAIT_INTERVAL=10  # 10 seconds
    OUTDOCK_DIR="${WORK_DIR}/output_3d_mols_inputs/3d_mols_inputs"
    TARGET_DIR="${OUTDOCK_DIR}/1" 
    
    # Wait for OUTDOCK files to appear
    WAIT_TIME=0
    while [ $WAIT_TIME -lt $MAX_WAIT ]; do
        # Check if any OUTDOCK files exist
        OUTDOCK_COUNT=$(find "${OUTDOCK_DIR}" -name "OUTDOCK.0" -type f | wc -l)
        
        # Print contents of TARGET_DIR
        log "Contents of ${TARGET_DIR} at ${WAIT_TIME}s:"
        ls -la "${TARGET_DIR}" 2>&1 || log "  Directory does not exist or cannot be accessed"
        
        if [ $OUTDOCK_COUNT -gt 0 ]; then
            log "Found ${OUTDOCK_COUNT} OUTDOCK files. Proceeding with processing."
            break
        fi
        
        log "No OUTDOCK files found yet. Waiting ${WAIT_INTERVAL} seconds... (${WAIT_TIME}/${MAX_WAIT})"
        sleep $WAIT_INTERVAL
        WAIT_TIME=$((WAIT_TIME + WAIT_INTERVAL))
    done

    if [ $WAIT_TIME -ge $MAX_WAIT ]; then
        log "WARNING: Timed out waiting for OUTDOCK files. Will attempt to process anyway."
    fi
    
    # Step 4: Process OUTDOCK files (keeping this part unchanged)
    log "Processing OUTDOCK files"
    # Base directory for OUTDOCK files
    BASE_DIR="output_3d_mols_inputs/3d_mols_inputs"
    RESULTS_FILE="results.smi"
    
    # Initialize empty results file
    > "${RESULTS_FILE}"
    
    # Loop through all numbered directories
    for dir in "${BASE_DIR}"/*/; do
        if [[ -d "${dir}" ]]; then
            OUTDOCK_FILE="${dir}OUTDOCK.0"
            
            if [ -f "${OUTDOCK_FILE}" ]; then
                log "Processing ${OUTDOCK_FILE}"
                python3 parse_outdock.py "${OUTDOCK_FILE}" >> "${RESULTS_FILE}"
            else
                log "Warning: OUTDOCK file not found at ${OUTDOCK_FILE}"
            fi
        fi
    done
    
    if [ -s "${RESULTS_FILE}" ]; then
        log "Results saved to ${RESULTS_FILE}"
    else
        log "ERROR: No OUTDOCK file results were written to Results.smi"
        exit 1
    fi

    #Cleaning up the uncessesary files
    log "Cleaning up..."
    rm -rf "${WORK_DIR}/output_3d"
    rm -rf "${WORK_DIR}/output_3d_mols_inputs"
    rm -rf "${WORK_DIR}/tarballs_repacked"
    #cleaning up the scratch directory
    cleanup_scratch
    rm -rf "${WORK_DIR}/3d_mols_inputs.sdi"
    log "Pipeline completed successfully"
}

#Running the pipeline directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Create the log file name and export it
    export DATE_STAMP=$(date '+%Y%m%d_%H%M%S')
    export LOG_FILE="pipeline_${DATE_STAMP}.log"
    
    # Create empty log file
    touch "${LOG_FILE}"
    
    # Run the pipeline directly
    main "$@" 2>&1 | tee "${LOG_FILE}"
fi
