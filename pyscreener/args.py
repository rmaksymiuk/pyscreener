import os
from pathlib import Path
import shlex

from configargparse import ArgumentParser, ArgumentTypeError, Namespace

def positive_int(arg: str):
    value = int(arg)
    if value <= 0:
        raise ArgumentTypeError('Value must be greater than 0!')
    return value

def add_args(parser: ArgumentParser):
    ### GENERAL ARGS ###
    parser.add_argument('--config', is_config_file=True,
                        help='filepath of a configuration file to use')
    parser.add_argument('--name',
                        help='the base name of the outputs')
    parser.add_argument('--mode', default='docking',
                        choices=['docking', 'md', 'dft'],
                        help='the mode in which to run pyscreener')
    parser.add_argument('--distributed', action='store_true', default=True,
                        help='whether to parallelize computation using a distributed setup')
    parser.add_argument('--nworkers', type=int, metavar='N_WORKERS', default=-1,
                        help='the number of workers to use. (Only used when distributed=False.)')
    
    parser.add_argument('--root', default='.',
                        help='the root directory under which to organize all program outputs')
    parser.add_argument('--tmp', default=os.environ.get('TMP', '.'),
                        help='path to your system\'s TMP directory. If using a distributed setup, this directory must be shared between all machines.')
    parser.add_argument('-v', '--verbose', action='count', default=0,
                        help='the level of output this program should print')

    ### CONVERSION ARGS ###
    parser.add_argument('--no-title-line', default=False, action='store_true',
                        help='whether there is no title line in the ligands csv file')
    parser.add_argument('--start', type=int, default=0,
                        help='the index at which start conversion')
    parser.add_argument('--nconvert', type=int,
                        help='the number of molecules to convert')
    
    ### DOCKING ARGS ###
    parser.add_argument('--docker', default='vina',
                        choices=['vina', 'smina', 'qvina', 'psovina'],
                        help='the name of the docking program to use')
    parser.add_argument('-r', '--receptor', required=True,
                        help='the filename of the receptor')
    parser.add_argument('-l', '--ligands', required=True,
                        help='the name of the file containing the ligand to dock')
    parser.add_argument('-c', '--center', required=True,
                        type=float, nargs=3,
                        metavar=('CENTER_X', 'CENTER_Y', 'CENTER_Z'),
                        help='the x-, y-, and z-coordinates of the center of the docking box')
    parser.add_argument('-s', '--size', required=True,
                        type=int, nargs=3,
                        metavar=('SIZE_X', 'SIZE_Y', 'SIZE_Z'),
                        help='the x-, y-, and z-dimensions of the docking box')
    parser.add_argument('--ncpu', type=int, default=1, metavar='N_CPU',
                        help='the number of cores available to each worker process')
    parser.add_argument('--extra', type=shlex.split,
                        help='extra command line arguments to pass to screening software. E.g., "--exhaustiveness=16"')
    
    ### SCORING/PARSING ARGS ###
    parser.add_argument('--score-mode', default='best',
                        choices={'best', 'avg', 'boltzmann'},
                        help='The method used to calculate the overall score of an individual docking run')
    parser.add_argument('--repeat', type=positive_int, default=1,
                        help='the number of times to repeat each screening run')
    parser.add_argument('--repeat-score-mode', default='best',
                        choices={'best', 'avg', 'boltzmann'},
                        help='The method used to calculate the overall docking score of a molecule')

def gen_args() -> Namespace:
    parser = ArgumentParser(
        description='Automate virtual screening of compound libraries.')
    add_args(parser)
    args = parser.parse_args()

    if args.name is None:
        args.name = f'{Path(args.receptor).stem}_{Path(args.ligands).stem}'
        
    args.title_line = not args.no_title_line
    del args.no_title_line

    return args
