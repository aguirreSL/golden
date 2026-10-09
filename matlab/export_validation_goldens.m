function export_validation_goldens(opts)
%EXPORT_VALIDATION_GOLDENS Golden of every SQAT validation script, call by call.
%
%   Runs the scripts of the baseline `validation/` folder unchanged (on a copy)
%   with the SQAT metric functions wrapped: each call records its inputs and
%   its complete outputs (export_call.m), so the Rust port can be checked
%   against MATLAB on every signal the SQAT validations use. No decimation.
%
%   Name-value arguments:
%     sqat_root    SQAT tree at the sha being recorded
%     sqat_sha     that sha, written to the manifest (required)
%     sounds_root  folder with validation_SQAT_v1_0 (Zenodo) and
%                  AIAA-2020-2582_Sound_Files (NASA); the SQAT tree gives
%                  reference_signals (required)
%     out_dir      output root (default: <repo>/data/<sqat_sha>/level3v)
%     filter       run only scripts whose path contains this text
%     internal     also record the calls a script makes to the local functions of a metric
%                  through Tonality_Aures1985('localfunctions'), as Tonality_Aures1985.<name>
%
%   Output: <out_dir>/<script path>/call_NNNN_<function>/ and <out_dir>/inputs/. Each
%   call.json also lists the warnings raised during the call and, for a call that ended in
%   error, the error (shadow/warning.m, export_warn_frame.m). <out_dir>/manifest.json holds the
%   provenance: SQAT sha, MATLAB release and products, BLAS, LAPACK, FFTW, machine, threads,
%   power mode, the MATLAB path before the export, and the result of every script.
%   Run with one computational thread: matlab -singleCompThread -batch "...".
arguments
    opts.sqat_root (1,1) string = string(getenv("SQAT_ROOT"))
    opts.sqat_sha (1,1) string = ""
    opts.sounds_root (1,1) string = ""
    opts.out_dir (1,1) string = ""
    opts.filter (1,1) string = ""
    opts.internal (1,1) logical = false
end
here = fileparts(mfilename('fullpath'));
repo = fileparts(here);
if opts.sqat_sha == "" || opts.sounds_root == ""
    error('export_validation_goldens:args', 'sqat_sha and sounds_root are required');
end
if opts.out_dir == "", opts.out_dir = string(fullfile(repo, 'data', opts.sqat_sha, 'level3v')); end
root = char(opts.sqat_root);
path0 = path;   % the MATLAB path before the export, for the manifest

% virtual SQAT root: links to the baseline, sound_files merged with the external data
vroot = fullfile(tempdir, 'sqat_vroot');
if isfolder(vroot), rmdir(vroot, 's'); end
mkdir(fullfile(vroot, 'sound_files'));
top = dir(root);
for i = 1:numel(top)
    n = top(i).name;
    if any(strcmp(n, {'.', '..', '.git', 'sound_files', 'validation'})), continue; end
    link_(fullfile(root, n), fullfile(vroot, n));
end
link_(fullfile(root, 'sound_files', 'reference_signals'), fullfile(vroot, 'sound_files', 'reference_signals'));
for n = {'validation_SQAT_v1_0', 'AIAA-2020-2582_Sound_Files'}
    link_(fullfile(char(opts.sounds_root), n{1}), fullfile(vroot, 'sound_files', n{1}));
end
copyfile(fullfile(root, 'validation'), fullfile(vroot, 'validation'));   % scripts write results next to themselves

% SQAT path, then the wrappers and shadows in front of it
dirs = {'psychoacoustic_metrics/Loudness_ISO532_1', 'psychoacoustic_metrics/Roughness_Daniel1997', ...
    'psychoacoustic_metrics/FluctuationStrength_Osses2016', 'psychoacoustic_metrics/Sharpness_DIN45692', ...
    'psychoacoustic_metrics/Tonality_Aures1985', 'psychoacoustic_metrics/Loudness_ECMA418_2', ...
    'psychoacoustic_metrics/Roughness_ECMA418_2', 'psychoacoustic_metrics/Tonality_ECMA418_2', ...
    'psychoacoustic_metrics/EPNL_FAR_Part36', 'psychoacoustic_metrics/EPNL_FAR_Part36/helper', ...
    'utilities', 'utilities/ECMA418_2', 'sound_level_meter'};
