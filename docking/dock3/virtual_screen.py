import os
import subprocess
import tempfile
import warnings
from pathlib import Path
from typing import List, Optional, Union
from dataclasses import dataclass
import pandas as pd
import time
import numpy as np
import shutil
from datetime import datetime

@dataclass
class DockingResult:
    """Store docking results"""
    smiles: str
    zinc_id: str
    score: float

class DOCK3VirtualScreen:
    """Simplified virtual screen for DOCK3.8"""
    def __init__(self, 
                 screen_type=None,
                 dockfiles=None,
                 pipeline_scripts=None,
                 ncpu=1,
                 library_file=None,
                 output_dir: Optional[Union[str, Path]] = None):
        #These 5 are the most important parameters in objective file
        self.dockfiles = Path(dockfiles)
        self.library_file = Path(library_file)
        self.scripts_dir = Path(__file__).parent / "running_scripts"
        self.screen_type = screen_type
        #not sure if needed
        self.ncpu = ncpu
        
        # Create temp directory inside dock3 folder
        self.temp_dir = Path(__file__).parent / "temp"
        if self.temp_dir.exists():
            shutil.rmtree(self.temp_dir)  # Clean up any existing temp directory
        self.temp_dir.mkdir(exist_ok=True)
        
        # Copy scripts to temp directory
        for ext in ["*.sh", "*.bash", "*.py"]:
            for script in self.scripts_dir.glob(ext):
                shutil.copy2(script, self.temp_dir)
                os.chmod(self.temp_dir / script.name, 0o755)
        
        # Results directory
        default_output = f'pyscreener_{datetime.now().strftime("%Y-%m-%d_%H-%M-%S")}'
        self.path: Path = Path(output_dir if output_dir is not None else default_output)
        self.path.mkdir(exist_ok=True, parents=True)
        
        self._results: List[DockingResult] = []
        self._current_tmp_dir: Optional[Path] = None

        # Validate paths
        if not self.dockfiles.exists():
            raise ValueError(f"Invalid dockfiles path: {dockfiles}")
        if not self.scripts_dir.exists():
            raise ValueError(f"Invalid scripts path: {self.scripts_dir}")
            
        # Validate required scripts
        required_scripts = ["run_pipeline.sh", "run_3d_build.sh", "make_tarballs.bash", "run_subdock.sh", "parse_outdock.py"]
        for script in required_scripts:
            if not (self.scripts_dir / script).exists():
                raise ValueError(f"Required script not found: {script}")

    def __call__(self, smis: List[str]) -> np.ndarray:
        """Match original VirtualScreen interface"""
        try:
            print("Starting __call__")
            
            # Ensure temp directory exists
            self.temp_dir = Path(__file__).parent / "temp"
            if not self.temp_dir.exists():
                print(f"Recreating temp directory: {self.temp_dir}")
                self.temp_dir.mkdir(exist_ok=True)
                
                # Copy scripts to temp directory
                for ext in ["*.sh", "*.bash", "*.py"]:
                    for script in self.scripts_dir.glob(ext):
                        shutil.copy2(script, self.temp_dir)
                        os.chmod(self.temp_dir / script.name, 0o755)
            
            # Create DataFrame from selected SMILES
            df_selected = pd.DataFrame({'smiles': smis})
            
            # Read library in chunks to save memory
            chunk_size = 1_000_000  # Adjust based on available RAM
            matched_pairs = []

            # Use a set to track unique pairs during processing
            seen_pairs = set()
            unique_pairs = []
            duplicate_count = 0
            
            for chunk in pd.read_csv(self.library_file,
                                usecols=['smiles', 'zincid'],
                                chunksize=chunk_size):
                
                # Merge current chunk with selected SMILES
                matches = pd.merge(df_selected, chunk, 
                                on='smiles', 
                                how='inner')
                
                if not matches.empty:
                    # Process each pair to ensure uniqueness
                    for pair in matches[['smiles', 'zincid']].values:
                        # Convert pair to tuple for hashing
                        pair_tuple = tuple(pair)
                        
                        # Only add if we haven't seen this pair before
                        if pair_tuple not in seen_pairs:
                            seen_pairs.add(pair_tuple)
                            unique_pairs.append(pair)
                            # Also add to matched_pairs for later use
                            matched_pairs.append(pair)
                        else:
                            duplicate_count += 1
            
            # Report duplicates
            if duplicate_count > 0:
                print(f"Found and skipped {duplicate_count} duplicate (smiles, zincid) pairs")
            
            print(f"Processing {len(unique_pairs)} unique (smiles, zincid) pairs")
            
            # Clear previous results
            self._results = []
            
            # Create mappings for results tracking
            smi_to_idx = {smi: i for i, smi in enumerate(smis)}
            zincid_to_result = {}
            
            # Initialize the results list
            for smi, zincid in unique_pairs:
                result = DockingResult(
                    smiles=smi,
                    zinc_id=zincid,
                    score=None  # Initially set to None
                )
                self._results.append(result)
                zincid_to_result[zincid] = result
            
            # Write unique pairs to input.smi
            input_basename = "input.smi"
            input_file = self.temp_dir / input_basename
            data = np.array(unique_pairs)
            np.savetxt(input_file, data, fmt='%s', delimiter='\t')
            print(f"Input file saved to: {input_file}")
            
            # Run pipeline with explicit bash and foreground execution
            print("\nRunning pipeline...")
            try:
                # Run pipeline with basename
                cmd = [
                    "bash",
                    str(self.temp_dir / "run_pipeline.sh"),
                    str(input_basename),  # Use basename instead of full path
                    str(self.dockfiles)
                ]
                print(f"Running command: {' '.join(cmd)}")
                
                result = subprocess.run(
                    cmd,
                    cwd=self.temp_dir,
                    env={**os.environ},
                    shell=False,
                    check=True,
                    capture_output=True,
                    text=True
                )
                
                print("Pipeline completed with return code:", result.returncode)
                print("\nPipeline stdout:")
                print(result.stdout)
                print("\nPipeline stderr:")
                print(result.stderr)
                
            except subprocess.CalledProcessError as e:
                print(f"Pipeline failed with return code: {e.returncode}")
                print(f"Pipeline stdout:\n{e.stdout}")
                print(f"Pipeline stderr:\n{e.stderr}")
                raise
            
            # Check if results file exists
            results_file = self.temp_dir / "results.smi"
            if not results_file.exists():
                print(f"Contents of {self.temp_dir}:")
                for f in self.temp_dir.glob('*'):
                    print(f"  {f}")
                raise FileNotFoundError(f"Pipeline did not create {results_file}")
            
            # Initialize scores array with NaN
            scores = np.full(len(smis), np.nan)
            
            # Track processed zinc IDs and missing zinc IDs
            processed_zincids = set()
            missing_zincids = set()
            
            # Read results and match back to original SMILES order
            results_file = self.temp_dir / "results.smi"
            print(f"Reading results from: {results_file}")
            
            # Count lines in results file
            result_count = 0
            with open(results_file) as f:
                for _ in f:
                    result_count += 1
            print(f"Found {result_count} entries in results.smi")
            
            # Process results
            with open(results_file) as f:
                for line in f:
                    parts = line.strip().split(",")
                    if len(parts) >= 2:
                        zinc_id, score = parts[0], parts[1]
                        try:
                            score = float(score)
                            processed_zincids.add(zinc_id)
                            
                            # Update the corresponding result in _results
                            if zinc_id in zincid_to_result:
                                zincid_to_result[zinc_id].score = score
                            else:
                                missing_zincids.add(zinc_id)
                                # Create a new result entry for this zinc_id
                                # We need to find the corresponding SMILES if possible
                                print(f"Found result for zinc_id {zinc_id} not in our tracking dictionary")
                        except ValueError:
                            print(f"Warning: Could not parse score from line: {line.strip()}")
            
            # Report on results processing
            print(f"Processed {len(processed_zincids)} zinc IDs from results file")
            print(f"Missing {len(missing_zincids)} zinc IDs that were in results but not in our tracking")
            print(f"Current _results list has {len(self._results)} entries")
            
            # Check for zinc IDs that were in our tracking but not in results
            tracked_but_not_processed = set(zincid_to_result.keys()) - processed_zincids
            if tracked_but_not_processed:
                print(f"Warning: {len(tracked_but_not_processed)} zinc IDs were tracked but not found in results")
            
            # Copy results to permanent storage
            self.collect_files()
            
            # Write full results to the output directory
            full_results_path = self.path / "full_results.txt"
            with open(full_results_path, "w") as f:
                for result in self._results:
                    score_str = f"{result.score:.2f}" if result.score is not None else "None"
                    f.write(f"SMILES: {result.smiles} ZINC ID: {result.zinc_id} Score: {score_str}\n")
            
            print(f"Wrote {len(self._results)} results to {full_results_path}")
            
            # Clean up temp directory
            if self.temp_dir.exists():
                print(f"Cleaning up temp directory: {self.temp_dir}")
                shutil.rmtree(self.temp_dir)
            
            # Populate scores array for return
            for result in self._results:
                if result.score is not None and result.smiles in smi_to_idx:
                    scores[smi_to_idx[result.smiles]] = result.score
                
            return scores
                
        except Exception as e:
            # Clean up temp directory even if there's an error
            if hasattr(self, 'temp_dir') and self.temp_dir.exists():
                shutil.rmtree(self.temp_dir)
                pass
            warnings.warn(f"DOCK3.8 failed(virtual_screen()): {e}")
            return np.array([np.nan] * len(smis))
    
    
    def results(self) -> List[DockingResult]:
        """Return stored docking results"""
        return self._results

    
    def collect_files(self):
            """Copy important files from temp directory to permanent storage"""
            if self.temp_dir and self.temp_dir.exists():
                # Generate timestamp for unique filenames
                timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
                
                # Copy results file with timestamp
                if (self.temp_dir / "results.smi").exists():
                    results_file = self.path / f"results_{timestamp}.smi"
                    shutil.copy2(
                        self.temp_dir / "results.smi",
                        results_file
                    )
                
                # Copy log files with timestamp
                for log_file in self.temp_dir.glob("*.log"):
                    new_name = f"{log_file.stem}_{timestamp}{log_file.suffix}"
                    shutil.copy2(log_file, self.path / new_name)
    