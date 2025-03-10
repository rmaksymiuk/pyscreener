from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from pyscreener.docking.metadata import SimulationMetadata

@dataclass(repr=True, eq=False)
class DOCK3Metadata(SimulationMetadata):
    # Only need minimal settings since scripts handle everything else
    work_dir: Optional[Path] = None  # Where to run the pipeline