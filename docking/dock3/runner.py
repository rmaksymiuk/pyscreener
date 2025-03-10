import os
from pathlib import Path
import subprocess as sp
from typing import List, Optional
import warnings

from pyscreener.exceptions import MissingEnvironmentVariableError
from pyscreener.docking import DockingRunner, Result, Simulation
from .metadata import DOCK3Metadata

class DOCK3Runner(DockingRunner):
    def __init__(self, dockfiles=None, **kwargs):
        super().__init__()
        # Path to dockfiles from config
        self.dockfiles = Path(dockfiles) if dockfiles else None
        if not self.dockfiles or not self.dockfiles.exists():
            raise ValueError(f"Invalid dockfiles path: {dockfiles}")
        
        # Path to pipeline scripts (fixed location in package)
        self.scripts_dir = Path(__file__).parent / "running_scripts"
        self.pipeline_script = self.scripts_dir / "run_pipeline.sh"
        if not self.pipeline_script.exists():
            raise ValueError(f"Pipeline script not found at {self.pipeline_script}")
        
        # Make sure all required scripts are present
        required_scripts = ["run_3d_build.sh", "make_tarballs.bash", "run_subdock.sh"]
        for script in required_scripts:
            if not (self.scripts_dir / script).exists():
                raise ValueError(f"Required script {script} not found in {self.scripts_dir}")

    def run(self, sim: Simulation) -> Optional[List[float]]:
        """Run DOCK3.8 pipeline"""
        try:
            # Working directory is simulation's temporary directory
            working_dir = sim.tmp_dir
            
            # Create input SMILES file
            input_file = working_dir / f"{sim.name}.smi"
            with open(input_file, 'w') as f:
                f.write(f"{sim.smi}\tZINC{sim.name}\n")  # Format: SMILES\tZINCID

            # Copy necessary scripts to working directory
            for script in self.scripts_dir.glob("*.sh"):
                shutil.copy2(script, working_dir)
                # Make executable
                os.chmod(working_dir / script.name, 0o755)

            # Run pipeline
            cmd = [
                str(working_dir / "run_pipeline.sh"),
                str(input_file.name),  # Just filename since we're in working_dir
            ]
            
            proc = sp.run(
                cmd,
                cwd=working_dir,
                stdout=sp.PIPE,
                stderr=sp.PIPE,
                encoding="utf-8",
                env={
                    **os.environ,
                    "DOCKFILES": str(self.dockfiles)
                },
                check=True
            )
            
            # Parse results
            results_file = working_dir / "results.smi"
            return self.parse_results(results_file)
            
        except Exception as e:
            warnings.warn(f"DOCK3.8 pipeline failed: {str(e)}")
            return None

    def parse_results(self, results_file: Path) -> Optional[List[float]]:
        """Parse DOCK3.8 results file"""
        try:
            if not results_file.exists():
                raise FileNotFoundError(f"Results file not found: {results_file}")
                
            with open(results_file) as f:
                scores = []
                for line in f:
                    if line.strip():
                        try:
                            zinc_id, score = line.strip().split(',')
                            scores.append(float(score))
                        except ValueError as e:
                            warnings.warn(f"Failed to parse line: {line.strip()}")
                            continue
                return scores if scores else None
        except Exception as e:
            warnings.warn(f"Failed to parse results: {str(e)}")
            return None

    @classmethod
    def is_multithreaded(cls) -> bool:
        """Indicate that we're using SLURM for parallel processing"""
        return True