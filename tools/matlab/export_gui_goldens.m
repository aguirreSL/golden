function export_gui_goldens(varargin)
% EXPORT_GUI_GOLDENS  Headless golden fixtures for the sqat-gui core (slice G1).
%   Runs the frozen fork helpers SQAT_GUI_metrics and SQAT_GUI_load (fork commit
%   b312b58, read only) and writes JSON + small WAVs under crates/sqat-gui/tests/fixtures.
%   The fork applies the channel rule in SQAT_GUI.m (nested channel_list, not callable
%   headless): its two lines are copied verbatim in il_channel_list below.
%   Usage: matlab -batch "addpath('tools/matlab'); export_gui_goldens()"
p = inputParser;
addParameter(p, 'fork_root', '/Users/sergioaguirre/Documents/git/SQAT');
addParameter(p, 'out_dir', fullfile(fileparts(mfilename('fullpath')), '..', '..', ...
    'crates', 'sqat-gui', 'tests', 'fixtures'));
addParameter(p, 'matlab_license', 'Trial');
addParameter(p, 'baseline_root', '/Users/sergioaguirre/Documents/git/SQAT_baseline_4a99198');
addParameter(p, 'only', '');   % 'g7', 'g8' or 'g9': write only those fixtures (quick)
parse(p, varargin{:});
fork = p.Results.fork_root;
out = char(java.io.File(p.Results.out_dir).getCanonicalPath());
expected = 'b312b589a3fc1b5869b8cc1ff25079ef48e00e23';
[st, sha] = system(['git -C "' fork '" rev-parse HEAD']);
sha = strtrim(sha);
assert(st == 0 && strcmp(sha, expected), 'fork is not at %s (got %s)', expected, sha);
addpath(fullfile(fork, 'gui'), fullfile(fork, 'utilities'));
if ~isfolder(out), mkdir(out); end
if strcmp(p.Results.only, 'g7'), il_g7(out); return, end
if strcmp(p.Results.only, 'g8'), il_g8(out); return, end
if strcmp(p.Results.only, 'g9'), il_g9(out); return, end

% deterministic WAVs, 16 bit PCM (audioread returns int / 32768)
n = (0:31)';
audiowrite(fullfile(out, 'mono.wav'), 0.5 * sin(2 * pi * 3 * n / 32), 8000, 'BitsPerSample', 16);
audiowrite(fullfile(out, 'stereo.wav'), [(n - 16) / 40, -0.25 * (n - 16) / 40], 48000, 'BitsPerSample', 16);

% catalogue
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
il_write(fullfile(out, 'catalog.json'), cat);

% loads: channel option -> channel list (fork rule) -> SQAT_GUI_load
specs = {'mono.wav', 94, '1'; 'stereo.wav', 100, '2'; 'stereo.wav', 94, 'All'; 'mono.wav', 74, '3'};
loads = cell(1, size(specs, 1));
for k = 1:size(specs, 1)
    f = fullfile(out, specs{k, 1});
    info = audioinfo(f);
    [cl, fell_back] = il_channel_list(info.NumChannels, specs{k, 3});
    [x, fs, nch] = SQAT_GUI_load(f, specs{k, 2}, cl);
    loads{k} = struct('file', specs{k, 1}, 'dBFS', specs{k, 2}, 'option', specs{k, 3}, ...
        'nch', nch, 'fs', fs, 'channels', {num2cell(cl)}, 'fell_back', fell_back, ...
        'samples', {num2cell(x, 1)});
end
il_write(fullfile(out, 'loads.json'), loads);

% direct loads the fork rejects (no fallback at this level)
errs = {'mono.wav', 3; 'mono.wav', 0};
E = cell(1, size(errs, 1));
for k = 1:numel(E)
    try
        SQAT_GUI_load(fullfile(out, errs{k, 1}), 94, errs{k, 2});
        id = '';
    catch err
        id = err.identifier;
    end
    E{k} = struct('file', errs{k, 1}, 'channel', errs{k, 2}, 'error_id', id);
end
il_write(fullfile(out, 'load_errors.json'), E);

% G2: metrics from the baseline (4a99198), helpers single_values/extract/restat from the fork.
% il_case = headless on_run for one file (share/take not reproduced).
bl = p.Results.baseline_root;
[~, bsha] = system(['git -C "' bl '" rev-parse HEAD']);
assert(startsWith(strtrim(bsha), '4a99198'), 'baseline is not at 4a99198');
addpath(bl); startup_SQAT([bl filesep]);
fs = 48000; t = (0:2 * fs - 1)'/fs; rng(1);
xl = 0.2 * (1 + 0.8 * sin(2 * pi * 4 * t)) .* sin(2 * pi * 1000 * t) + 0.01 * randn(size(t));
xr = 0.1 * (1 + 0.5 * sin(2 * pi * 70 * t)) .* sin(2 * pi * 500 * t) + 0.01 * randn(size(t));
audiowrite(fullfile(out, 'g2_mono.wav'), xl, fs, 'BitsPerSample', 16);
audiowrite(fullfile(out, 'g2_stereo.wav'), [xl xr], fs, 'BitsPerSample', 16);
tl = (0:2.5 * fs - 1)';   % 2.5 s: the annoyance models go time-varying above 2 s
audiowrite(fullfile(out, 'g2_long.wav'), 0.2 * (1 + 0.8 * sin(2 * pi * 4 * tl / fs)) .* sin(2 * pi * 1000 * tl / fs) + 0.01 * randn(size(tl)), fs, 'BitsPerSample', 16);
ids = {M.id}; none = struct();
o2 = struct('Loudness_ISO532_1', struct('field', 1, 'method', 1), 'Sharpness_DIN45692', struct('weight_type', 'aures', 'method', 2, 'time_skip', 0.7), ...
    'FluctuationStrength_Osses2016', struct('method', 0), 'Loudness_ECMA418_2', struct('fieldtype', 'diffuse', 'time_skip', 0.1), ...
    'Roughness_Daniel1997', struct('time_skip', 0.3), 'Tonality_Aures1985', struct('field', 1, 'time_skip', 0.5), ...
    'EPNL_FAR_Part36', struct('dt', 0.25, 'threshold', 8));