for i = 1:numel(dirs), addpath(fullfile(root, dirs{i})); end
wrap = { ...
    'psychoacoustic_metrics/Loudness_ISO532_1', {'Loudness_ISO532_1'}; ...
    'psychoacoustic_metrics/Roughness_Daniel1997', {'Roughness_Daniel1997'}; ...
    'psychoacoustic_metrics/FluctuationStrength_Osses2016', {'FluctuationStrength_Osses2016'}; ...
    'psychoacoustic_metrics/Sharpness_DIN45692', {'Sharpness_DIN45692_from_loudness'}; ...
    'psychoacoustic_metrics/Tonality_Aures1985', {'Tonality_Aures1985'}; ...
    'psychoacoustic_metrics/Loudness_ECMA418_2', {'Loudness_ECMA418_2'}; ...
    'psychoacoustic_metrics/Roughness_ECMA418_2', {'Roughness_ECMA418_2'}; ...
    'psychoacoustic_metrics/Tonality_ECMA418_2', {'Tonality_ECMA418_2'}; ...
    'psychoacoustic_metrics/EPNL_FAR_Part36', {'EPNL_FAR_Part36'}; ...
    'psychoacoustic_metrics/EPNL_FAR_Part36/helper', {'get_PNLT'}; ...
    'sound_level_meter', {'Gen_weighting_filters', 'Do_SLM', 'Get_Leq'}};
sbx = fullfile(tempdir, 'sqat_wrap');
if isfolder(sbx), rmdir(sbx, 's'); end
for i = 1:size(wrap, 1)
    d = fullfile(sbx, sprintf('w%02d', i));
    copyfile(fullfile(root, wrap{i, 1}), d);          % private/ and data files come along
    for f = wrap{i, 2}
        make_wrapper_(d, f{1});
        if opts.internal && strcmp(f{1}, 'Tonality_Aures1985')
            make_local_wrappers_(d, f{1}, fullfile(sbx, 'locals'));
        end
    end
    addpath(d);
end
if opts.internal, addpath(fullfile(sbx, 'locals')); end
shadow = fullfile(sbx, 'shadow');
mkdir(shadow);
write_text_(fullfile(shadow, 'input.m'), ...
    sprintf('function r = input(varargin)\n%% answers the "re-run or load stored results" prompts: re-run\nr = 1;\nend\n'));
write_text_(fullfile(shadow, 'basepath_SQAT.m'), ...
    sprintf('function bp = basepath_SQAT\nbp = [''%s'' filesep];\nend\n', vroot));
addpath(shadow);
addpath(here);   % export_call, export_warn_frame, export_warn_on
addpath(fullfile(here, 'shadow'));   % warning.m: records the warnings of each call

setenv('SQAT_CALLS_ROOT', char(opts.out_dir));
if ~isfolder(char(opts.out_dir)), mkdir(char(opts.out_dir)); end
M = manifest_(opts, path0);
M.scripts = {};
write_json_(fullfile(char(opts.out_dir), 'manifest.json'), M);
scripts = dir(fullfile(vroot, 'validation', '**', '*.m'));
for i = 1:numel(scripts)
    s = fullfile(scripts(i).folder, scripts(i).name);
    rel = erase(s, [fullfile(vroot, 'validation') filesep]);
    if contains(rel, [filesep 'private' filesep]) || contains(rel, [filesep 'figs' filesep]), continue; end
    txt = fileread(s);
    if startsWith(strtrim(regexprep(txt, '^(\s*%[^\n]*\n)*', '')), 'function'), continue; end  % helpers
    if opts.filter ~= "" && ~contains(rel, opts.filter), continue; end
    tag = erase(rel, '.m');
    if isfolder(fullfile(char(opts.out_dir), tag)), rmdir(fullfile(char(opts.out_dir), tag), 's'); end
    setenv('SQAT_CALLS_TAG', tag);
    fprintf('SCRIPT %s ... ', rel);
    t0 = tic;
    r = struct('script', string(rel), 'status', "ok", 'seconds', 0, 'message', "");
    try
        run_script_(s);
        fprintf('ok (%.0f s)\n', toc(t0));
    catch e
        fprintf('FAILED (%.0f s): %s\n', toc(t0), e.message);
        r.status = "failed";
        r.message = string(e.message);
    end
    r.seconds = toc(t0);
    M.scripts{end+1} = r;
    write_json_(fullfile(char(opts.out_dir), 'manifest.json'), M);
    close all force;
end
setenv('SQAT_CALLS_TAG', '');
end

