function export_gui_goldens_9f(tree, sha, out)
% EXPORT_GUI_GOLDENS_9F  Golden data for slice G31: the fork branch feat/gui-export-data at commit
%   SHA, run from TREE, a git archive of that commit (read only), not from a checkout. Writes, under
%   crates/sqat-gui/tests/fixtures:
%     g31_level.json   the sound level of the Waveform tab with three time weightings (eeda442,
%                      1349479): per mono WAV and frequency weighting (Z, A, C), Do_SLM with f, s
%                      and i (n, Leq, LE, Lmax, levels exceeded) and the y axis of draw_level
%     g31_export.json  the export of results (bff4e63, 69e6d8c, 2409ef5): the 14 metrics of
%                      SQAT_GUI_metrics on g2_stereo.wav, default parameters, channels as the GUI
%                      runs them; per analysis the VariableNames and size of SQAT_GUI_analysis_table;
%                      per metric the workbook of SQAT_GUI_export_data with Include all ticked: sheet
%                      names, header row and size of each sheet as readcell reads them, the missing
%                      cells and the first two columns of Single values, the Info cells. The
%                      workbooks are deleted.
%   The local functions of SQAT_GUI.m that save_results uses (il_unit, il_entry_info and theirs) are
%   copied verbatim from TREE at run time; the stamp of the Info sheet is fixed.
%   matlab -batch "addpath('tools/matlab'); export_gui_goldens_9f('<tree>', '<sha>')"
if nargin < 3
    out = fullfile(fileparts(mfilename('fullpath')), '..', '..', 'crates', 'sqat-gui', 'tests', 'fixtures');
end
out = char(java.io.File(out).getCanonicalPath());
addpath(tree);
startup_SQAT([tree filesep]);
tmp = [tree '_g31'];
if ~isfolder(tmp), mkdir(tmp); end
src = fileread(fullfile(tree, 'gui', 'SQAT_GUI.m'));
for n = {'il_unit', 'il_level_unit', 'il_entry_info', 'il_param_text', 'il_label_unit', 'il_if'}
    b = regexp(src, ['^function [^\n]*\<' n{1} '\(.*?(?=^function )'], 'match', 'once', 'lineanchors');
    assert(~isempty(b), 'local function %s not found in SQAT_GUI.m', n{1});
    fid = fopen(fullfile(tmp, [n{1} '.m']), 'w'); fwrite(fid, b); fclose(fid);
end
addpath(tmp);
assert(startsWith(which('SQAT_GUI_export_data'), tree), 'SQAT_GUI_export_data is not taken from %s', tree);
prov = struct('fork_commit', sha, 'fork_branch', 'feat/gui-export-data', 'source', 'git archive', ...
    'matlab', version, 'threads', maxNumCompThreads, 'script', 'tools/matlab/export_gui_goldens_9f.m');
il_level(out, prov);
il_export(out, prov, tmp);
rmpath(tmp);
rmdir(tmp, 's');
fprintf('written to %s\n', out);
end

%% -------------------------------------------------------------------------
function il_level(out, prov)
% draw_level and show_level_values of SQAT_GUI.m: Do_SLM on the whole channel (in Pa, 94 dBFS) with
% the frequency weighting of the player and each time weighting; the y axis from all three
pct = [1 5 10 50 90 95 99];
tws = {'f', 's', 'i'};
C = {};
for file = {'g2_mono.wav', 'g19_file_mono.wav', 'g18_halves.wav'}
    [x, fs] = SQAT_GUI_load(fullfile(out, file{1}), 94, 1);
    for fw = {'Z', 'A', 'C'}
        L3 = cell2mat(cellfun(@(tw) reshape(Do_SLM(x, fs, fw{1}, tw, 94), [], 1), tws, 'UniformOutput', false));
        lo = floor(min(arrayfun(@(k) get_exceeded_value(L3(:, k), 99), 1:3)) / 10) * 10;
        hi = ceil(max(L3(:)) / 10) * 10;
        T = cell(1, 3);
        for k = 1:3
            L = L3(:, k);
            Leq = Get_Leq(L, fs);
            T{k} = struct('weight_time', tws{k}, 'n', numel(L), 'Leq', Leq, 'LE', Leq + 10*log10(numel(L) / fs), ...
                'Lmax', max(L), 'exceeded', arrayfun(@(p) get_exceeded_value(L, p), pct));
        end
        C{end+1} = struct('file', file{1}, 'fs', fs, 'weight_freq', fw{1}, 'time', {T}, 'lo', lo, 'hi', hi, ...
            'ylim', [lo max(hi, lo + 10)], 'finite', all(isfinite([lo hi]))); %#ok<AGROW>
    end
end
il_write(fullfile(out, 'g31_level.json'), struct('provenance', prov, 'pct', pct, 'cases', {C}));
end