cases = {'g2_mono.wav', 94, '1', ids, none; 'g2_mono.wav', 100, '1', ids, o2; 'g2_stereo.wav', 94, 'All', ids, none; ...
    'g2_stereo.wav', 94, '3', ids([1 2 3]), struct('Sharpness_DIN45692', struct('method', 1)); 'g2_long.wav', 94, '1', ids([6 9 10]), struct('FluctuationStrength_Osses2016', struct('time_skip', 0.5))};
G = cell(1, size(cases, 1)); P = G; E5 = G; for k = 1:size(cases, 1)
    [rows, plots, E5{k}] = il_case(M, out, cases{k, :});
    G{k} = struct('file', cases{k, 1}, 'dBFS', cases{k, 2}, 'channel', cases{k, 3}, 'metrics', {cases{k, 4}}, ...
        'params', cases{k, 5}, 'rows', {rows});
    P{k} = struct('file', cases{k, 1}, 'entries', {plots});   % G3: the fork's extract, same runs, same order
end
il_write(fullfile(out, 'g2_rows.json'), G, false);
il_write(fullfile(out, 'g3_plots.json'), P, false);
rs = {'Loudness_ISO532_1', 'g2_mono.wav', 0.5, 0.9; 'Sharpness_DIN45692', 'g2_mono.wav', 0.5, 0.9; 'Roughness_Daniel1997', 'g2_mono.wav', 0, 0.6; ...
    'Tonality_Aures1985', 'g2_mono.wav', 0, 0.6; 'FluctuationStrength_Osses2016', 'g2_long.wav', 0, 0.5};
R = cell(1, size(rs, 1)); for k = 1:size(rs, 1)
    [x, fs] = SQAT_GUI_load(fullfile(out, rs{k, 2}), 94, 1);
    OUT = il_run(M, rs{k, 1}, x, fs, struct(rs{k, 1}, struct('method', 2 - (k == 5), 'time_skip', rs{k, 3})));
    T = SQAT_GUI_single_values(SQAT_GUI_restat(OUT, rs{k, 1}, rs{k, 4}), 1, 1);
    R{k} = struct('metric', rs{k, 1}, 'file', rs{k, 2}, 'skip_run', rs{k, 3}, 'skip_new', rs{k, 4}, 'rows', {il_rows(T)});
end
il_write(fullfile(out, 'g2_restat.json'), R);
% SQAT_GUI_export uses WriteMode 'replacefile', valid for .xlsx only (.csv errors in R2026a): plain writetable.
vals = [1e-7; NaN; 123456789.123456; Inf; -Inf; 0; -0; 1/3; 1e15; 1e16; 100000; 2.5; 1e-5; 5e-324; pi];
n = numel(vals); C = cell(1, 2);
for k = 1:2   % 1: comma and quote in File; 2: nothing to quote
    T = table(repmat({'g2_mono.wav'}, n, 1), repmat({'Loudness_ISO532_1'}, n, 1), repmat({'Binaural'}, n, 1), repmat({'Nmax'}, n, 1), vals, ...
        'VariableNames', {'File', 'Metric', 'Channel', 'Quantity', 'Value'});
    if k == 1, T.File(1:3) = {'a,b.wav'; 'q"x.wav'; 'plain.wav'}; end
    writetable(T, fullfile(tempdir, 'g2.csv'));
    C{k} = fileread(fullfile(tempdir, 'g2.csv'));
end
il_write(fullfile(out, 'g2_csv.json'), struct('quoted', C{1}, 'plain', C{2}));

% G4: maps. The colormap table, the fork's surface call read back from the pixels, the colour limits
% of draw_analysis (its lines copied in il_group), and the maps of extract on three G2 runs.
c = SQAT_GUI_colormap_artemis(256);
il_write(fullfile(out, 'g4_lut.json'), struct('rgb', c), false);
il_write(fullfile(out, 'g4_render.json'), struct('render', il_render_probe(c), 'auto_clim', {il_auto_clim()}), false);
mc = {'g2_mono.wav', 94, '1', ids, none; 'g2_stereo.wav', 94, 'All', ids([2 5 8]), none; ...
    'g2_mono.wav', 94, '1', ids([1 4 6]), struct('Loudness_ISO532_1', struct('method', 1), 'FluctuationStrength_Osses2016', struct('method', 0)); 'g2_long.wav', 94, '1', ids(6), none};