function M = manifest_(opts, path0)
% provenance of the recording; the home folder is written as ~
home = char(java.lang.System.getProperty('user.home'));
M = struct();
M.sqat_sha = opts.sqat_sha;
M.date_utc = string(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
M.matlab_version = string(version);
M.matlab_release = string(version('-release'));
v = ver;
M.products = arrayfun(@(p) struct('name', string(p.Name), 'version', string(p.Version), ...
    'release', string(p.Release)), v(:)', 'UniformOutput', false);
M.blas = try_(@() version('-blas'));
M.lapack = try_(@() version('-lapack'));
M.fftw = try_(@() version('-fftw'));
M.computer = string(computer);
M.arch = string(computer('arch'));
M.os = try_(@() system_dependent('getos'));
M.cpu = sys_('sysctl -n machdep.cpu.brand_string');
M.power_mode = sys_('pmset -g | grep -i powermode');
M.comp_threads = maxNumCompThreads;
M.matlab_path = strrep(string(strsplit(path0, pathsep)), home, '~');
end

function link_(src, dst)
% a symbolic link on macOS and Linux; on Windows a junction for a folder (no admin right
% needed) and a copy for a file
if ~ispc
    system(sprintf('ln -s "%s" "%s"', src, dst));
elseif isfolder(src)
    system(sprintf('mklink /J "%s" "%s"', dst, src));
else
    copyfile(src, dst);
end
end

function t = try_(f)
try
    t = string(f());
catch
    t = "";
end
end

function t = sys_(cmd)
[st, out] = system(cmd);
t = "";
if st == 0, t = string(strtrim(out)); end
end

function write_json_(p, x)
fid = fopen(p, 'w');
fwrite(fid, uint8(jsonencode(x, 'PrettyPrint', true)));
fclose(fid);
end

function run_script_(s)
% base workspace: the scripts run `clear all`, which must not reach this function
old = cd(fileparts(s));
try
    evalin('base', sprintf('run(''%s'');', s));
catch e
    cd(old);
    rethrow(e);
end
cd(old);
end

function make_wrapper_(d, name)
src = fileread(fullfile(d, [name '.m']));
orig = regexprep(src, ['(function[^\n=]*=\s*)' name '(\s*\()'], ['$1' name '__orig$2'], 'once');
if strcmp(orig, src)
    error('export_validation_goldens:wrap', 'no function line for %s', name);
end
write_text_(fullfile(d, [name '__orig.m']), orig);
write_text_(fullfile(d, [name '.m']), sprintf([ ...
    'function varargout = %s(varargin)\n' ...
    '%% recording wrapper (matlab/export_validation_goldens.m)\n' ...
    'n = max(nargout, 1);\n' ...
    'varargout = cell(1, n);\n' ...
    'export_warn_frame(''push'');\n' ...
    'try\n' ...
    '    [varargout{1:n}] = %s__orig(varargin{:});\n' ...
    'catch e\n' ...
    '    export_call(''%s'', varargin, {}, export_warn_frame(''pop''), e);\n' ...
    '    rethrow(e);\n' ...
    'end\n' ...
    'export_call(''%s'', varargin, varargout, export_warn_frame(''pop''));\n' ...
    'end\n'], name, name, name, name));
end

function make_local_wrappers_(d, name, locals)
% the local functions of <name> recorded as <name>.<local>: a wrapper file per local function,
% and the wrapper of <name> hands out those wrappers for 'localfunctions'; each wrapper keeps the
% local function's own name, so the scripts that pick a handle by func2str still find it
src = fileread(fullfile(d, [name '__orig.m']));
t = regexp(src, '\nfunction[^\n(]*?\<(il_\w+)\s*\(', 'tokens');
if ~isfolder(locals), mkdir(locals); end
for i = 1:numel(t)
    nm = t{i}{1};
    write_text_(fullfile(locals, [nm '.m']), sprintf([ ...
        'function varargout = %s(varargin)\n' ...
        '%% recording wrapper of a local function of %s (matlab/export_validation_goldens.m)\n' ...
        'h = getappdata(0, ''sqat_local_%s'');\n' ...
        'n = max(nargout, 1);\n' ...
        'varargout = cell(1, n);\n' ...
        'export_warn_frame(''push'');\n' ...
        '[varargout{1:n}] = h(varargin{:});\n' ...
        'export_call(''%s.%s'', varargin, varargout, export_warn_frame(''pop''));\n' ...
        'end\n'], nm, name, nm, name, nm));
end
w = fileread(fullfile(d, [name '.m']));
w = regexprep(w, 'end\n$', '');
w = [w sprintf([ ...
    'if nargin == 1 && ischar(varargin{1}) && strcmp(varargin{1}, ''localfunctions'')\n' ...
    '    fh = varargout{1};\n' ...
    '    for i = 1:numel(fh)\n' ...
    '        nm = func2str(fh{i});\n' ...
    '        if exist(nm, ''file'') == 2\n' ...
    '            setappdata(0, [''sqat_local_'' nm], fh{i});\n' ...
    '            fh{i} = str2func(nm);\n' ...
    '        end\n' ...
    '    end\n' ...
    '    varargout{1} = fh;\n' ...
    'end\n' ...
    'end\n'])];
write_text_(fullfile(d, [name '.m']), w);
end

function write_text_(p, t)
fid = fopen(p, 'w');
fwrite(fid, uint8(t));
fclose(fid);
end
