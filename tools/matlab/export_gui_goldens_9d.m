function export_gui_goldens_9d(varargin)
% EXPORT_GUI_GOLDENS_9D  Golden fixtures for the sqat-gui slices of phase 9d (fork commit dbf721a).
%   Runs SQAT_GUI_enhanced_stft of the fork (read only) on deterministic signals and saves the
%   colour table the fork loads for its maps (cmap_inferno.txt of the toolbox). Writes, under
%   crates/sqat-gui/tests/fixtures:
%     g11_enh_48k.wav, g11_enh_44k.wav  16 bit inputs, read by both sides through SQAT_GUI_load
%     g11_enhanced.json                  per case: arguments, t, f, info, and per map its file
%                                        (or, for the default grid, rows 1:8:end and columns
%                                        1:8:end) with sum, min, max and NaN count of the whole map
%     g11_<case>_<k>.f64                 a whole map, little-endian double, MATLAB column order
%                                        (F frequencies per time column, M columns)
%     g12_inferno.json                   the 256 x 3 table as MATLAB loads it
%   Run on one computational thread, so sums do not depend on the core count:
%   matlab -singleCompThread -batch "addpath('tools/matlab'); export_gui_goldens_9d()"
p = inputParser;
addParameter(p, 'fork_root', '/Users/sergioaguirre/Documents/git/SQAT');
addParameter(p, 'out_dir', fullfile(fileparts(mfilename('fullpath')), '..', '..', ...
    'crates', 'sqat-gui', 'tests', 'fixtures'));
parse(p, varargin{:});
fork = p.Results.fork_root;
out = char(java.io.File(p.Results.out_dir).getCanonicalPath());
expected = 'dbf721aedc7130dcb291736c7ad157d379eeb9c3';   % d248cc2 plus the fixes of e30fc51..dbf721a
[st, sha] = system(['git -C "' fork '" rev-parse HEAD']);
sha = strtrim(sha);
assert(st == 0 && strcmp(sha, expected), 'fork is not at %s (got %s)', expected, sha);
[~, dirty] = system(['git -C "' fork '" status --porcelain -- gui utilities']);
assert(isempty(strtrim(dirty)), 'fork has local changes in gui/ or utilities/');
addpath(fullfile(fork, 'gui'), fullfile(fork, 'utilities'), fullfile(fork, 'utilities', 'ECMA418_2'));
assert(maxNumCompThreads == 1, 'run with -singleCompThread');

% inputs: a tone, a chirp, a click and a quieter tone that starts late
signals = {};
for fs = [48000 44100]
    t = (0:round(0.6 * fs) - 1)' / fs;
    x = 0.3 * sin(2 * pi * 1000 * t) + 0.2 * sin(2 * pi * (200 * t + 3000 * t.^2)) ...
        + 0.05 * sin(2 * pi * 4000 * t) .* (t > 0.35);
    x(round(0.3 * fs)) = x(round(0.3 * fs)) + 0.8;   % click
    name = sprintf('g11_enh_%dk.wav', round(fs / 1000));
    audiowrite(fullfile(out, name), x, fs, 'BitsPerSample', 16);
    signals(end+1, :) = {name, fs}; %#ok<AGROW>
end
% a silent excerpt (e30fc51: no energy gives the floor of the scale, not NaN)
audiowrite(fullfile(out, 'g11_enh_silent.wav'), zeros(round(0.3 * 48000), 1), 48000, 'BitsPerSample', 16);
signals(end+1, :) = {'g11_enh_silent.wav', 48000};

% cases: name, signal, smoothing, n_frames, f_min, bins_per_octave, preview, whole maps
cases = {
    'default',  1, {'readable', 'sharp'}, [],  [], [], [],   false   % the GUI's full-map call
    'coarse',   1, {'readable', 'sharp'}, 100, 50, 24, [],   true
    'preview',  1, {'readable', 'sharp'}, 100, 50, 24, true, true
    'k44',      2, 'readable',            150, [], 48, [],   true
    'sharp1',   2, 'sharp',               60,  30, 36, false, true
    'silent',   3, {'readable', 'sharp'}, 50,  50, 24, [],   true
};
C = cell(1, size(cases, 1));
for k = 1:size(cases, 1)
    [name, si, sm, nf, fmin, bpo, pv, whole] = cases{k, :};
    x = SQAT_GUI_load(fullfile(out, signals{si, 1}), 94, 1);
    fs = signals{si, 2};
    [tt, ff, L, info] = SQAT_GUI_enhanced_stft(x, fs, sm, nf, fmin, bpo, pv);
    if ~iscell(L), L = {L}; end
    maps = cell(1, numel(L));
    for j = 1:numel(L)
        Lj = L{j};
        m = struct('rows', size(Lj, 1), 'cols', size(Lj, 2), 'sum', sum(Lj(:)), 'min', min(Lj(:)), ...
            'max', max(Lj(:)), 'nan', nnz(isnan(Lj)));
        if whole
            f = sprintf('g11_%s_%d.f64', name, j);
            fid = fopen(fullfile(out, f), 'w', 'ieee-le'); fwrite(fid, Lj, 'double'); fclose(fid);
            m.file = f;
        else
            m.step = 8;
            m.sub = Lj(1:8:end, 1:8:end);
        end
        maps{j} = m;
    end
    C{k} = struct('name', name, 'wav', signals{si, 1}, 'fs', fs, 'smoothing', {sm}, ...
        'n_frames', il_arg(nf), 'f_min', il_arg(fmin), 'bins_per_octave', il_arg(bpo), 'preview', il_arg(pv), ...
        't', tt, 'f', ff', 'hop', info.hop, 'windows_ms', info.windows_ms, 'maps', {maps});
end
try
    SQAT_GUI_enhanced_stft(zeros(4800, 1), 48000, 'blurry');
    bad = '';
catch err
    bad = err.identifier;
end
try
    SQAT_GUI_enhanced_stft(zeros(4800, 1), 48000, 'readable', [], 24000);
    bad_fmin = '';
catch err
    bad_fmin = err.identifier;
end
prov = struct('fork_commit', sha, 'fork_branch', 'feat/sqat-gui', 'matlab', version, ...
    'threads', maxNumCompThreads, 'script', 'tools/matlab/export_gui_goldens_9d.m');
il_write(fullfile(out, 'g11_enhanced.json'), struct('provenance', prov, 'cases', {C}, 'bad_smoothing_id', bad, 'bad_f_min_id', bad_fmin));

% colour table of the maps and spectrograms (loaded by the fork, SQAT_GUI.m line 144)
cmap = load('cmap_inferno.txt');
il_write(fullfile(out, 'g12_inferno.json'), struct('provenance', prov, 'file', strrep(erase(which('cmap_inferno.txt'), [fork filesep]), filesep, '/'), 'rgb', cmap));
fprintf('written to %s\n', out);
end

function v = il_arg(a)
% [] (the default) as JSON null
if isempty(a), v = NaN; else, v = a; end
end

function il_write(path, s)
fid = fopen(path, 'w');
fwrite(fid, [jsonencode(s, 'PrettyPrint', true) newline]);
fclose(fid);
end