EE = cell(1, size(mc, 1)); MP = EE; for k = 1:size(mc, 1)
    [~, ~, EE{k}] = il_case(M, out, mc{k, :});
    MP{k} = struct('file', mc{k, 1}, 'dBFS', mc{k, 2}, 'channel', mc{k, 3}, 'metrics', {mc{k, 4}}, 'params', mc{k, 5}, 'entries', {il_map_entries(EE{k})});
end
grp = {'Loudness_ECMA418_2', 'specific_loudness_time', {1 '1'; 2 '1'; 2 '2'; 2 'Binaural'}; 'Tonality_ECMA418_2', 'specific_tonality_time', {1 '1'; 2 '1'; 2 '2'}};
G4 = cell(1, size(grp, 1)); for k = 1:size(grp, 1), G4{k} = il_group(EE, grp{k, :}); end
il_write(fullfile(out, 'g4_maps.json'), struct('cases', {MP}, 'groups', {G4}), false);

% G5: the statistics table of draw_stats (its lines copied in il_stats), one table per metric over the entries
% of four G2 runs plus a Loudness ISO method 2 run with time_skip 0.9 (the restat path), in run order.
c5 = [cases([1 2 3 5], :); {'g2_mono.wav', 94, '1', ids(1), struct('Loudness_ISO532_1', struct('method', 2, 'time_skip', 0.9))}];
[~, ~, e5] = il_case(M, out, c5{end, :}); E5 = [E5([1 2 3 5]), {e5}];
S5 = cell(1, size(c5, 1)); for k = 1:numel(S5)
    S5{k} = struct('file', c5{k, 1}, 'dBFS', c5{k, 2}, 'channel', c5{k, 3}, 'metrics', {c5{k, 4}}, 'params', c5{k, 5});
end
T5 = {}; for id = ids
    en = []; for k = 1:numel(E5), en = [en, E5{k}(strcmp({E5{k}.metric}, id{1}))]; end %#ok<AGROW>
    if ~isempty(en), T5{end+1} = il_stats(id{1}, en); end %#ok<AGROW>
end
il_write(fullfile(out, 'g5_stats.json'), struct('cases', {S5}, 'tables', {T5}), false);

% G6: the weighting helpers of the fork on a deterministic signal at two rates, and the waveform rules of SQAT_GUI.m
% (decimation and seek, closures not callable headless: their lines are copied verbatim in il_decimate and il_seek).
fq = [20 25 31.5 40 63 100 200 500 1000 2000 4000 8000 10000 16000 20000 22000];
W = {}; for fs = [44100 48000], for ty = {'A', 'C', 'Z'}
    t = (0:2047)' / fs; x = 0.3 * sin(2*pi*100*t) + 0.2 * sin(2*pi*1000*t) + 0.1 * sin(2*pi*8000*t); x(1) = x(1) + 0.5;
    [b, a] = SQAT_GUI_weight_filter(fs, ty{1});
    W{end+1} = struct('fs', fs, 'type', ty{1}, 'b', b(:)', 'a', a(:)', 'f', fq, 'curve', SQAT_GUI_weight_curve(fq, fs, ty{1}), ...
        'x', x', 'y', SQAT_GUI_weight(x, fs, ty{1})'); %#ok<AGROW>
end, end
D = {}; for n = [100 2000000 2000001 4500001], D{end+1} = il_decimate(n, 48000); end %#ok<AGROW>
S = {}; for tq = [-1 0 0.5/48000 1/48000 1.5/48000 0.01 999/48000 1000/48000 1], S{end+1} = il_seek(tq, 48000, 1000); end %#ok<AGROW>
il_write(fullfile(out, 'g6_player.json'), struct('weight', {W}, 'decimate', {D}, 'seek', {S}), false);

il_g7(out);   % G7: spectrogram of the player window
% G8: playback, which needs a sound output (the runners of GitHub Actions have none)
try, nout = numel(audiodevinfo().output); catch, nout = 0; end
if nout > 0
    il_g8(out);
else
    fprintf('export_gui_goldens: no audio output device, G8 (playback) skipped\n');
end
il_g9(out);   % G9: spectral filter of the filter boxes
v = ver('signal');
prov = struct('fork_commit', sha, 'fork_branch', 'feat/sqat-gui', ...
    'matlab_version', ['R' version('-release')], 'signal_toolbox', v.Version, ...
    'matlab_license', p.Results.matlab_license, 'generated', char(datetime('now', 'Format', 'yyyy-MM-dd')), ...
    'script', 'tools/matlab/export_gui_goldens.m', 'baseline_commit', strtrim(bsha));
il_write(fullfile(out, 'provenance.json'), prov);
end

function [cl, fell_back] = il_channel_list(nch, option)
% verbatim rule of SQAT_GUI.m channel_list, plus the condition that logs the fallback
fell_back = ~strcmp(option, 'All') && str2double(option) > nch;
if strcmp(option, 'All')
    cl = 1:nch;
else
    cl = str2double(option);
    if cl > nch
        cl = 1;
    end
end
end

function [rows, plots, E] = il_case(M, out, file, dBFS, option, ids, over)
path = fullfile(out, file);
[cl, ~] = il_channel_list(audioinfo(path).NumChannels, option);
joint = numel(cl) == 2;
stereo = ismember(ids, {M([M.stereo]).id});
E = struct('metric', {}, 'channel', {}, 'values', {}, 'analyses', {});
for c = cl
    for id = ids(~(stereo & joint))
        [x, fs] = SQAT_GUI_load(path, dBFS, c);
        OUT = il_run(M, id{1}, x, fs, over);
        E(end+1) = struct('metric', id{1}, 'channel', num2str(c), 'values', SQAT_GUI_single_values(OUT, 1, 1), ...
            'analyses', SQAT_GUI_extract(OUT, id{1}, 1)); %#ok<AGROW>
    end
