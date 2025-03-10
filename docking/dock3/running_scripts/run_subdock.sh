#!/bin/bash


if [ "$#" -ne 2 ]; then
    echo "Usage: $0 sdi_file dockfiles_path"
    exit 1
fi
sdi_file="$1"
WORKDIR="$PWD"
DOCKFILES="$2"

# Debug: Print input file contents and existence
echo "Contents of ${sdi_file}:"
cat "${sdi_file}"
echo "---"

# Make sure directories exist
#mkdir -p "${WORKDIR}/dockfiles"
mkdir -p "${WORKDIR}/output_3d_mols_inputs"

export DOCKFILES="${DOCKFILES}"
export DOCKEXEC=/nfs/soft/dock/versions/dock38/executables/dock38_nogist
export SHRTCACHE=/scratch
export LONGCACHE=/scratch

export TMPDIR=/scratch
export SBATCH_EXEC=/usr/bin/sbatch
export SQUEUE_EXEC=/usr/bin/squeue
export SBATCH_ARGS="--time=19:28:00"

# Get base name without .sdi extension
export k=$(basename "${sdi_file}" .sdi)
echo "k ${k}"

# Set absolute paths
export INPUT_SOURCE="${sdi_file}" 
export EXPORT_DEST="${WORKDIR}/output_${k}/${k}"

# Clear any existing output directories that might make the script think the job is complete
rm -rf "${EXPORT_DEST}"
mkdir -p "${EXPORT_DEST}"

# Debug: Print all relevant variables
echo "Debug information:"
echo "WORKDIR: ${WORKDIR}"
echo "DOCKFILES: ${DOCKFILES}"
echo "INPUT_SOURCE: ${INPUT_SOURCE}"
echo "EXPORT_DEST: ${EXPORT_DEST}"
echo "File exists check:"
ls -l "${INPUT_SOURCE}"
echo "File contents:"
cat "${INPUT_SOURCE}"

# Run the subdock script
sh /nfs/soft/dock/versions/dock38/DOCK/ucsfdock/docking/submit/slurm/subdock.bash