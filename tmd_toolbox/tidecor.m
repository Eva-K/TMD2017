%
% Script to run 'tmd_tide_pred.m' in parallel on several HDF5 files.
%
% This script facilitates the use of the Matlab Tide Model Driver (TMD):
% 
%    https://www.esr.org/research/polar-tide-models/tmd-software/
%
% To edit in the code:
%   - path to input HDF5 data file(s)
%   - path to tide and load model control files
%   - names/cols of variables: lon, lat, time, height
%   - reference epoch for time in seconds
% 
% To run from Terminal:
%   /path/to/matlab -nodesktop < tidecor.m
% 
% To run from Matlab GUI:
%   tidecor
%
% Units of input variables:
%   lon (deg)
%   lat (deg)
%   time (secs since epoch)
%   height (m)
%
% Parallelization:
%   * Parallelization is done externally from the original TMD code
%     (i.e. running this script on each input file).
%   * For optimal efficiency, merge/split the input files into N files,
%     with N equal number of cores (even if the files end up fairly large).
%
% Notes:
%   * Some original Matlab scripts were modified to improve performance.
%     These modifications include replacing loops by vectorization, and
%     improving the I/O for multiple data files.
%   * Changes were made by Alex Gardner and Fernando Paolo, and they are
%     marked in the code.
% 
% Fernando Paolo <paolofer@jpl.nasa.gov>
% Jun 29, 2017 

clear ALL
tic;
%-----------------------------------------------------------
% Edit here
%-----------------------------------------------------------

% Path to input data file(s)
PATH = '/Users/paolofer/data/envisat/floating/merged_*.h5';

% Number of parallel jobs
NJOBS = 4;

% Name of variables if HDF5 files
XVAR = '/lon'; 
YVAR = '/lat';
TVAR = '/t_sec';
ZVAR = '/h_res';

% DEPRECATED (use HDF5 only)
% Columns of x/y/t if ASCII files (Matlab uses 1-based indexing!)
XCOL = 4;
YCOL = 3;
TCOL = 2;

% Days from 0000-Jan-1 to the reference epoch (Y, M, D, h, m, s)
REFTIME = datenum(1, 1, 1);  %NOTE: Double check this!

% Path to tide model
TIDEMODEL = 'DATA/Model_CATS2008a_opt';

% Path to load-tide model
LOADMODEL = 'DATA/Model_tpxo7.2_load';

% Path to TMD functions
addpath('FUNCTIONS')

%-----------------------------------------------------------

% Get list of file names (from structure array)
list = dir(PATH);
files = {list.name}';

% Prepend path to file names (with list comprehension)
files = cellfun(@(x) fullfile(fileparts(PATH), x), files, 'UniformOutput', false);

% Start pool of workers
pool = gcp('nocreate');
if isempty(pool)
    parpool(NJOBS);
end

% Process files in parallel (parallel for loop)
parfor i = 1:length(files)

    infile = files{i}

    fprintf('processing file: %s ...\n', infile);

    % Get variables from file
    x = h5read(infile, XVAR);
    y = h5read(infile, YVAR);
    t = h5read(infile, TVAR);
    h = h5read(infile, ZVAR);

    %% Loads ASCII file into matrix
    %data = dlmread(infile);

    %lon = data(:,XCOL);
    %lat = data(:,YCOL);
    %time = data(:,TCOL);

    % Serial date number = number of days from 0000-Jan-1
    SDtime = (t/86400.) + REFTIME;    

    % Predict tide values using the TMD toolbox
    [z, conList] = tmd_tide_pred(TIDEMODEL, SDtime, y, x, 'z');
    [l, conList] = tmd_tide_pred(LOADMODEL, SDtime, y, x, 'z');

    % Make sure dimensions correspond
    z = reshape(z, length(z), 1);
    l = reshape(l, length(z), 1);

    % Change NaN -> 0
    z(isnan(z)) = 0;                    
    l(isnan(l)) = 0;

    % Apply correction
    h_cor = h - (z + l);

    % Save data in the same input file
    h5create(infile,'/h_tide', length(z));
    h5create(infile,'/h_load', length(l));
    h5write(infile, '/h_tide', z);
    h5write(infile, '/h_load', l);
    h5write(infile, ZVAR, h_cor);

    % Rename file
    [path, fname, ext] = fileparts(infile);
    outfile = fullfile(path, strcat(fname, '_TIDE', ext));
    movefile(infile, outfile);

    %[path, fname, ext] = fileparts(infile);
    %outfile = fullfile(path, strcat(fname, '.tide_matlab'));
    %dlmwrite(outfile, [lon lat time z' l'], ' ')
     
    fprintf('Output -> %s\n', outfile);

    fclose('all');

end

% Get the current pool and shut it down
pool = gcp('nocreate');
delete(pool);

toc;