end
for id = ids(stereo & joint)
    [x, fs] = SQAT_GUI_load(path, dBFS, cl);
    OUT = il_run(M, id{1}, x, fs, over);
    for label = {'1', '2', 'Binaural'}
        c_out = label{1};
        if ~strcmp(c_out, 'Binaural'), c_out = str2double(c_out); end
        v = SQAT_GUI_single_values(OUT, c_out, 2);
        A = SQAT_GUI_extract(OUT, id{1}, c_out);
        if ~isempty(A) || ~isempty(v)   % the fork's rule
            E(end+1) = struct('metric', id{1}, 'channel', label{1}, 'values', v, 'analyses', A); %#ok<AGROW>
        end
    end
end
plots = arrayfun(@(e) struct('metric', e.metric, 'channel', e.channel, 'analyses', {il_plots(e.analyses)}), E, 'UniformOutput', false);
rows = {};
for id = ids
    for e = E(strcmp({E.metric}, id{1}))
        r = il_rows(e.values);
        for i = 1:numel(r), r{i}.file = file; r{i}.metric = e.metric; r{i}.channel = e.channel; end
        rows = [rows, r]; %#ok<AGROW>
    end
end
end

function t = il_stats(id, entries)
% the table of draw_stats, its lines verbatim; a missing cell is empty there (present 0), a value is a column per entry
q = {};
for k = 1:numel(entries)
    q = union(q, entries(k).values.Quantity, 'stable');
end
data = cell(numel(q), 1 + numel(entries));
data(:, 1) = q(:);
for k = 1:numel(entries)
    for r = 1:numel(q)
        i_q = find(strcmp(entries(k).values.Quantity, q{r}), 1);
        if ~isempty(i_q)
            data{r, k + 1} = entries(k).values.Value(i_q);
        end
    end
