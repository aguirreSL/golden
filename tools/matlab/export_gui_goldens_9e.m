function export_gui_goldens_9e(varargin)
% EXPORT_GUI_GOLDENS_9E  Golden fixtures for the sqat-gui slices of phase 9e (fork commit 850437f,
%   the head of PR #84 on ggrecow/SQAT after the review of 2026-10-05; first exported at 8c889f3). Runs the fork (read only) and writes, under
%   crates/sqat-gui/tests/fixtures:
%     g18_halves.wav                     1.5 s, a loud half and a quiet half (60 dB lower)
%     g18_enhanced.json                  SQAT_GUI_enhanced_stft in dB SPL, per case: arguments, t,
%                                        f, info (with ref), and per map its file or, for the large
%                                        maps, rows and columns 1:step:end (step 8 or 16), with sum,
%                                        min, max and NaN count of the whole map. The six cases of g11 on the
%                                        same WAVs, the whole map of g18_halves.wav and excerpts of
%                                        its quiet half cut as zoom_map does, with and without ref
%     g18_<case>_<k>.f64                 a whole map, little-endian double, MATLAB column order
%     g19_*.wav, g19_calibration.json    SQAT_GUI_calibration (three methods, one level or one per
%                                        channel, one calibrator recording or one per channel, and
%                                        its errors) and SQAT_GUI_load with one dBFS per channel
%     g20_catalog.json                   SQAT_GUI_metrics, 14 entries, Do_SLM first
%     g20_sound_level.json               the Sound level analysis through the catalogue (OUT,
%                                        SQAT_GUI_extract, SQAT_GUI_single_values) and the values of
%                                        the level line of the Waveform tab
%   The WAVs of g11 are read, not written again.
%   Run on one computational thread, so sums do not depend on the core count:
%   matlab -singleCompThread -batch "addpath('tools/matlab'); export_gui_goldens_9e()"
p = inputParser;
addParameter(p, 'fork_root', '/Users/sergioaguirre/Documents/git/SQAT');
addParameter(p, 'out_dir', fullfile(fileparts(mfilename('fullpath')), '..', '..', ...
    'crates', 'sqat-gui', 'tests', 'fixtures'));
parse(p, varargin{:});
fork = p.Results.fork_root;
out = char(java.io.File(p.Results.out_dir).getCanonicalPath());
expected = '850437fc73de2ae2c07558fe8e5f0e6ef81e6c56';   % head of PR #84, 2026-10-05
[st, sha] = system(['git -C "' fork '" rev-parse HEAD']);
sha = strtrim(sha);
assert(st == 0 && strcmp(sha, expected), 'fork is not at %s (got %s)', expected, sha);
[~, dirty] = system(['git -C "' fork '" status --porcelain -- gui utilities sound_level_meter psychoacoustic_metrics']);
assert(isempty(strtrim(dirty)), 'fork has local changes in gui/, utilities/, sound_level_meter/ or psychoacoustic_metrics/');
addpath(fork);
startup_SQAT([fork filesep]);
assert(maxNumCompThreads == 1, 'run with -singleCompThread');
prov = struct('fork_commit', sha, 'fork_branch', 'feat/sqat-gui', 'pr', 'ggrecow/SQAT#84', ...
    'matlab', version, 'threads', maxNumCompThreads, 'script', 'tools/matlab/export_gui_goldens_9e.m');

il_g18(out, prov);
il_g19(out, prov);
il_g20(out, prov);
fprintf('written to %s\n', out);
end

%% -------------------------------------------------------------------------
function il_g18(out, prov)
% the enhanced spectrogram in dB SPL (dca4549) with the references of the whole map (11e4e40)
fs = 48000;
t = (0:round(1.5 * fs) - 1)' / fs;
rng(7);
x = 0.5 * sin(2 * pi * 1000 * t) + 0.002 * randn(size(t));
q = t >= 0.75;
x(q) = x(q) * 1e-3;                                    % the quiet half, 60 dB lower
audiowrite(fullfile(out, 'g18_halves.wav'), x, fs, 'BitsPerSample', 16);

% name, wav, smoothing, n_frames, f_min, bins_per_octave, preview, step (0: whole map) (g11's six)
cases = {
    'default',  'g11_enh_48k.wav',    {'readable', 'sharp'}, [],  [], [], [],    8
    'coarse',   'g11_enh_48k.wav',    {'readable', 'sharp'}, 100, 50, 24, [],    0
    'preview',  'g11_enh_48k.wav',    {'readable', 'sharp'}, 100, 50, 24, true,  0
    'k44',      'g11_enh_44k.wav',    'readable',            150, [], 48, [],    0
    'sharp1',   'g11_enh_44k.wav',    'sharp',               60,  30, 36, false, 0
    'silent',   'g11_enh_silent.wav', {'readable', 'sharp'}, 50,  50, 24, [],    0
    'halves',   'g18_halves.wav',     {'readable', 'sharp'}, [],  [], [], [],    16
};
C = cell(1, size(cases, 1) + 3);
for k = 1:size(cases, 1)
    [name, wav, sm, nf, fmin, bpo, pv, step] = cases{k, :};
    [x, fs] = SQAT_GUI_load(fullfile(out, wav), 94, 1);
    [tt, ff, L, info] = SQAT_GUI_enhanced_stft(x, fs, sm, nf, fmin, bpo, pv);
    C{k} = il_case(out, name, wav, fs, sm, nf, fmin, bpo, pv, [], tt, ff, L, info, step);
    if strcmp(name, 'halves')
        full_ref = info.ref;
        xh = x;
    end
end
% excerpts of the quiet half, cut as zoom_map of SQAT_GUI.m (lines 3031 to 3052) cuts them
lim = [1.0 1.3];
span = diff(lim);
pad = 0.3;
i1 = max(1, floor((lim(1) - pad) * fs) + 1);
i2 = min(numel(xh), ceil((lim(2) + pad) * fs));
nf = ceil((i2 - i1 + 1) / max(1, round(max(0.001, span / 2000) * fs)));
ex = {'zoom_readable', 'readable', full_ref(1); 'zoom_sharp', 'sharp', full_ref(2); 'zoom_noref', 'readable', []};
for k = 1:size(ex, 1)
    [tt, ff, L, info] = SQAT_GUI_enhanced_stft(xh(i1:i2), fs, ex{k, 2}, nf, [], [], [], ex{k, 3});
    c = il_case(out, ex{k, 1}, 'g18_halves.wav', fs, ex{k, 2}, nf, [], [], [], ex{k, 3}, tt, ff, L, info, 16);
    c.excerpt = struct('lim', lim, 'i1', i1, 'i2', i2);
    C{size(cases, 1) + k} = c;
end
il_write(fullfile(out, 'g18_enhanced.json'), struct('provenance', prov, 'cases', {C}), false);
end

function c = il_case(out, name, wav, fs, sm, nf, fmin, bpo, pv, ref, tt, ff, L, info, step)
if ~iscell(L), L = {L}; end
maps = cell(1, numel(L));
for j = 1:numel(L)
    Lj = L{j};
    m = struct('rows', size(Lj, 1), 'cols', size(Lj, 2), 'sum', sum(Lj(:)), 'min', min(Lj(:)), ...
        'max', max(Lj(:)), 'nan', nnz(isnan(Lj)));
    if step == 0
        f = sprintf('g18_%s_%d.f64', name, j);
        fid = fopen(fullfile(out, f), 'w', 'ieee-le'); fwrite(fid, Lj, 'double'); fclose(fid);
        m.file = f;
    else
        m.step = step;
        m.sub = Lj(1:step:end, 1:step:end);
    end
    maps{j} = m;
end
refs = cell(1, numel(info.ref));
for j = 1:numel(info.ref)
    refs{j} = struct('e_max', info.ref(j).e_max, 'r_max', info.ref(j).r_max);
end
ref_in = [];
if ~isempty(ref)
    ref_in = struct('e_max', ref.e_max, 'r_max', ref.r_max);
end
c = struct('name', name, 'wav', wav, 'fs', fs, 'smoothing', {sm}, 'n_frames', il_arg(nf), ...
    'f_min', il_arg(fmin), 'bins_per_octave', il_arg(bpo), 'preview', il_arg(pv), 'ref_in', ref_in, ...
    't', tt, 'f', ff', 'hop', info.hop, 'windows_ms', info.windows_ms, 'ref', {refs}, 'maps', {maps});
end

%% -------------------------------------------------------------------------
function il_g19(out, prov)
% calibration of a WAV file (bb8ecd0, per channel 850437f) and the load with one dBFS per channel
fs = 48000;
t = (0:round(0.25 * fs) - 1)' / fs;
tc = (0:round(0.5 * fs) - 1)' / fs;
t44 = (0:round(0.25 * 44100) - 1)' / 44100;
w = {
    'g19_file_stereo.wav',  [0.3 * sin(2 * pi * 1000 * t), 0.1 * sin(2 * pi * 500 * t)], fs
    'g19_file_mono.wav',    0.2 * sin(2 * pi * 1000 * t44),                              44100
    'g19_cal_stereo.wav',   [0.5 * sin(2 * pi * 1000 * tc), 0.25 * sin(2 * pi * 1000 * tc)], fs
    'g19_cal_mono.wav',     0.7 * sin(2 * pi * 1000 * tc),                               fs
    'g19_cal_half.wav',     [0.5 * sin(2 * pi * 1000 * tc), zeros(size(tc))],           fs
    'g19_silent_stereo.wav', zeros(round(0.1 * fs), 2),                                  fs
    'g19_cal_mono2.wav',    0.35 * sin(2 * pi * 1000 * tc),                              fs
    'g19_file_three.wav',   [0.3 * sin(2 * pi * 1000 * t), 0.1 * sin(2 * pi * 500 * t), 0.05 * sin(2 * pi * 250 * t)], fs
};
for k = 1:size(w, 1)
    audiowrite(fullfile(out, w{k, 1}), w{k, 2}, w{k, 3}, 'BitsPerSample', 16);
end
% method, file, level (one, or one per channel), calibrator recording (one, or a cell of one per channel)
cases = {
    'dbfs',       'g19_file_stereo.wav',   94,    ''
    'dbfs',       'g19_file_mono.wav',     100.5, ''
    'calibrator', 'g19_file_stereo.wav',   94,    'g19_cal_stereo.wav'
    'calibrator', 'g19_file_stereo.wav',   114,   'g19_cal_mono.wav'
    'calibrator', 'g19_file_mono.wav',     94,    'g19_cal_stereo.wav'
    'calibrator', 'g19_file_mono.wav',     93.8,  'g19_cal_mono.wav'
    'relative',   'g19_file_stereo.wav',   70,    ''
    'relative',   'g19_file_mono.wav',     65.5,  ''
    'calibrator', 'g19_file_stereo.wav',   94,    'g19_silent_stereo.wav'
    'calibrator', 'g19_file_stereo.wav',   94,    'g19_cal_half.wav'
    'relative',   'g19_silent_stereo.wav', 70,    ''
    'bogus',      'g19_file_mono.wav',     94,    ''
    'dbfs',       'g19_file_stereo.wav',   [94 100.5],  ''
    'dbfs',       'g19_file_stereo.wav',   [94 100 90], ''
    'dbfs',       'g19_file_mono.wav',     [94 100],    ''
    'calibrator', 'g19_file_stereo.wav',   [94 114],    'g19_cal_stereo.wav'
    'calibrator', 'g19_file_stereo.wav',   94,          {'g19_cal_mono.wav', 'g19_cal_mono2.wav'}
    'calibrator', 'g19_file_stereo.wav',   [94 100],    {'g19_cal_mono.wav', 'g19_cal_mono2.wav'}
    'calibrator', 'g19_file_three.wav',    94,          'g19_cal_stereo.wav'
    'calibrator', 'g19_file_three.wav',    94,          {'g19_cal_mono.wav', 'g19_cal_mono2.wav'}
    'calibrator', 'g19_file_stereo.wav',   94,          {'g19_cal_mono.wav', 'g19_silent_stereo.wav'}
    'relative',   'g19_file_stereo.wav',   [70 65.5],   ''
    'relative',   'g19_file_three.wav',    [70 65 60],  ''
    'relative',   'g19_silent_stereo.wav', [70 65],     ''
};
C = cell(1, size(cases, 1));
for k = 1:size(cases, 1)
    [method, file, level, cal] = cases{k, :};
    calpath = '';
    if ~isempty(cal), calpath = fullfile(out, cal); end     % a cell stays a cell
    cals = cellstr(cal);
    if isempty(cal), cals = {}; end
    dBFS = []; label = ''; id = '';
    try
        [dBFS, label] = SQAT_GUI_calibration(method, fullfile(out, file), level, calpath);
    catch err
        id = err.identifier;
    end
    C{k} = struct('method', method, 'file', file, 'level', {num2cell(level)}, 'calibrator', {cals}, ...
        'dBFS', {num2cell(dBFS)}, 'label', label, 'error_id', id);
end
% loads with one dBFS per channel (SQAT_GUI_load, bb8ecd0)
loads = {'g19_file_stereo.wav', [90 100], [1 2]; 'g19_file_stereo.wav', [90 100], 2; ...
    'g19_file_stereo.wav', [90 100], 1; 'g19_file_stereo.wav', 97, [1 2]; 'g19_file_mono.wav', 88, 1};
L = cell(1, size(loads, 1));
for k = 1:size(loads, 1)
    [x, fs_k, nch] = SQAT_GUI_load(fullfile(out, loads{k, 1}), loads{k, 2}, loads{k, 3});
    L{k} = struct('file', loads{k, 1}, 'dBFS', {num2cell(loads{k, 2})}, 'channels', {num2cell(loads{k, 3})}, ...
        'fs', fs_k, 'nch', nch, 'n', size(x, 1), 'head', {num2cell(x(1:64, :), 1)}, ...
        'sumsq', {num2cell(sum(x.^2, 1))});
end
il_write(fullfile(out, 'g19_calibration.json'), struct('provenance', prov, 'calibrations', {C}, 'loads', {L}));
end

%% -------------------------------------------------------------------------
function il_g20(out, prov)
% the Sound level analysis (60fec2b, 7f381a4, 1221d72) and the catalogue of 14
M = SQAT_GUI_metrics;
cat = cell(1, numel(M));
for k = 1:numel(M)
    ps = cell(1, numel(M(k).params));
    for j = 1:numel(ps)
        q = M(k).params(j);
        opts = cell(1, size(q.options, 1));
        for o = 1:numel(opts)
            opts{o} = struct('label', q.options{o, 1}, 'value', q.options{o, 2});
        end
        ps{j} = struct('name', q.name, 'label', q.label, 'type', q.type, 'options', {opts}, 'value', q.value);
    end
    cat{k} = struct('matlab_id', M(k).id, 'label', M(k).label, 'stereo', M(k).stereo, 'params', {ps});
end
il_write(fullfile(out, 'g20_catalog.json'), struct('provenance', prov, 'catalog', {cat}));

assert(strcmp(M(1).id, 'Do_SLM'), 'Do_SLM is not the first entry');
% file, weight_freq, weight_time, tob_weight
runs = {'g2_mono.wav', 'A', 'f', 'A'; 'g2_mono.wav', 'Z', 's', 'Z'; 'g2_mono.wav', 'C', 'i', 'C'; ...
    'g2_mono.wav', 'A', 'f', 'Z'; 'g2_mono.wav', 'Z', 'f', 'C'; 'g19_file_mono.wav', 'A', 'f', 'A'; ...
    'g19_file_mono.wav', 'C', 's', 'Z'};
R = cell(1, size(runs, 1));
for k = 1:size(runs, 1)
    [x, fs] = SQAT_GUI_load(fullfile(out, runs{k, 1}), 94, 1);
    pr = struct('weight_freq', runs{k, 2}, 'weight_time', runs{k, 3}, 'tob_weight', runs{k, 4});
    OUT = M(1).run(x, fs, pr, false);
    A = SQAT_GUI_extract(OUT, 'Do_SLM', 1);
    T = SQAT_GUI_single_values(OUT, 1, 1);
    R{k} = struct('file', runs{k, 1}, 'params', pr, 'out', OUT, 'analyses', {A}, 'rows', {il_rows(T)});
end
% a session saved before the parameter tob_weight: the bands stay unweighted (Z)
[x, fs] = SQAT_GUI_load(fullfile(out, 'g2_mono.wav'), 94, 1);
OUT = M(1).run(x, fs, struct('weight_freq', 'A', 'weight_time', 'f'), false);
old = struct('file', 'g2_mono.wav', 'TOB_unit', OUT.TOB_unit, 'TOB_level', OUT.TOB_level);
% the level line of the Waveform tab (show_level_values of SQAT_GUI.m): Do_SLM on the whole
% signal with the weighting of the player, every sample, and the levels exceeded during p %
W = cell(1, 2);
wl = {'A', 'f'; 'Z', 's'};
pct = [1 5 10 50 90 95 99];
for k = 1:2
    Lw = Do_SLM(x, fs, wl{k, 1}, wl{k, 2}, 94);
    Lw = Lw(:);
    Leq = Get_Leq(Lw, fs);
    W{k} = struct('weight_freq', wl{k, 1}, 'weight_time', wl{k, 2}, 'n', numel(Lw), 'Leq', Leq, ...
        'LE', Leq + 10*log10(numel(Lw) / fs), 'Lmax', max(Lw), 'pct', pct, ...
        'exceeded', arrayfun(@(q) get_exceeded_value(Lw, q), pct));
end
il_write(fullfile(out, 'g20_sound_level.json'), struct('provenance', prov, 'runs', {R}, ...
    'before_tob_weight', old, 'waveform', {W}), false);
end

%% -------------------------------------------------------------------------
function v = il_arg(a)
% [] (the default) as JSON null
if isempty(a), v = NaN; else, v = a; end
end

function r = il_rows(T)
r = cell(1, height(T));
for i = 1:height(T), r{i} = struct('quantity', T.Quantity{i}, 'value', T.Value(i)); end
end

function il_write(path, s, pretty)
if nargin < 3, pretty = true; end
fid = fopen(path, 'w');
fwrite(fid, [jsonencode(s, 'PrettyPrint', pretty) newline]);
fclose(fid);
end