%% -------------------------------------------------------------------------
function il_export(out, prov, tmp)
% the run of SQAT_GUI.m (a stereo metric on both channels at once, the others per channel) and
% save_results with Include all: the ids are 'values', then the analyses in the order the entries hold them
M = SQAT_GUI_metrics;
wav = fullfile(out, 'g2_stereo.wav');
f = struct('id', 1, 'name', 'g2_stereo.wav', 'path', 'g2_stereo.wav', 'fs', 48000, 'nch', 2, 'dBFS', [94 94], ...
    'cal_set', false, 'cal', struct('method', 'dbfs', 'level', 94, 'file', '', 'label', '94 dBFS'));   % as loaded
stamp = {'Exported', '2026-10-08 12:00:00'; 'SQAT version', 'fixed'; 'MATLAB', 'fixed'};
R = cell(1, numel(M));
for k = 1:numel(M)
    e = M(k);
    e.p = struct();
    for q = e.params, e.p.(q.name) = q.value; end
    r = struct('matlab_id', e.id, 'stereo', e.stereo, 'error', '');
    try
        en = struct('channel', {}, 'analyses', {}, 'values', {});
        if e.stereo
            [x, fs] = SQAT_GUI_load(wav, 94, [1 2]);
            OUT = il_run(e, x, fs);
            for c = {'1', '2', 'Binaural'}
                cc = c{1};
                if ~strcmp(cc, 'Binaural'), cc = str2double(cc); end
                s = struct('channel', c{1}, 'analyses', {SQAT_GUI_extract(OUT, e.id, cc)}, ...
                    'values', {SQAT_GUI_single_values(OUT, cc, 2)});
                if ~isempty(s.analyses) || ~isempty(s.values), en(end+1) = s; end %#ok<AGROW>
            end
        else
            for c = 1:2
                [x, fs] = SQAT_GUI_load(wav, 94, c);
                OUT = il_run(e, x, fs);
                en(end+1) = struct('channel', num2str(c), 'analyses', {SQAT_GUI_extract(OUT, e.id, 1)}, ...
                    'values', {SQAT_GUI_single_values(OUT, 1, 1)}); %#ok<AGROW>
            end
        end
        E = cell(1, numel(en));
        for j = 1:numel(en)
            A = en(j).analyses;
            T = cell(1, numel(A));
            for i = 1:numel(A)
                t = SQAT_GUI_analysis_table(A(i));
                T{i} = struct('id', A(i).id, 'label', A(i).label, 'kind', A(i).kind, ...
                    'names', {t.Properties.VariableNames}, 'size', size(t));
            end
            E{j} = struct('channel', en(j).channel, 'analyses', {T});
        end
        r.entries = E;
        all_a = [en.analyses];
        ids = [{'values'}, unique({all_a.id}, 'stable')];
        xf = fullfile(tmp, sprintf('g2_stereo_s1_%s.xlsx', e.id));
        info = cell2table([stamp; il_entry_info(f, e)], 'VariableNames', {'Item', 'Value'});
        files = SQAT_GUI_export_data(en, ids, xf, info, @(q) il_unit(e.id, q));
        W = struct('ids', {ids}, 'n_files', numel(files), 'sheets', {{}});
        for s = sheetnames(xf)'
            c = readcell(xf, 'Sheet', s);
            W.sheets{end+1} = struct('name', s, 'header', {il_cells(c(1, :))}, 'size', size(c));
            if s == "Single values"
                [ri, ci] = find(cellfun(@(v) isa(v, 'missing'), c));
                W.values_missing = num2cell([ri ci], 2)';
                W.values_rows = il_rows(c(:, 1:2));
            elseif s == "Info"
                W.info = il_rows(c);
            end
        end
        cellfun(@delete, files);
        r.workbook = W;
    catch err
        r.error = sprintf('%s: %s', err.identifier, err.message);
    end
    R{k} = r;
end
il_write(fullfile(out, 'g31_export.json'), struct('provenance', prov, 'file', 'g2_stereo.wav', 'dBFS', 94, ...
    'stamp', {il_rows(stamp)}, 'metrics', {R}), false);
end

%% -------------------------------------------------------------------------
function OUT = il_run(e, x, fs)
% run_metric of SQAT_GUI.m: the printout of the toolbox is captured, no figure
[~, OUT] = evalc('e.run(x, fs, e.p, false)');
end

function c = il_cells(c)
% a row of readcell for JSON: a missing cell as null
c(cellfun(@(v) isa(v, 'missing'), c)) = {NaN};
end

function r = il_rows(c)
r = arrayfun(@(i) il_cells(c(i, :)), 1:size(c, 1), 'UniformOutput', false);
end

function il_write(path, s, pretty)
if nargin < 3, pretty = true; end
fid = fopen(path, 'w');
fwrite(fid, [jsonencode(s, 'PrettyPrint', pretty) newline]);
fclose(fid);
end