end
d = data(:, 2:end); present = cellfun(@(c) ~isempty(c), d); v = zeros(size(d)); v(present) = [d{present}];
row = @(m) arrayfun(@(r) num2cell(m(r, :)), 1:size(m, 1), 'UniformOutput', false);
t = struct('metric', id, 'quantities', {q(:)'}, 'present', {row(present)}, 'value', {row(v)});
end

function r = il_map_entries(E)
% the maps of each entry; the matrix is kept for every step-th time row (at most about 3000 values), the
% full matrix as sum, min, max and count of NaN; order lists every analysis id of the entry
r = cell(1, numel(E));
for k = 1:numel(E)
    A = E(k).analyses; m = {};
    for a = A(strcmp({A.kind}, 'map'))
        [nt, nb] = size(a.z); rows = unique([1:max(1, ceil(numel(a.z) / 3000)):nt nt]);
        m{end+1} = struct('id', a.id, 'label', a.label, 'xlabel', a.xlabel, 'ylabel', a.ylabel, 'zlabel', a.zlabel, ...
            'bandscale', a.bandscale, 'nt', nt, 'nb', nb, 'x', a.x, 'y', a.y, 'rows', rows - 1, 'z_rows', a.z(rows, :), ...
            'sum', sum(a.z(:), 'omitnan'), 'min', min(a.z(:), [], 'omitnan'), 'max', max(a.z(:), [], 'omitnan'), 'nan', nnz(isnan(a.z))); %#ok<AGROW>
    end
    r{k} = struct('metric', E(k).metric, 'channel', E(k).channel, 'order', {{A.id}}, 'maps', {m});
end
end

function g = il_group(EE, metric, id, mem)
% panels of one map analysis and the colour limits of draw_analysis, verbatim
A = [];
for q = 1:size(mem, 1)
    E = EE{mem{q, 1}}; e = E(strcmp({E.metric}, metric) & strcmp({E.channel}, mem{q, 2}));
    A = [A e.analyses(strcmp({e.analyses.id}, id))]; %#ok<AGROW>
end
n = numel(A); n_cols = min(n, 2);
lo = min(arrayfun(@(a) min(a.z(:), [], 'omitnan'), A));
hi = max(arrayfun(@(a) max(a.z(:), [], 'omitnan'), A));
g = struct('metric', metric, 'id', id, 'members', {cellfun(@(c, ch) struct('case', c - 1, 'channel', ch), mem(:, 1), mem(:, 2), 'UniformOutput', false)'}, ...
    'rows', ceil(n / n_cols), 'cols', n_cols, 'lo', lo, 'hi', hi, 'common', isfinite(lo) && hi > lo);
end

function r = il_enc(Z)
% NaN and Inf as codes (JSON has neither): kind 0 finite, 1 NaN, 2 +Inf, 3 -Inf, the value 0 there
K = zeros(size(Z)); K(isnan(Z)) = 1; K(Z == Inf) = 2; K(Z == -Inf) = 3; Z(K > 0) = 0;
r = struct('nt', size(Z, 1), 'nb', size(Z, 2), 'z', Z, 'kind', K);
end

function r = il_render_probe(c)
% the fork's surface call on a tiny map, printed to a PNG; each cell colour read back as a table index
% (0: the background shows, -1: no table colour). Cell (i,j) is drawn from Z(i,j), the last row and column never.
nt = 7; nb = 5; lo = 0; hi = 10;
Z = reshape(linspace(-2, 12, nt * nb), nt, nb);
Z(1, 1) = NaN; Z(2, 2) = lo; Z(3, 3) = hi; Z(4, 1) = Inf; Z(5, 1) = -Inf; Z(6, 2) = 10 * 100 / 256; Z(6, 3) = 10 * 101 / 256; Z(6, 4) = 10 * 255.5 / 256;
f = figure('Visible', 'off', 'Position', [100 100 420 300], 'Color', [0.5 0.5 0.5], 'InvertHardcopy', 'off');   % grey: no table colour
ax = axes(f, 'Units', 'normalized', 'Position', [0 0 1 1]);
surface(ax, 0:nt-1, 0:nb-1, zeros(nb, nt), Z.', 'EdgeColor', 'none');
view(ax, 2); axis(ax, 'tight'); ax.Layer = 'top'; colormap(ax, c); clim(ax, [lo hi]); axis(ax, 'off');
png = [tempname '.png']; print(f, '-dpng', '-r100', png); im = imread(png); close(f);
[H, W, ~] = size(im); idx = zeros(nt - 1, nb - 1);
for i = 1:nt-1
    for j = 1:nb-1
        rgb = double(squeeze(im(round(H * (1 - (j - 0.5) / (nb - 1))), round(W * (i - 0.5) / (nt - 1)), :))') / 255;
        [d, k] = min(sum((c - rgb).^2, 2));
        if d < 1e-4, idx(i, j) = k; elseif all(abs(rgb - 0.5) < 0.01), idx(i, j) = 0; else, idx(i, j) = -1; end
    end
end
r = il_enc(Z); r.lo = lo; r.hi = hi; r.idx = idx;
end

function r = il_auto_clim()
% the CLim that MATLAB picks alone (the fork sets none when the common limits are not finite or lo == hi)
Z = {5 * ones(3, 4), NaN(3, 4), [1 NaN 3 4; 2 3 4 5; 1 2 3 4], [1 Inf 3 4; 2 3 4 5; 1 2 3 4], [-Inf 1 2 3; 1 2 3 4; 1 1 1 1], zeros(3, 4), [2 2 2 2; 2 2 2 2; 2 2 2 NaN]};
r = cell(1, numel(Z));
for k = 1:numel(Z)
    f = figure('Visible', 'off'); ax = axes(f); surface(ax, 0:3, 0:2, zeros(3, 4), Z{k}, 'EdgeColor', 'none');
    r{k} = il_enc(Z{k}); r{k}.clim = get(ax, 'CLim'); close(f);
end
end

function r = il_plots(A)
% G3: series and profiles only (maps are G4); the ylim lines are the fork's draw_analysis, verbatim
A = A(~strcmp({A.kind}, 'map'));
r = cell(1, numel(A));
for k = 1:numel(A)
    y_all = vertcat(A(k).y);
    y_range = [min(y_all) max(y_all)];
    y_ref = max(abs(y_range));
    ylim = [];
    if all(isfinite(y_range)) && y_ref > 0 && diff(y_range) <= 1e-3 * y_ref
        ylim = mean(y_range) + [-0.05 0.05] * y_ref;
    end
    r{k} = struct('id', A(k).id, 'label', A(k).label, 'kind', A(k).kind, 'x', A(k).x, 'y', A(k).y, ...
        'xlabel', A(k).xlabel, 'ylabel', A(k).ylabel, 'bandscale', A(k).bandscale, 'ylim', ylim);
end
end

function OUT = il_run(M, id, x, fs, over)
m = M(strcmp({M.id}, id));
q = struct();
for j = 1:numel(m.params), q.(m.params(j).name) = m.params(j).value; end
if isfield(over, id)
    for f = fieldnames(over.(id))', q.(f{1}) = over.(id).(f{1}); end
end
[~, OUT] = evalc('m.run(x, fs, q, false)');
end

function r = il_decimate(n, fs)
% draw_waveform_window, verbatim; the signal is the sample index, so that the sums are exact
x = (0:n-1)';
step = max(1, ceil(numel(x) / 2e6));   % display only: at most 2e6 points
t = (0:numel(x)-1)' / fs;
t = t(1:step:end); x = x(1:step:end);
r = struct('n', n, 'fs', fs, 'step', step, 'count', numel(t), 'sum_x', sum(x), 'head', {num2cell([t(1:3) x(1:3)], 2)'}, ...
    'tail', {num2cell([t(end-2:end) x(end-2:end)], 2)'});
end

function r = il_seek(t, wave_fs, n)
% seek and move_playhead of SQAT_GUI.m, verbatim (wave_y has n samples)
sample = min(max(round(t * wave_fs) + 1, 1), n);
t_now = (sample - 1) / wave_fs;
r = struct('t', t, 'fs', wave_fs, 'n', n, 'sample', sample, 't_now', t_now);
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

function il_g7(out)
% G7: SQAT_GUI_window, _read_window and _spectrogram of the fork on a 2 s chirp (16 bit WAV, so Rust reads the
% same samples), and the lines of draw_spectrogram and on_spec_option of SQAT_GUI.m (closures, copied verbatim in
% il_spec_draw). Matrices are kept for rows 1:sr:end and columns 1:sc:end (sr, sc = floor(n/32), the last always),
% plus sum, min, max and NaN count of the whole matrix. Plans (frame rules) also run on zero signals for long N.
fs = 48000; t = (0:2 * fs - 1)';
x0 = 0.4 * sin(2 * pi * (300 * t / fs + (12000 - 300) / 4 * (t / fs).^2)) + 0.1 * sin(2 * pi * 1000 * t / fs) .* (t > fs / 2) + 0.05 * sin(2 * pi * 50 * t / fs);
audiowrite(fullfile(out, 'g7_chirp.wav'), x0, fs, 'BitsPerSample', 16);
x = SQAT_GUI_load(fullfile(out, 'g7_chirp.wav'), 94, 1);
W = {}; for nm = {'hann', 'hamming', 'rect', 'rectangular', 'blackmanharris'}, for n = [2 16 64 1024]
    w = SQAT_GUI_window(nm{1}, n); W{end+1} = struct('name', nm{1}, 'n', n, 'sum', sum(w), 'w', w(1:max(1, floor(n / 32)):end)', 'step', max(1, floor(n / 32))); end, end %#ok<AGROW>
cv = {[0.1 0.5 1 0.5 0.1], [1 2], (1:16) / 16, sin(pi * (0:9) / 9)};
for k = 1:numel(cv), for n = [16 64 100 1024]
    w = SQAT_GUI_window('custom', n, cv{k}); W{end+1} = struct('name', 'custom', 'n', n, 'custom', cv{k}, 'sum', sum(w), 'w', w', 'step', 1); end, end %#ok<AGROW>
% imported windows: files written here, read by the fork
fl = {'col.txt', sprintf('0.1\n0.5\n1\n0.5\n0.1\n'); 'row.csv', '0.1,0.5,1,0.5,0.1'; 'tab.dat', sprintf('0.1\t0.5\t1\t0.5\t0.1\n'); 'sp.dat', '0.1 0.5 1 0.5 0.1'; ...
    'hdr.csv', sprintf('w\n0.1\n0.5\n1\n'); 'hdr2.csv', sprintf('# window\n0.1\n0.5\n1\n'); 'two.csv', sprintf('1,2\n3,4\n5,6\n'); 'one.txt', '0.5'; 'nan.csv', '1,NaN,2'; ...
    'inf.csv', '1,Inf,2'; 'bad.csv', '1,abc,2'; 'empty.txt', ''; 'semi.csv', '1;2;3'; 'sci.txt', sprintf('1e-3\n2E+0\n-0.5\n'); 'crlf.txt', sprintf('1\r\n2\r\n3\r\n'); ...
    'blank.txt', sprintf('1\n2\n3\n\n\n'); 'trail.csv', '1,2,3,'; 'sp2.txt', sprintf('1 2\n3 4'); 'xyz.xyz', '1 2 3'; 'lead.txt', sprintf('\n\n1\n2\n3\n'); 'mid.txt', sprintf('1\nabc\n3\n'); ...
    'cplx.txt', '1+2i,3'; 'missing.txt', ''};
wd = fullfile(out, 'g7_windows'); if ~isfolder(wd), mkdir(wd); end
% .mat windows are not ported (Sergio, 2026-09-25): the Rust GUI reads .txt, .csv and .dat only
R = cell(1, size(fl, 1)); for k = 1:size(fl, 1)
    f = fullfile(wd, fl{k, 1}); if ~strcmp(fl{k, 1}, 'missing.txt'), fid = fopen(f, 'w'); fwrite(fid, fl{k, 2}); fclose(fid); end
    try, v = SQAT_GUI_read_window(f); id = ''; catch err, v = []; id = err.identifier; end
    R{k} = struct('file', fl{k, 1}, 'ok', isempty(id), 'error_id', id, 'w', v');
end
% spectrograms: file, window, degree, overlap, weighting, label, signal length
cs = {'hann', 10, 50, 'Z', 'Hann', 0; 'hamming', 8, 75, 'Z', 'Hamming', 0; 'rect', 12, 0, 'Z', 'Rectangular', 0; 'blackmanharris', 6, 95, 'Z', 'Blackman-Harris', 0; ...
    'hann', 16, 95, 'Z', 'Hann', 0; 'hann', 10, 50, 'A', 'Hann', 0; 'hamming', 13, 60, 'A', 'Hamming', 0; 'blackmanharris', 10, 50, 'C', 'Blackman-Harris', 0; ...
    'hann', 12, 33.3, 'Z', 'Hann', 1000; 'hann', 9, 40, 'A', 'Hann', 0; 'hann', 6, 20, 'C', 'Hann', 0; 'hann', 10, 12.5, 'Z', 'Hann', 0};   % 12.5: %.0f of a tie in the title
cw = {'col.txt', 9, 25, 'Z'; 'col.txt', 10, 50, 'A'; 'row.csv', 8, 0, 'Z'}; n0 = size(cs, 1); cs = [cs; cell(3, 6)];
S = cell(1, size(cs, 1)); for k = 1:size(cs, 1)
    xs = x; if cs{k, 6} > 0, xs = x(1:cs{k, 6}); end
    win = cs{k, 1}; label = cs{k, 5};
    if k > n0, win = SQAT_GUI_read_window(fullfile(wd, cw{k - n0, 1})); label = ['Custom: ' cw{k - n0, 1}]; cs(k, 2:4) = cw(k - n0, 2:4); end
    S{k} = il_spec_draw(xs, fs, win, cs{k, 2}, cs{k, 3}, cs{k, 4}, label);
    S{k}.window = cs{k, 1}; S{k}.custom_file = ''; S{k}.n_signal = numel(xs);
    if k > n0, S{k}.window = 'custom'; S{k}.custom_file = cw{k - n0, 1}; end
end
% frame rules on zero signals (info and sizes only; the content is the eps floor)
pl = [96000 6 95; 96000 16 95; 96000 10 0; 96000 10 50; 96000 10 95; 1000 12 50; 65536 16 0; 65535 16 0; 65537 16 95; 1.2e6 12 95; 1.2e6 11 95; 1.2e6 14 95; 1e6 16 90; ...
      30000 6 0; 100 6 50; 64 6 50; 50000 8 33.3; 50000 8 12.5; 300000 7 87.5; 2e6 9 95];
P = cell(1, size(pl, 1)); for k = 1:size(pl, 1)
    [tt, ff, L, info] = SQAT_GUI_spectrogram(zeros(pl(k, 1), 1), fs, 'hann', pl(k, 2), pl(k, 3));
    P{k} = struct('n', pl(k, 1), 'degree', pl(k, 2), 'overlap', pl(k, 3), 'n_fft', info.n_fft, 'hop', info.hop, 'info_overlap', info.overlap, 'limited', info.limited, ...
        'n_frames', numel(tt), 'n_bins', numel(ff), 't_first', tt(1), 't_last', tt(end), 'f_last', ff(end), 'floor_db', L(1, 1));
end
il_write(fullfile(out, 'g7_spectrogram.json'), struct('windows', {W}, 'read_window', {R}, 'spectrograms', {S}, 'plans', {P}, 'fs', fs), false);
end

function r = il_spec_draw(x, fs, win, degree, overlap, weighting, label)
% on_spec_option (clamps) and draw_spectrogram (up to clim, title and colour bar label) of SQAT_GUI.m, verbatim
degree = round(min(max(degree, 6), 16)); overlap = min(max(overlap, 0), 95);
[t_spec, f_spec, L, info] = SQAT_GUI_spectrogram(x, fs, win, degree, overlap);
keep = f_spec >= 20;
L0 = L; L = L(keep, :) + SQAT_GUI_weight_curve(f_spec(keep), fs, weighting);
lim = max(L, [], 'all') + [-80 0];
if strcmp(weighting, 'Z'), zl = 'Level (dB SPL)'; else, zl = sprintf('Level (dB(%s))', weighting); end
ttl = sprintf('Spectrogram (%s window, %d points, %.0f %% overlap)', label, info.n_fft, info.overlap);
r = struct('degree', degree, 'overlap_in', overlap, 'weighting', weighting, 'label', label, 'info', info, 'n_frames', numel(t_spec), 'n_bins', numel(f_spec), ...
    'n_keep', nnz(keep), 'f_first', f_spec(1), 'f_last', f_spec(end), 'f_keep_first', f_spec(find(keep, 1)), 'f_sum', sum(f_spec), 't_sum', sum(t_spec), ...
    'raw', il_mat(L0), 'drawn', il_mat(L), 'lim', lim, 'zlabel', zl, 'title', ttl);
end

function r = il_mat(L)
[nb, nf] = size(L); ri = unique([1:max(1, floor(nb / 32)):nb nb]); ci = unique([1:max(1, floor(nf / 32)):nf nf]);
r = struct('rows', ri - 1, 'cols', ci - 1, 'z', L(ri, ci), 'sum', sum(L, 'all'), 'min', min(L, [], 'all'), 'max', max(L, [], 'all'), 'nan', nnz(isnan(L)));
end

function il_g8(out)
% G8: the real fork (Visible off, sqat_gui_mute: it plays silence) driven through its own callbacks, for the anti-clip
% and the log of a play; the buffer and position rules are closures, copied verbatim in il_playbuf.
fs = 48000; t = (0:9599)' / fs; f = fullfile(out, 'g8_clip.wav');
audiowrite(f, 0.95 * sin(2 * pi * 2500 * t), fs, 'BitsPerSample', 16);   % A lifts 2.5 kHz by 1.3 dB: over full scale
setappdata(groot, 'sqat_gui_mute', true); cl = onCleanup(@() rmappdata(groot, 'sqat_gui_mute'));
fig = SQAT_GUI({f}, 'Visible', 'off'); b = findall(fig, 'Tag', 'open_waveform'); b.ButtonPushedFcn(b, []);
w = findall(groot, 'Tag', 'SQAT_GUI_waveform'); con = findall(fig, 'Tag', 'console'); nl = numel(con.Value);
pl = getappdata(w, 'sqat_play'); pa = getappdata(w, 'sqat_audio'); tag = @(x) findall(w, 'Tag', x);
act = {@() set_w('A'), @() push('play'), @() seek(0.05), @() push('play'), @() push('stop'), @() set_w('Z'), @() push('play'), @() push('stop')};
nm = {'weighting A', 'play', 'seek 0.05 s', 'pause', 'stop', 'weighting Z', 'play', 'stop'}; S = cell(1, numel(act));
    function set_w(v), d = tag('wave_weighting'); d.Value = v; d.ValueChangedFcn(d, []); end
    function push(x), b = tag(x); b.ButtonPushedFcn(b, []); end
    function seek(ts), a = tag('waveform_axes'); a.ButtonDownFcn(a, struct('IntersectionPoint', [ts 0 0])); end
for k = 1:numel(act)
    act{k}(); pause(0.3); i = pl(); L = regexprep(con.Value(nl+1:end), '^\[[0-9:]+\] ', ''); nl = numel(con.Value);
    S{k} = struct('action', nm{k}, 'playing', i.playing, 'box_loop', i.box_loop, 'sample', i.sample, 'log', {L(:)'});
    if k == 1, y = pa(); peak = max(abs(y)); end
end
% (n, sample, box [r1 r2] in samples, loop): the play buffer and where each buffer sample is in the file
y = single((1:10)' / 16); C = {10, 3, [], true; 10, 0, [], false; 10, 5, [4 7], true; 10, 9, [4 7], true; 10, 4, [4 7], false; 10, 1, [10 10], true};
B = cell(1, size(C, 1)); for k = 1:numel(B), B{k} = il_playbuf(y(1:C{k, 1}), 8000, C{k, 2}, C{k, 3}, C{k, 4}); end
il_write(fullfile(out, 'g8_play.json'), struct('fs', fs, 'peak_A', peak, 'steps', {S}, 'bufs', {B}), false);
end

function r = il_playbuf(y, fs, sample, box, loop)
% start_playback and file_position of SQAT_GUI.m, verbatim (the box already in samples, as play_region gives it)
n = numel(y); r1 = 1; r2 = n; if ~isempty(box), r1 = box(1); r2 = box(2); end
arg = sample; if sample == 0, sample = r1; end
sample = min(max(round(sample), 1), n); box_loop = ~isempty(box) && sample >= r1 && sample <= r2;
if box_loop, last = r2; rep = y(r1:r2); loop_from = r1; else, last = n; rep = y; loop_from = 1; end
first = y(sample:last);
if loop, buf = [first; repmat(rep, max(1, ceil(120 * fs / numel(rep))), 1)]; else, buf = first; rep = zeros(0, 1, 'single'); end
m = struct('sample', sample, 'n_first', numel(first), 'loop_from', loop_from, 'n_rep', numel(rep));
ii = unique(min([1 2 m.n_first m.n_first + [1 2 m.n_rep m.n_rep + 1 2 * m.n_rep + 3] numel(buf)], numel(buf)));
pos = zeros(size(ii)); for k = 1:numel(ii), pos(k) = il_file_position(m, ii(k)); end
r = struct('n', n, 'arg', arg, 'sample', sample, 'box', box, 'loop', loop, 'map', m, 'box_loop', box_loop, 'len', numel(buf), ...
    'head', double(buf(1:min(60, numel(buf))))', 'i', ii, 'pos', pos);
end

function pos = il_file_position(m, i)
i = max(i, 1);
if i <= m.n_first || m.n_rep == 0, pos = m.sample + min(i, m.n_first) - 1; else, pos = m.loop_from + mod(i - m.n_first - 1, m.n_rep); end
end

function il_g9(out)
% G9: SQAT_GUI_spectral_filter of the fork on the G7 chirp (2 s, 48 kHz, chirp plus tones; the sound the player filters is the
% file as audioread gives it). Both modes, several box sets and lengths. Kept: y(1:64:end) and the last sample (idx, 0 based),
% plus sum, sum of |y|, min and max of the whole output. The helper exposes no mask, so the mask is tested through the output.
fs = 48000; x = audioread(fullfile(out, 'g7_chirp.wav'));
B = {'one', 96000, [0.5 1.2 800 3000]; 'overlap', 96000, [0.3 1.0 500 2500; 0.8 1.6 2000 6000]; ...
     'edges', 96000, [0.2 1.0 0 100; 1.0 1.9 20000 24000]; 'whole', 96000, [0 2 0 24000]; 'nyquist', 96000, [0.2 1.5 24000 24000]; ...
     'outside', 96000, [5 6 1000 2000; 0.5 1.0 30000 40000]; 'short', 1000, [0 1 0 24000]; 'short2', 3000, [0.01 0.05 1000 6000]; ...
     'odd', 50001, [0.1 0.9 100 1500]};
C = cell(1, 2 * size(B, 1)); k = 0;
for b = 1:size(B, 1), for m = {'keep', 'remove'}
    k = k + 1; y = SQAT_GUI_spectral_filter(x(1:B{b, 2}), fs, B{b, 3}, m{1}); ii = unique([1:64:numel(y) numel(y)]);
    C{k} = struct('name', B{b, 1}, 'mode', m{1}, 'n', numel(y), 'boxes', B{b, 3}, 'idx', ii - 1, 'y', y(ii)', ...
        'sum', sum(y), 'sum_abs', sum(abs(y)), 'min', min(y), 'max', max(y));
end, end
xs = x(1:5000); bx = [0.01 0.05 500 4000];
il_write(fullfile(out, 'g9_filter.json'), struct('fs', fs, 'cases', {C}, 'step', 64, 'default_is_remove', isequal(SQAT_GUI_spectral_filter(xs, fs, bx), ...
    SQAT_GUI_spectral_filter(xs, fs, bx, 'remove')), 'empty_is_input', isequal(SQAT_GUI_spectral_filter(xs, fs, zeros(0, 4), 'keep'), xs)), false);
end
