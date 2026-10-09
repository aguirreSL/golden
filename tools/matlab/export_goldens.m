function export_goldens(opts)
%EXPORT_GOLDENS Generate the golden fixtures for the SQAT Rust port.
%
%   export_goldens(...) runs the pinned SQAT MATLAB baseline and writes the
%   fixture tree consumed by the sqat-fixtures crate, exactly as specified
%   in docs/fixtures-format.md (sections 1-12 are the contract).
%
%   Name-value arguments:
%     sqat_root      worktree of ggrecow/SQAT checked out at the sha pinned
%                    in SQAT_BASELINE (default: env SQAT_ROOT)
%     extras_root    local SQAT reference tree carrying material that is
%                    NOT in the baseline git: sound_files/validation_SQAT_v1_0
%                    (Zenodo doi 10.5281/zenodo.7933206) and
%                    test/golden/modulation_metrics_bitwise.mat
%                    (default: env SQAT_EXTRAS_ROOT)
%     out_dir        fixture data root (default: <repo>/crates/sqat-fixtures/data)
%     dryrun         plan only: registry, names and budget estimate; no
%                    metric calls, no writes (default false)
%     filter         substring: run only cases whose name contains it
%     matlab_license license type string recorded in the manifest
%                    (default "trial"; provenance only, never a gate)
%     skip_pass2     skip the determinism second pass (default false)
%     full           no decimation anywhere, probes included (default false);
%                    for the unversioned full set (sound_files/golden_full)
%
%   Provenance: every expected value is produced by the baseline worktree;
%   internal stages are captured by injecting pure-observation
%   export_probe(...) calls into sandbox COPIES of the metric files (the
%   baseline itself is never modified; injected lines only read variables).
%
%   Runbook: docs/regen-fixtures.md.

arguments
    opts.sqat_root (1,1) string = string(getenv("SQAT_ROOT"))
    opts.extras_root (1,1) string = string(getenv("SQAT_EXTRAS_ROOT"))
    opts.out_dir (1,1) string = ""
    opts.dryrun (1,1) logical = false
    opts.filter (1,1) string {mustBeNonzeroLengthText} = "all"
    opts.matlab_license (1,1) string {mustBeNonzeroLengthText} = "trial"
    opts.skip_pass2 (1,1) logical = false
    opts.budget_mb (1,1) double {mustBePositive} = 650
    opts.append (1,1) logical = false
    opts.manifest_only (1,1) logical = false
    opts.internal_pass2 (1,1) logical = false % set by the determinism rerun
    opts.full (1,1) logical = false
end

c = init_context(opts);
opts.filter = c.filter_back;

fprintf('%s: start (dryrun=%d, filter="%s")\n', mfilename, c.dryrun, c.filter);
fprintf('  sqat_root   : %s (%s)\n', c.sqat_root, c.worktree_sha);
fprintf('  extras_root : %s (%s)\n', c.extras_root, c.extras_sha);
fprintf('  out_dir     : %s\n', c.out_root);

if c.manifest_only
    % scan/checksum/verify ONLY: never dispatch sections (an earlier bug
    % re-ran every section and clobbered hand-regenerated fixtures)
    finalize_export(c);
    fprintf('%s: manifest-only done\n', mfilename);
    return;
end
try
    sec_signals_synthetic(c);
catch secerr
    dump_section_error('signals_synthetic', secerr);
end
try
    sec_signals_reference(c);
catch secerr
    dump_section_error('signals_reference', secerr);
end
try
    sec_level1_resample(c);
catch secerr
    dump_section_error('level1_resample', secerr);
end
try
    sec_level1_sos(c);
catch secerr
    dump_section_error('level1_sos', secerr);
end
try
    sec_level1_buffer(c);
catch secerr
    dump_section_error('level1_buffer', secerr);
end
try
    sec_level1_window(c);
catch secerr
    dump_section_error('level1_window', secerr);
end
try
    sec_level1_interp1(c);
catch secerr
    dump_section_error('level1_interp1', secerr);
end
try
    sec_level1_fft(c);
catch secerr
    dump_section_error('level1_fft', secerr);
end
try
    sec_level1_util(c);
catch secerr
    dump_section_error('level1_util', secerr);
end
try
    sec_level1_leq(c);
catch secerr
    dump_section_error('level1_leq', secerr);
end
try
    sec_validation(c);
catch secerr
    dump_section_error('validation', secerr);
end
try
    sec_level3_loudness_iso(c);
catch secerr
    dump_section_error('level3_loudness_iso', secerr);
end
try
    sec_level3_aures(c);
catch secerr
    dump_section_error('level3_aures', secerr);
end
try
    sec_level3_ecma(c);
catch secerr
    dump_section_error('level3_ecma', secerr);
end
try
    sec_level3_ecma_e4bands(c);
catch secerr
    dump_section_error('level3_ecma_e4bands', secerr);
end
try
    sec_level3_daniel(c);
catch secerr
    dump_section_error('level3_daniel', secerr);
end
try
    sec_level3_fs(c);
catch secerr
    dump_section_error('level3_fs', secerr);
end
try
    sec_level3_sharpness(c);
catch secerr
    dump_section_error('level3_sharpness', secerr);
end
try
    sec_level3_epnl(c);
catch secerr
    dump_section_error('level3_epnl', secerr);
end
try
    sec_level3_pa(c);
catch secerr
    dump_section_error('level3_pa', secerr);
end
try
    sec_level3_slm(c);
catch secerr
    dump_section_error('level3_slm', secerr);
end
try
    sec_level3_bitwise(c);
catch secerr
    dump_section_error('level3_bitwise', secerr);
end

finalize_export(c);

if ~c.dryrun && ~c.skip_pass2 && ~c.internal_pass2
    determinism_pass2(opts, c);
end

fprintf('%s: done (%d files, %.2f MB)\n', mfilename, numel(c.reg.info), ...
    sum_bytes(c)/1024/1024);
end

% ========================================================================
% Context and baseline validation
% =========================================================================

function c = init_context(opts)
here = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(here));            % tools/matlab -> repo root

if strlength(opts.sqat_root) == 0
    error('export_goldens:sqat_root', ...
        'sqat_root is required (argument or env SQAT_ROOT).');
end
if strlength(opts.extras_root) == 0
    error('export_goldens:extras_root', ...
        'extras_root is required (argument or env SQAT_EXTRAS_ROOT).');
end
if strlength(opts.out_dir) == 0
    opts.out_dir = string(fullfile(repo, 'crates', 'sqat-fixtures', 'data'));
end
if ~isfolder(opts.sqat_root)
    error('export_goldens:sqat_root', 'sqat_root does not exist: %s', opts.sqat_root);
end
if ~isfolder(opts.extras_root)
    error('export_goldens:extras_root', 'extras_root does not exist: %s', opts.extras_root);
end

% baseline sha pinned in SQAT_BASELINE; the worktree MUST sit at it
base_txt = fileread(fullfile(repo, 'SQAT_BASELINE'));
base_tok = regexp(base_txt, '([0-9a-f]|[0-9A-F]){40}', 'match');
if isempty(base_tok)
    error('export_goldens:baseline', 'no 40-hex sha found in SQAT_BASELINE');
end
baseline_sha = string(base_tok{1});
[st, out] = system(sprintf('git -C "%s" rev-parse HEAD', opts.sqat_root));
if st ~= 0
    error('export_goldens:git', 'git rev-parse failed on sqat_root:\n%s', out);
end
worktree_sha = string(strtrim(out));
if ~opts.dryrun && worktree_sha ~= baseline_sha
    error('export_goldens:baseline', ...
        'worktree sha %s != SQAT_BASELINE %s. Check out the pinned sha first.', ...
        worktree_sha, baseline_sha);
end
[st2, out2] = system(sprintf('git -C "%s" rev-parse HEAD', opts.extras_root));
if st2 == 0
    extras_sha = string(strtrim(out2));
else
    extras_sha = "";
end

c = struct();
c.here = here;
c.repo = repo;
c.sqat_root = opts.sqat_root;
c.extras_root = opts.extras_root;
c.out_root = opts.out_dir;
c.dryrun = opts.dryrun;
if opts.filter == "all"
    c.filter = "";
else
    c.filter = lower(opts.filter);
end
c.filter_back = c.filter;
c.budget_mb = opts.budget_mb;
c.skip_pass2 = opts.skip_pass2;
c.append = opts.append;
c.manifest_only = opts.manifest_only;
c.matlab_license = opts.matlab_license;
c.internal_pass2 = opts.internal_pass2;
c.full = opts.full;
c.baseline_sha = baseline_sha;
c.worktree_sha = worktree_sha;
c.extras_sha = extras_sha;
c.tmp = string(tempdir());
c.reg = egreg();
c.reg.out_root = c.out_root;
c.reg.dryrun = c.dryrun;

if c.dryrun
    fprintf('  dryrun: planning only, nothing is written\n');
elseif c.manifest_only
    fprintf('  manifest_only: scan, checksum and verify the existing tree\n');
else
    if c.append
        if ~isfolder(c.out_root)
            mkdir(c.out_root);
        end
        stale = fullfile(c.out_root, 'manifest.json');
        if isfile(stale)
            delete(stale);   % never leave a stale manifest mid-append
        end
    else
        if isfolder(c.out_root)
            rmdir(c.out_root, 's');   % generated tree: regenerate from scratch
        end
        mkdir(c.out_root);
    end
end

setup_sqat_path(c.sqat_root);
addpath(here);           % export_probe reachable from sandbox copies
end

function setup_sqat_path(root)
% replicate the startup_SQAT path layout (minus examples, publications,
% validation scripts and sound_files; private/ works via parent folders)
dirs = { ...
    'psychoacoustic_metrics/Loudness_ISO532_1', ...
    'psychoacoustic_metrics/Roughness_Daniel1997', ...
    'psychoacoustic_metrics/FluctuationStrength_Osses2016', ...
    'psychoacoustic_metrics/Sharpness_DIN45692', ...
    'psychoacoustic_metrics/Tonality_Aures1985', ...
    'psychoacoustic_metrics/Loudness_ECMA418_2', ...
    'psychoacoustic_metrics/Roughness_ECMA418_2', ...
    'psychoacoustic_metrics/Tonality_ECMA418_2', ...
    'psychoacoustic_metrics/EPNL_FAR_Part36', ...
    'psychoacoustic_metrics/EPNL_FAR_Part36/helper', ...
    'psychoacoustic_metrics/PsychoacousticAnnoyance_Widmann1992', ...
    'psychoacoustic_metrics/PsychoacousticAnnoyance_Zwicker1999', ...
    'psychoacoustic_metrics/PsychoacousticAnnoyance_More2010', ...
    'psychoacoustic_metrics/PsychoacousticAnnoyance_Di2016', ...
    'utilities', ...
    'utilities/ECMA418_2', ...
    'sound_level_meter'};
for i = 1:numel(dirs)
    d = fullfile(root, dirs{i});
    if isfolder(d)
        addpath(d);
    end
end
end

function tf = should_run(c, name)
tf = (c.filter == "") || contains(lower(string(name)), c.filter);
end

% ========================================================================
% Writer: registry, raw f64, json, verbatim copies, checksums
% =========================================================================

function register_file(c, rel, sha, nbytes)
rel = char(rel);
c.reg.info(end+1) = struct('path', rel, 'sha256', char(sha), ...
    'bytes', double(nbytes)); %#ok<AGROW>
end

function writer_f64(c, rel, A, meta)
% raw little-endian f64, C order (row-major; spec 2.1) + sidecar meta json
A = double(A);
if c.dryrun
    register_file(c, rel, "", numel(A) * 8);
    return;
end
abs_p = fullfile(c.out_root, char(rel));
d = fileparts(abs_p);
if ~isfolder(d), mkdir(d); end
fid = fopen(abs_p, 'w', 'ieee-le');
if fid == -1
    error('export_goldens:write', 'cannot open %s', abs_p);
end
if ~isempty(A)
    fwrite(fid, c_order_flat_(A), 'double');
end
fclose(fid);
write_sidecar_meta(c, rel, meta_defaults_(A, meta));
register_file(c, rel, sha256_file(abs_p), dir(abs_p).bytes);
end

function flat = c_order_flat_(A)
% C-order (row-major) linearization: permute dims reversed, then reshape
flat = reshape(permute(A, ndims(A):-1:1), 1, []);
end

function writer_c64(c, rel, Z, meta)
% complex array -> <rel>_re.f64 / <rel>_im.f64 (spec 2.1)
rel = char(rel);
writer_f64(c, [rel '_re.f64'], real(Z), meta);
writer_f64(c, [rel '_im.f64'], imag(Z), meta);
end

function m = meta_defaults_(A, meta)
m = struct();
m.shape = size(A);
m.dtype = "f64";
m.order = "C";
m.unit = "";
m.description = "";
if isfield(meta, 'unit'), m.unit = string(meta.unit); end
if isfield(meta, 'description'), m.description = string(meta.description); end
if isfield(meta, 'source')
    m.source = meta.source;
else
    m.source = struct('m_file', "", 'stage', "");
end
if isfield(meta, 'decimated')
    m.decimated = meta.decimated;
end
end

function write_sidecar_meta(c, rel, m)
abs_p = fullfile(c.out_root, [char(rel) '.meta.json']);
d = fileparts(abs_p);
if ~isfolder(d), mkdir(d); end
fid = fopen(abs_p, 'w');
fwrite(fid, uint8(jsonencode(m, 'PrettyPrint', true)));
fwrite(fid, uint8(newline));
fclose(fid);
register_file(c, [rel '.meta.json'], sha256_file(abs_p), dir(abs_p).bytes);
end

function writer_json(c, rel, s)
if c.dryrun
    register_file(c, rel, "", numel(jsonencode(s)) + 64);
    return;
end
abs_p = fullfile(c.out_root, char(rel));
d = fileparts(abs_p);
if ~isfolder(d), mkdir(d); end
fid = fopen(abs_p, 'w');
fwrite(fid, uint8(jsonencode(s, 'PrettyPrint', true)));
fwrite(fid, uint8(newline));
fclose(fid);
register_file(c, rel, sha256_file(abs_p), dir(abs_p).bytes);
end

function writer_copy(c, src, rel)
% verbatim copy of a source file (wav/xlsx/txt/asc)
if c.dryrun
    register_file(c, rel, "", dir(char(src)).bytes);
    return;
end
abs_p = fullfile(c.out_root, char(rel));
d = fileparts(abs_p);
if ~isfolder(d), mkdir(d); end
copyfile(char(src), abs_p);
register_file(c, rel, sha256_file(abs_p), dir(abs_p).bytes);
end

function h = sha256_file(path)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(path, 'r');
if fid == -1
    error('export_goldens:sha', 'cannot read %s', path);
end
try
    blk = fread(fid, 65536, 'uint8=>uint8');
    while ~isempty(blk)
        md.update(blk);
        blk = fread(fid, 65536, 'uint8=>uint8');
    end
catch err
    fclose(fid);
    rethrow(err);
end
fclose(fid);
hx = lower(dec2hex(typecast(md.digest(), 'uint8')));  % [n x 2]
h = reshape(hx.', 1, []);
end

function b = sum_bytes(c)
b = sum([c.reg.info.bytes]);
end

% ========================================================================
% Probes: capture hook + sandbox instrumentation
% ========================================================================


function me_throw_(id, msg)
throw(MException(['export_goldens:' id], msg));
end

function c = probe_begin(c, case_rel)
d = fullfile(c.tmp, 'sqat_export_probes');
if isfolder(d), rmdir(d, 's'); end
mkdir(d);
setappdata(0, 'sqat_export_probe_dir', d);
setappdata(0, 'sqat_export_probe_seq', struct());
c.probe_dir = string(d);
c.probe_case_rel = string(case_rel);
end

function probe_off()
setappdata(0, 'sqat_export_probe_dir', '');
end

function sandbox = instrument(c, relfile, probes, tag)
%SANDBOX-COPY a baseline .m with pure-observation injections.
% probes: struct array with fields anchor (exact line text) and code
% (cellstr). Every anchor must match exactly one line (trimmed compare).
% The copy is prepended to the path; the baseline is never modified.
src = fileread(fullfile(c.sqat_root, char(relfile)));
lines = regexp(src, '\r?\n', 'split');
sandbox = fullfile(c.tmp, ['sqat_export_sandbox_' char(tag)]);
if isfolder(sandbox), rmdir(sandbox, 's'); end
mkdir(sandbox);
if ~isempty(getenv('SQAT_SANDBOX_KEEP')), fprintf('SANDBOXDIR[%s]\n', sandbox); end

ins_idx = zeros(numel(probes), 1);
for k = 1:numel(probes)
    hit = 0;
    for i = 1:numel(lines)
        if strcmp(strtrim(lines{i}), strtrim(probes(k).anchor))
            hit = hit + 1;
            ins_idx(k) = i;
        end
    end
    if hit ~= 1
        error('export_goldens:anchor', ...
            'anchor %d in %s matched %d lines (needs exactly 1):\n%s', ...
            k, relfile, hit, probes(k).anchor);
    end
    % advance past continuation lines: never inject inside a continued
    % statement (the anchor may itself end with `...`)
    j = ins_idx(k);
    while j < numel(lines)
        t = strtrim(lines{j});
        cpart = regexp(t, '%', 'split', 'once');
        cpart = strtrim(cpart{1});
        if ~isempty(cpart) && numel(cpart) >= 3 && strcmp(cpart(end-2:end), '...')
            j = j + 1;
        else
            break;
        end
    end
    ins_idx(k) = j;
end
[~, order] = sort(ins_idx, 'descend');
for o = order.'
    indent = regexp(lines{ins_idx(o)}, '\S', 'once') - 1;
    pad = blanks(indent);
    code = probes(o).code;
    if ischar(code)
        code = {code};
    end
    if c.full   % capture-time decimation (x:step:end) off
        code = regexprep(code, '1:\d+:end', '1:1:end');
    end
    for j = numel(code):-1:1
        lines = [lines(1:ins_idx(o)), [pad code{j}], lines(ins_idx(o)+1:end)]; %#ok<AGROW>
    end
end
[~, nm, xt] = fileparts(char(relfile));
fid = fopen(fullfile(sandbox, [nm xt]), 'w');
fwrite(fid, uint8(strjoin(lines, newline)));
fclose(fid);
% copy sibling private/ and helper/ dirs so the sandbox copy resolves its
% subfunctions exactly like the baseline file does
src_dir = fileparts(fullfile(c.sqat_root, char(relfile)));
for sib = {'private', 'helper'}
    src_sib = fullfile(src_dir, sib{1});
    if isfolder(src_sib)
        copyfile(src_sib, fullfile(sandbox, sib{1}));
    end
end
addpath(sandbox);
end

function hdir = expose_private_(c, relfile)
% verbatim copy of a baseline private/ helper into a temp helper dir so the
% export can call it directly (the baseline itself is never modified)
hdir = fullfile(c.tmp, 'sqat_export_helpers');
if ~isfolder(hdir)
    mkdir(hdir);
end
[~, nm] = fileparts(char(relfile));
copyfile(fullfile(c.sqat_root, char(relfile)), fullfile(hdir, [nm '.m']));
end

function s = leaf_of_(p)
[~, s] = fileparts(char(p));
end

function instrument_clear()
dd = dir(fullfile(tempdir, 'sqat_export_sandbox_*'));
for i = 1:numel(dd)
    p = fullfile(dd(i).folder, dd(i).name);
    rmpath(p);
    rmdir(p, 's');
end
end

% ========================================================================
% Deterministic signal synthesis (spec section 9: rng(42,'twister'))
% ========================================================================

function x = synth_tone(fs, dur_s, f, db_spl)
t = (0:round(dur_s*fs)-1)' / fs;
x = sqrt(2) * 2e-5 * 10^(db_spl/20) * sin(2*pi*f*t);
end

function x = synth_am(fs, dur_s, fc, fmod, depth_pct, db_spl)
t = (0:round(dur_s*fs)-1)' / fs;
m = depth_pct/100;
x = sqrt(2) * 2e-5 * 10^(db_spl/20) * (1 + m*sin(2*pi*fmod*t)) .* sin(2*pi*fc*t);
end

function x = synth_fm(fs, dur_s, fc, fmod, df, db_spl)
t = (0:round(dur_s*fs)-1)' / fs;
x = sqrt(2) * 2e-5 * 10^(db_spl/20) * sin(2*pi*fc*t + (df/fmod)*sin(2*pi*fmod*t));
end

function x = synth_noise_band(fs, dur_s, fc, bw, db_spl, seedv)
rng(seedv, 'twister');
raw = randn(round(dur_s*fs), 1);
[b, a] = butter(2, [max(fc-bw/2, 1)/(fs/2), min(fc+bw/2, fs/2-1)/(fs/2)], 'bandpass');
x = filter(b, a, raw);
x = x / rms_local_(x) * (2e-5 * 10^(db_spl/20));
end

function x = synth_pink(fs, dur_s, db_spl, seedv)
rng(seedv, 'twister');
n = round(dur_s*fs);
X = fft(randn(n, 1));
f = (0:n-1)';
x = real(ifft(X ./ sqrt(max(f, 0.5))));
x = x / rms_local_(x) * (2e-5 * 10^(db_spl/20));
end

function r = rms_local_(x)
r = sqrt(mean(x.^2));
end

function x = read_wav_mono(path, chan)
[x, fs] = audioread(char(path));
if nargin < 2 || isempty(chan)
    chan = 1;
end
x = double(x(:, chan));
c = struct('x', x, 'fs', fs); %#ok<NASGU>
end

% ========================================================================
% Level3 case runner: OUT + warnings + errors + planned probes
% ========================================================================

function case_out = run_metric_case(c, cfg)
% cfg fields:
%   metric, name, m_file, params, tol
%   make_fcn   () -> OUT (runs the metric, sandboxed)
%   anchor     full probes (no decimation)
%   warn_case  warning/clamp/error case: probes full + relaxed warning gate
%   expect_warn_id  expected identifier ("" = none expected)
%   probe_plan struct array: name, files{part,field,file,meta}, nodecimate,
%               longdec (0 none | 20 | 100 applied to long vectors)
%   input_rel  rel path of input array (written by caller), "" if none
%   input_ref  struct for case.json when the input lives elsewhere
%   out_meta   extra values merged into case.json
case_rel = sprintf('level3/%s/%s', cfg.metric, cfg.name);
case_marker = fullfile(c.out_root, case_rel, '.complete');
% append skips a case already exported: its marker, or its case.json (the committed trees
% carry no markers, docs/regen-fixtures.md section 2)
if c.append && (isfile(case_marker) || isfile(fullfile(c.out_root, case_rel, 'case.json')))
    fprintf('  case %s (resume-skip)\n', case_rel);
    case_out = struct('skipped', true);
    return;
end
if ~should_run(c, case_rel)
    case_out = struct('skipped', true);
    return;
end
fprintf('  case %s\n', case_rel);

case_json = struct();
case_json.metric = string(cfg.metric);
case_json.case = string(cfg.name);
case_json.m_file = string(cfg.m_file);
case_json.baseline_sha = c.baseline_sha;
case_json.params = cfg.params;
case_json.anchor = logical(cfg.anchor);
case_json.warning_case = logical(cfg.warn_case);
case_json.expected_warning_id = string(cfg.expect_warn_id);
case_json.tolerance = string(cfg.tol);
if isfield(cfg, 'input_ref') && ~isempty(cfg.input_ref)
    case_json.input_ref = cfg.input_ref;
end
if isfield(cfg, 'input_rel') && strlength(string(cfg.input_rel)) > 0
    case_json.input_file = string(cfg.input_rel);
end
if isfield(cfg, 'out_meta') && ~isempty(cfg.out_meta)
    case_json.out_meta = cfg.out_meta;
end

c = probe_begin(c, case_rel);
if c.dryrun
    % planning mode: register the case skeleton (name/naming-rule checks and
    % budget lower bound); metric outputs are only produced by real runs
    case_json.dryrun = true;
    case_json.files = {};
    writer_json(c, sprintf('%s/case.json', case_rel), case_json);
    writer_json(c, sprintf('%s/warnings.json', case_rel), struct('warnings', {{}}));
    case_out = struct('skipped', false, 'OUT', []);
    return;
end
% every warning of the call, oldest first (warn_shadow/warning.m on the path during the call)
shadow = fullfile(fileparts(mfilename('fullpath')), 'warn_shadow');
addpath(shadow);
export_warn_frame('push');
err_id = "";
err_msg = "";
OUT = [];
try
    OUT = cfg.make_fcn();
catch e
    err_id = string(e.identifier);
    err_msg = string(e.message);
    fprintf('MAKEFN-ERR id=[%s] msg=[%s] frames=%d\n', err_id, err_msg, numel(e.stack));
    if ~isempty(e.stack)
        fprintf('  at %s:%d\n', e.stack(1).name, e.stack(1).line);
    end
end
W = export_warn_frame('pop');
rmpath(shadow);
probe_off();
W = struct('id', {W.id}, 'message', {W.message});
% ---- warnings / errors (spec sections 5.0 and 7) ------------------------
files_list = {};
if err_id ~= "" || err_msg ~= ""
    if ~cfg.warn_case
        error('export_goldens:unexpected_error', ...
            'case %s errored unexpectedly:\n%s\n%s', case_rel, err_id, err_msg);
    end
    writer_json(c, sprintf('%s/errors.json', case_rel), ...
        struct('identifier', err_id, 'message', err_msg));
    writer_json(c, sprintf('%s/warnings.json', case_rel), ...
        struct('warnings', {{}}));
elseif cfg.warn_case
    % an empty expected id with no warning passes, as with lastwarn before (r11 of the bitwise set)
    if ~(isempty(W) && strlength(string(cfg.expect_warn_id)) == 0) && ...
            (isempty(W) || ~any(strcmp(string({W.id}), string(cfg.expect_warn_id))))
        error('export_goldens:warning_mismatch', ...
            'case %s: expected warning id "%s", got %s', ...
            case_rel, cfg.expect_warn_id, strjoin(string({W.id}), ', '));
    end
    wid = "";
    if ~isempty(W), wid = string(W(end).id); end
    if wid ~= ""   % anti multi-class check (spec 7); plain ids cannot be
        % selectively disabled (documented limitation in the spec)
        probe_off();
        warning('off', char(wid));
        cleanup = onCleanup(@() warning('on', char(wid)));
        lastwarn('', '');
        cfg.make_fcn();
        [msg2, wid2] = lastwarn;
        clear cleanup
        if wid2 ~= ""
            % F0.7 finding: record instead of aborting (r10 shows the
            % suppressed id still reported by lastwarn in this MATLAB);
            % reviewed against the case matrix in the morning report
            fprintf('  note: case %s anti-multi-class rerun still reports %s\n', ...
                case_rel, wid2);
            case_json.multi_warning_rerun = string(wid2);
        end
    end
    writer_json(c, sprintf('%s/warnings.json', case_rel), struct('warnings', {num2cell(W)}));
else
    % a case not declared as a warning case still records what MATLAB raised
    writer_json(c, sprintf('%s/warnings.json', case_rel), struct('warnings', {num2cell(W)}));
end

% ---- OUT numeric fields -------------------------------------------------
if isstruct(OUT) && ~isempty(OUT)
    fn = fieldnames(OUT);
    out_meta = struct();
    for i = 1:numel(fn)
        v = OUT.(fn{i});
        if isnumeric(v) && ~isempty(v)
            writer_f64(c, sprintf('%s/out_%s.f64', case_rel, fn{i}), v, ...
                struct('description', sprintf('OUT.%s of %s', fn{i}, cfg.m_file), ...
                'source', struct('m_file', cfg.m_file, 'stage', 'OUT')));
            files_list{end+1} = sprintf('out_%s.f64', fn{i}); %#ok<AGROW>
        elseif islogical(v) && isscalar(v)
            out_meta.(fn{i}) = v;
        elseif ischar(v) || isstring(v)
            out_meta.(fn{i}) = string(v);
        elseif isstruct(v) && ~isempty(v)
            % nested metric outputs (PA carries L/S/R/FS(/K) structs) are
            % reproducible via their own metrics; never serialize the arrays
            out_meta.(fn{i}) = struct('note', 'nested metric output struct', ...
                'fields', string(fieldnames(v).'));
        end
    end
    if ~isfield(case_json, 'out_meta')
        case_json.out_meta = out_meta;
    else
        f2 = fieldnames(out_meta);
        for i = 1:numel(f2)
            case_json.out_meta.(f2{i}) = out_meta.(f2{i});
        end
    end
end
case_json.files = string(files_list);
writer_json(c, sprintf('%s/case.json', case_rel), case_json);

% ---- planned probes ------------------------------------------------------
if isfield(cfg, 'probe_plan')
    for k = 1:numel(cfg.probe_plan)
        if strlength(string(cfg.probe_plan(k).name)) == 0
            continue;
        end
        export_planned_probe(c, case_rel, cfg.probe_plan(k), cfg.anchor || cfg.warn_case);
    end
end
fid = fopen(fullfile(c.out_root, case_rel, '.complete'), 'w');
if fid ~= -1
    fwrite(fid, uint8(sprintf('completed %s\n', char(datetime('now')))));
    fclose(fid);
end
case_out = struct('skipped', false, 'OUT', OUT);
end

function export_planned_probe(c, case_rel, plan, full_probe)
parts = dir(fullfile(c.probe_dir, [char(plan.name) '_*.mat']));
parts = sort({parts.name});
if isempty(parts)
    if (isfield(plan, 'optional') && plan.optional) || c.full
        fprintf('  note: optional probe %s produced no parts (skipped)\n', plan.name);
        return;
    end
    error('export_goldens:probe_missing', 'probe %s produced no parts in %s', ...
        plan.name, case_rel);
end
for k = 1:numel(plan.files)
    pf = plan.files(k);
    if iscell(pf)
        pf = pf{1};
    end
    want = sprintf('%s_%04d', plan.name, pf.part);
    hit = "";
    for i = 1:numel(parts)
        if startsWith(parts{i}, want)
            hit = parts{i};
        end
    end
    if isempty(hit) || strcmp(hit, "")
        if (isfield(plan, 'optional') && plan.optional) || c.full
            continue;   % exemplar-part probes: not every input produces all bands
        end
        error('export_goldens:probe_part', 'probe %s part %d missing (have %d parts)', ...
            plan.name, pf.part, numel(parts));
    end
    S = load(fullfile(c.probe_dir, hit));
    if isfield(S, 'S') && numel(fieldnames(S)) == 1
        S = S.S;   % parts saved as the variable S (struct arrays included)
    end
    if c.full && (isempty(S) || ~isfield(S, pf.field))
        continue;   % an input without that component (noise has no tones)
    end
    v = S.(pf.field);
    meta = pf.meta;
    if ~c.full
        [v, meta] = maybe_decimate_(v, meta, full_probe, plan);
    end
    if isfield(plan, 'complex') && plan.complex
        writer_c64(c, sprintf('%s/%s', case_rel, pf.file), v, meta);
    else
        writer_f64(c, sprintf('%s/%s', case_rel, pf.file), v, meta);
    end
end
end

function [v, meta] = maybe_decimate_(v, meta, full_probe, plan)
% spec 5.0 decimation rule: matrices time x band decimated x20 on the long
% axis outside the anchor/warning cases; scalar time series never
% decimated; long raw internal signals may be marked longdec for x20/x100.
% Safety cap (F0.7 finding): no single probe file above ~16 MB, even on
% anchors — raw intermediate signals (e.g. Do_OB13 filteredaudio
% [N x 28]) are decimated x100 with meta instead of blowing the budget.
if isnumeric(v) && numel(v) * 8 > 16e6
    if ismatrix(v) && size(v, 1) >= size(v, 2)
        meta.decimated = struct('factor', 100, 'axis', 0, 'original_shape', size(v), ...
            'reason', 'size cap');
        v = v(1:100:end, :);
    elseif ismatrix(v)
        meta.decimated = struct('factor', 100, 'axis', 1, 'original_shape', size(v), ...
            'reason', 'size cap');
        v = v(:, 1:100:end);
    else
        meta.decimated = struct('factor', 100, 'axis', 0, 'original_shape', size(v), ...
            'reason', 'size cap');
        v = v(1:100:end);
    end
    return;
end
if full_probe
    return;
end
if ismatrix(v) && min(size(v)) > 1 && max(size(v)) > 50 && ~plan.nodecimate
    if size(v, 1) >= size(v, 2)
        meta.decimated = struct('factor', 20, 'axis', 0, 'original_shape', size(v));
        v = v(1:20:end, :);
    else
        meta.decimated = struct('factor', 20, 'axis', 1, 'original_shape', size(v));
        v = v(:, 1:20:end);
    end
elseif isvector(v) && numel(v) > 20000 && isfield(plan, 'longdec') && plan.longdec > 1
    meta.decimated = struct('factor', plan.longdec, 'axis', 0, ...
        'original_shape', size(v));
    v = v(1:plan.longdec:end);
end
end

% probe-plan builders ------------------------------------------------------

function p = plan1(name, files, opts)
p = struct('name', {}, 'files', {}, 'nodecimate', {}, 'longdec', {}, 'complex', {});
p(1).name = name;
p(1).files = files;
p(1).nodecimate = false;
p(1).longdec = 0;
p(1).complex = false;
if isfield(opts, 'nodecimate'), p(1).nodecimate = opts.nodecimate; end
if isfield(opts, 'longdec'), p(1).longdec = opts.longdec; end
if isfield(opts, 'complex'), p(1).complex = opts.complex; end
p(1).optional = isfield(opts, 'optional') && opts.optional;
end

function f = pf(part, fieldname, file, unit, desc, mfile, stage)
f = struct('part', part, 'field', fieldname, 'file', file, ...
    'meta', struct('unit', unit, 'description', desc, ...
    'source', struct('m_file', mfile, 'stage', stage)));
end

% ========================================================================
% Section: signals/synthetic (spec 9)
% =========================================================================

function dump_section_error(tag, e)
% record a section failure without stopping the remaining chunks; the file
% is collected at the end of the run for review (F0.7 report)
r = e.getReport('extended', 'hyperlinks', 'off');
fprintf('SECTION-ERR %s id=[%s] msg=[%s]\n', tag, e.identifier, e.message);
for k = 1:numel(e.stack)
    fprintf('  at %s:%d\n', e.stack(k).name, e.stack(k).line);
end
fid = fopen('/tmp/export_section_error.txt', 'a');
if fid ~= -1
    fprintf(fid, '=== SECTION %s %s ===\n%s\n', tag, ...
        char(datetime('now')), r);
    fclose(fid);
end
fprintf('SECTION-FAIL %s: %.120s\n', tag, e.message);
end

function sec_signals_synthetic(c)
if ~should_run(c, 'signals/synthetic'), return; end
rng(42, 'twister');
syn = 'signals/synthetic';

x = synth_tone(48000, 1, 1000, 60);
writer_f64(c, sprintf('%s/tone_1khz_60db_1s_48k.f64', syn), x, ...
    struct('unit', 'Pa', 'description', 'pure tone 1 kHz 60 dB SPL, 1 s, seed 42'));

x = synth_am(44100, 1, 1000, 4, 100, 70);
writer_f64(c, sprintf('%s/am_tone_fc1k_fmod4_m100_70db_1s_44k1.f64', syn), x, ...
    struct('unit', 'Pa', 'description', 'AM tone fc 1 kHz fmod 4 Hz depth 100 pct, 70 dB SPL, 1 s, seed 42'));

x = synth_fm(44100, 1, 1500, 4, 700, 70);
writer_f64(c, sprintf('%s/fm_tone_fc1500_fmod4_df700_70db_1s_44k1.f64', syn), x, ...
    struct('unit', 'Pa', 'description', 'FM tone fc 1.5 kHz fmod 4 Hz deviation 700 Hz, 70 dB SPL, 1 s, seed 42'));

x = synth_noise_band(48000, 1, 4000, 800, 70, 42);
writer_f64(c, sprintf('%s/noise_band_fc4k_bw800_70db_1s_48k.f64', syn), x, ...
    struct('unit', 'Pa', 'description', 'band-limited noise fc 4 kHz BW 800 Hz, 70 dB SPL RMS, 1 s, rng(42)'));

% two float32 wav anchors (values are what audioread returns)
x = synth_pink(44100, 8, 70, 42);
write_wav_f32(c, sprintf('%s/pink_noise_8s_44k1_70db.wav', syn), x, 44100, ...
    'pink noise 8 s 44.1 kHz 70 dB SPL RMS, rng(42)');

x = synth_am(48000, 10, 1000, 70, 100, 70);
write_wav_f32(c, sprintf('%s/am_tone_fc1k_fmod70_m100_70db_10s_48k.wav', syn), x, 48000, ...
    'AM tone fc 1 kHz fmod 70 Hz depth 100 pct, 70 dB SPL, 10 s, seed 42');

writer_json(c, sprintf('%s/README.json', syn), struct( ...
    'seed', 42, 'generator', 'rng(42, ''twister'') then deterministic synthesis', ...
    'spl_reference', '20 uPa, RMS-calibrated (band noise/pink)', ...
    'calibration_convention', 'SQAT: dBFS = 94 dB SPL corresponds to 1 Pa rms'));
end

function write_wav_f32(c, rel, x, fs, desc)
if c.dryrun
    register_file(c, rel, "", numel(x) * 4 + 44);
    return;
end
abs_p = fullfile(c.out_root, char(rel));
d = fileparts(abs_p);
if ~isfolder(d), mkdir(d); end
audiowrite(abs_p, single(x), fs, 'BitsPerSample', 32);
register_file(c, rel, sha256_file(abs_p), dir(abs_p).bytes);
writer_json(c, [rel '.meta.json'], struct('fs', fs, 'dtype', 'f32', ...
    'description', desc));
end

% ========================================================================
% Section: signals/reference (spec 9)
% =========================================================================

function sec_signals_reference(c)
if ~should_run(c, 'signals/reference'), return; end
ref = 'signals/reference';

% TrainStation 10 s stereo trim (30 s source; fixed 0-10 s window)
src = fullfile(c.sqat_root, 'sound_files', 'reference_signals', ...
    'ExStereo_TrainStation7-0100-0130.wav');
[x, fs] = audioread(src);
n10 = 10 * fs;
if size(x, 1) < n10
    error('export_goldens:trim', 'TrainStation source shorter than 10 s');
end
write_wav_f32(c, sprintf('%s/trainstation_10s_stereo.wav', ref), x(1:n10, :), fs, ...
    'ExStereo_TrainStation7-0100-0130.wav trimmed to first 10 s (stereo, 48 kHz)');
writer_json(c, sprintf('%s/trainstation_10s_stereo.provenance.json', ref), struct( ...
    'source', 'sound_files/reference_signals/ExStereo_TrainStation7-0100-0130.wav', ...
    'source_sha256', string(sha256_file(src)), ...
    'trim', struct('start_s', 0, 'duration_s', 10, 'rule', 'fixed window from 0 s'), ...
    'baseline_sha', c.baseline_sha));

% RefSignal ECMA 2 s trim
src = fullfile(c.sqat_root, 'sound_files', 'reference_signals', ...
    'RefSignal_Loudness_ECMA418_2.wav');
[x, fs] = audioread(src);
n2 = 2 * fs;
write_wav_f32(c, sprintf('%s/refsignal_ecma_2s.wav', ref), x(1:n2), fs, ...
    'RefSignal_Loudness_ECMA418_2.wav trimmed to first 2 s');
writer_json(c, sprintf('%s/refsignal_ecma_2s.provenance.json', ref), struct( ...
    'source', 'sound_files/reference_signals/RefSignal_Loudness_ECMA418_2.wav', ...
    'source_sha256', string(sha256_file(src)), ...
    'trim', struct('start_s', 0, 'duration_s', 2)));

% RefSignal Daniel 5 s: source is exactly 5 s, copied verbatim
src = fullfile(c.sqat_root, 'sound_files', 'reference_signals', ...
    'RefSignal_Roughness_Daniel1997.wav');
writer_copy(c, string(src), sprintf('%s/refsignal_daniel_5s.wav', ref));
writer_json(c, sprintf('%s/refsignal_daniel_5s.provenance.json', ref), struct( ...
    'source', 'sound_files/reference_signals/RefSignal_Roughness_Daniel1997.wav', ...
    'source_sha256', string(sha256_file(src)), 'trim', 'none (full 5 s)'));
end

% ========================================================================
% Section: level1/resample (spec 4.1)
% =========================================================================

function sec_level1_resample(c)
if ~should_run(c, 'level1/resample'), return; end
d = 'level1/resample';

e = [1; zeros(8191, 1)];
writer_f64(c, sprintf('%s/impulse_8192.f64', d), e, ...
    struct('unit', '', 'description', 'unit impulse, 8192 samples'));

fs_list = [8000 11025 16000 22050 24000 32000 44100 48000];
for tgt = [48000 44100]
    for fs = fs_list
        if fs == tgt
            continue;   % native, no resample
        end
        g = gcd(tgt, fs);
        p = tgt / g;
        q = fs / g;
        y = resample(e, p, q);
        writer_f64(c, sprintf('%s/resample_impulse_%d_to_%d_p%d_q%d.f64', ...
            d, fs, tgt, p, q), y, struct('unit', '', ...
            'description', sprintf('resample(impulse,%d,%d): gcd form %d->%d', ...
            p, q, fs, tgt)));
    end
end

% direct (non-reduced) forms used by Do_OB13_ISO532_1 and EPNL
y = resample(e, 48000, 44100);
writer_f64(c, sprintf('%s/resample_impulse_44100_to_48000_direct_p48000_q44100.f64', d), ...
    y, struct('unit', '', 'description', 'resample(impulse,48000,44100) direct form (no gcd reduction)'));
y = resample(e, 48000, 22050);
writer_f64(c, sprintf('%s/resample_impulse_22050_to_48000_direct_p48000_q22050.f64', d), ...
    y, struct('unit', '', 'description', 'resample(impulse,48000,22050) direct form (no gcd reduction)'));

% identity anchor for the property tests
y = resample(e, 1, 1);
writer_f64(c, sprintf('%s/resample_impulse_identity_p1_q1.f64', d), y, ...
    struct('unit', '', 'description', 'resample(impulse,1,1) identity'));

% chirps at 5 representative ratios
pairs = [8000 48000; 24000 48000; 32000 44100; 44100 48000; 48000 44100];
for k = 1:size(pairs, 1)
    fs = pairs(k, 1);
    tgt = pairs(k, 2);
    t = (0:round(0.5*fs)-1)' / fs;
    xc = chirp(t, 100, 0.5, 0.45*fs);
    writer_f64(c, sprintf('%s/chirp_05s_%d.f64', d, fs), xc, ...
        struct('unit', 'Pa', 'description', sprintf('log chirp 100 Hz..%.0f Hz, 0.5 s at %d Hz', 0.45*fs, fs)));
    g = gcd(tgt, fs);
    p = tgt / g;
    q = fs / g;
    y = resample(xc, p, q);
    writer_f64(c, sprintf('%s/resample_chirp_%d_to_%d_p%d_q%d.f64', d, fs, tgt, p, q), ...
        y, struct('unit', 'Pa', 'description', sprintf('resample(chirp,%d,%d) %d->%d', p, q, fs, tgt)));
end
end

% ========================================================================
% Section: level1/sos (spec 4.2 and 8.2)
% =========================================================================

function sec_level1_sos(c)
if ~should_run(c, 'level1/sos'), return; end
d = 'level1/sos';

% 4 Hweight .mat of the FS private dir (variables Hweight_LP / Hweight_HP)
fsk = [44100 48000];
kinds = {'LP', 'HP'};
for i = 1:numel(fsk)
    for j = 1:numel(kinds)
        f = fullfile(c.sqat_root, 'psychoacoustic_metrics', ...
            'FluctuationStrength_Osses2016', 'private', ...
            sprintf('Hweight-%d-Hz-%s.mat', fsk(i), kinds{j}));
        S = load(f);
        H = S.(['Hweight_' kinds{j}]);
        assert_sos_(H);
        writer_f64(c, sprintf('%s/sos_hweight_%d_%s.f64', d, fsk(i), lower(kinds{j})), ...
            H, struct('unit', '', 'description', sprintf( ...
            'SOS cascade of Hweight-%d-Hz-%s.mat, rows [b0 b1 b2 a0 a1 a2]', ...
            fsk(i), kinds{j})));
    end
end

% Get_Hweight_roughness is pure inline tables (no .mat) but lives in a
% private/ dir; expose a verbatim copy in a helper dir (baseline untouched)
hdir = expose_private_(c, 'psychoacoustic_metrics/Roughness_Daniel1997/private/Get_Hweight_roughness.m');
addpath(hdir);
Hr = Get_Hweight_roughness(9600, 48000);
writer_f64(c, sprintf('%s/sos_hweight_roughness_48000.f64', d), Hr, ...
    struct('unit', '', 'description', 'Get_Hweight_roughness(9600,48000) weighting rows [47 x 9600]'));
Hr = Get_Hweight_roughness(8820, 44100);
writer_f64(c, sprintf('%s/sos_hweight_roughness_44100.f64', d), Hr, ...
    struct('unit', '', 'description', 'Get_Hweight_roughness(8820,44100) weighting rows [47 x 8820]'));

% deterministic test signal through filters with state
t = (0:47999)' / 48000;
xq = chirp(t, 100, 1, 20000);
writer_f64(c, sprintf('%s/state_input.f64', d), xq, ...
    struct('unit', 'Pa', 'description', 'shared chirp input for biquad/cascade/block cases'));

% (a) single biquad = first section of Hweight-48000-LP
S48 = load(fullfile(c.sqat_root, 'psychoacoustic_metrics', ...
    'FluctuationStrength_Osses2016', 'private', 'Hweight-48000-Hz-LP.mat'));
H = S48.Hweight_LP;
b = H(1, 1:3);
a = H(1, 4:6);
if abs(a(1) - 1) > eps
    b = b / a(1);
    a = a / a(1);
end
writer_f64(c, sprintf('%s/biquad_coeffs.f64', d), [b, a], ...
    struct('unit', '', 'description', 'biquad [b0 b1 b2 a0 a1 a2], first section of Hweight-48000-LP'));
[y, zf] = filter(b, a, xq);
writer_f64(c, sprintf('%s/biquad_out.f64', d), y, ...
    struct('unit', 'Pa', 'description', 'filter(b,a,x) full output'));
writer_f64(c, sprintf('%s/biquad_zi_final.f64', d), zf, ...
    struct('unit', '', 'description', 'filter final state [1 x 2] (direct form II transposed)'));

% (b) full SOS cascade with final Zi (per-section filter; this SPT sosfilt
% does not expose states, and the state semantics ARE the contract)
[yc, zc] = sos_cascade_(H, xq);
writer_f64(c, sprintf('%s/cascade_out.f64', d), yc, ...
    struct('unit', 'Pa', 'description', 'sosfilt(Hweight_48000_LP, x) full output'));
writer_f64(c, sprintf('%s/cascade_zi_final.f64', d), zc, ...
    struct('unit', '', 'description', 'sosfilt final state [n_sections x 2]'));

% (c) two-block stitching: Zi carried across the seam
half = floor(numel(xq) / 2);
[y1, z1] = sos_cascade_(H, xq(1:half));
[y2, z2] = sos_cascade_seeded_(H, xq(half+1:end), z1);
writer_f64(c, sprintf('%s/block1_out.f64', d), y1, ...
    struct('unit', 'Pa', 'description', 'block 1 output'));
writer_f64(c, sprintf('%s/block1_zi.f64', d), z1, ...
    struct('unit', '', 'description', 'state carried to block 2'));
writer_f64(c, sprintf('%s/block2_out.f64', d), y2, ...
    struct('unit', 'Pa', 'description', 'block 2 output with seeded Zi'));
writer_f64(c, sprintf('%s/block2_zi_final.f64', d), z2, ...
    struct('unit', '', 'description', 'final state after block 2'));
end

function [y, zf] = sos_cascade_(H, x)
% cascade the SOS sections with explicit direct form II transposed state
% (same semantics as MATLAB sosfilt internals; states are the contract)
y = x(:);
zf = zeros(size(H, 1), 2);
for s = 1:size(H, 1)
    b = H(s, 1:3);
    a = H(s, 4:6);
    if abs(a(1) - 1) > eps
        b = b / a(1);
        a = a / a(1);
    end
    [y, z1] = filter(b, a, y, zf(s, :).');
    zf(s, :) = z1.';
end
end

function [y, zf] = sos_cascade_seeded_(H, x, zseed)
y = x(:);
zf = zseed;
for s = 1:size(H, 1)
    b = H(s, 1:3);
    a = H(s, 4:6);
    if abs(a(1) - 1) > eps
        b = b / a(1);
        a = a / a(1);
    end
    [y, z1] = filter(b, a, y, zf(s, :).');
    zf(s, :) = z1.';
end
end

function assert_sos_(H)
if size(H, 2) ~= 6
    error('export_goldens:sos', 'SOS matrix must have 6 columns, got %d', size(H, 2));
end
end

% ========================================================================
% Section: level1/buffer (spec 4.3)
% =========================================================================

function sec_level1_buffer(c)
if ~should_run(c, 'level1/buffer'), return; end
d = 'level1/buffer';

% (N, overlap, nodelay?) pairs derived from the .m files (spec 4.3 + F0.6)
pairs = {11025, 5513, true;   % Aures frames
         88200, 79380, true;  % FS 2 s window at 44.1 kHz (0.9*N)
         24000, 0, false;     % EPNL dt blocks at 48 kHz (buffer(x,Nbins))
         16384, 12288, true;  % shm Roughness (overlap 0.75)
         8192, 6144, true;    % shm Tonality largest block
         4096, 3072, true; ...
         2048, 1536, true; ...
         1024, 768, true};
for k = 1:size(pairs, 1)
    N = pairs{k, 1};
    ov = pairs{k, 2};
    nd = pairs{k, 3};
    hop = N - ov;
    n = N + 2 * hop + 37;    % ~3 frames: overlap + tail padding exercised
    t = (0:n-1)' / 48000;
    x = 0.5 * sin(2*pi*1000*t) + 0.05 * sin(2*pi*3700*t);
    if nd
        B = buffer(x, N, ov, 'nodelay');
        tag = 'nodelay';
    else
        B = buffer(x, N);
        tag = 'plain';
    end
    base = sprintf('%s/buffer_n%d_ov%d_%s', d, N, ov, tag);
    writer_f64(c, sprintf('%s_input.f64', base), x, ...
        struct('unit', 'Pa', 'description', sprintf('buffer input for N=%d ov=%d %s', N, ov, tag)));
    meta = struct('unit', 'Pa', 'description', sprintf( ...
        'buffer(x,%d,%d%s) frames; frame count recorded here', N, ov, ...
        iif_(nd, ", 'nodelay'", '')));
    meta.frames = size(B, 2);
    writer_f64(c, sprintf('%s_out.f64', base), B, meta);
end
end

function v = iif_(cond, a, b_)
if cond
    v = a;
else
    v = b_;
end
end

% ========================================================================
% Section: level1/window (spec 4.4)
% =========================================================================

function sec_level1_window(c)
if ~should_run(c, 'level1/window'), return; end
d = 'level1/window';
w = hann(11025);
writer_f64(c, sprintf('%s/hann_sym_11025.f64', d), w, ...
    struct('unit', '', 'description', 'hann(11025) default = symmetric (Aures frame window)'));
w = hann(512, 'periodic');
writer_f64(c, sprintf('%s/hann_per_512.f64', d), w, ...
    struct('unit', '', 'description', 'hann(512,''periodic'') (ECMA roughness envelope spectrum)'));
w = blackman(8820, 'periodic');
writer_f64(c, sprintf('%s/blackman_per_8820.f64', d), w, ...
    struct('unit', '', 'description', 'blackman(8820,''periodic'') (Daniel native 44.1 kHz)'));
w = blackman(9600, 'periodic');
writer_f64(c, sprintf('%s/blackman_per_9600.f64', d), w, ...
    struct('unit', '', 'description', 'blackman(9600,''periodic'') (Daniel native 48 kHz)'));
end

% ========================================================================
% Section: level1/interp1 (spec 4.5)
% =========================================================================

function sec_level1_interp1(c)
if ~should_run(c, 'level1/interp1'), return; end
d = 'level1/interp1';

xn = [20 35 60 90 130 180 240 310 390 480 580 690 810 940 1080 1230 ...
      1390 1560 1740 1930 2130]';
yn = 40 + 30 * log10(xn / 20) + 3 * sin(xn / 90);
xq = [linspace(10, 2400, 101)'] ;
writer_f64(c, sprintf('%s/nodes_x.f64', d), xn, struct('unit', 'Hz', ...
    'description', 'non-uniform interpolation nodes (covers edge extrapolation)'));
writer_f64(c, sprintf('%s/nodes_y.f64', d), yn, struct('unit', 'dB', ...
    'description', 'node values'));
writer_f64(c, sprintf('%s/query_x.f64', d), xq, struct('unit', 'Hz', ...
    'description', 'query points including outside the mesh'));
writer_f64(c, sprintf('%s/out_linear.f64', d), interp1(xn, yn, xq, 'linear'), ...
    struct('unit', 'dB', 'description', 'interp1 linear'));
writer_f64(c, sprintf('%s/out_spline.f64', d), interp1(xn, yn, xq, 'spline'), ...
    struct('unit', 'dB', 'description', 'interp1 spline (not-a-knot)'));
writer_f64(c, sprintf('%s/out_pchip.f64', d), interp1(xn, yn, xq, 'pchip'), ...
    struct('unit', 'dB', 'description', 'interp1 pchip'));

% Aures semantics: interp1(FreqNoise, SPLnoise, FreqCrop, 'linear', 'extrap')
rng(5, 'twister');
FreqNoise = (20:4:5000)';
SPLnoise = 60 - 12 * log10(FreqNoise / 20 + 1) + 0.8 * randn(size(FreqNoise));
FreqCrop = [5; 10; 15; FreqNoise; 5005; 5100; 5500];
writer_f64(c, sprintf('%s/aures_freqnoise.f64', d), FreqNoise, struct('unit', 'Hz', ...
    'description', 'Aures case: noise spectrum frequency axis (4 Hz spacing)'));
writer_f64(c, sprintf('%s/aures_splnoise.f64', d), SPLnoise, struct('unit', 'dB', ...
    'description', 'Aures case: noise spectrum level, rng(5)'));
writer_f64(c, sprintf('%s/aures_freqcrop.f64', d), FreqCrop, struct('unit', 'Hz', ...
    'description', 'query axis including points outside the mesh'));
writer_f64(c, sprintf('%s/aures_out_linear_extrap.f64', d), ...
    interp1(FreqNoise, SPLnoise, FreqCrop, 'linear', 'extrap'), ...
    struct('unit', 'dB', 'description', 'interp1(...,''linear'',''extrap'') Tonality_Aures1985 L442'));

% ECMA roughness semantics: pchip on the 50 Hz block-time axis (Eq 103)
x = (0:115)' / 48000;
modAmpMax = 0.4 * exp(-((x - 0.0012) / 0.0006).^2) + 0.2;
l50 = floor(115 / 48000 * 50) + 1;
xq50 = linspace(0, 115 / 48000, l50);
writer_f64(c, sprintf('%s/ecma_pchip_blocktime.f64', d), x, struct('unit', 's', ...
    'description', 'ECMA pchip case: block time axis (iBlocksOut-1)/48e3'));
writer_f64(c, sprintf('%s/ecma_pchip_modampmax.f64', d), modAmpMax, struct('unit', '', ...
    'description', 'ECMA pchip case: per-block modulation max'));
writer_f64(c, sprintf('%s/ecma_pchip_out_50hz.f64', d), pchip(x, modAmpMax, xq50), ...
    struct('unit', '', 'description', 'pchip(x, modAmpMax, xq) on the 50 Hz axis'));
end

% ========================================================================
% Section: level1/fft + hilbert (spec 4.6, corrected size list)
% =========================================================================

function sec_level1_fft(c)
if ~should_run(c, 'level1/fft'), return; end
d = 'level1/fft';
rng(43, 'twister');

sizes = [512 2048 4096 8192 16384 8820 9600 11025 12000 88200];
for N = sizes
    t = (0:N-1)' / N;
    xr = 0.3 * sin(2*pi*13*t) + 0.2 * sin(2*pi*57*t + 0.4) + 0.05 * randn(N, 1);
    writer_f64(c, sprintf('%s/fft_in_real_%d.f64', d, N), xr, ...
        struct('unit', 'Pa', 'description', sprintf('deterministic real input, N=%d, rng(43) stream', N)));
    writer_c64(c, sprintf('%s/fft_out_real_%d', d, N), fft(xr), ...
        struct('unit', '', 'description', sprintf('fft(x) of the real input, N=%d', N)));
end

% complex inputs only where the toolbox semantics need them (mixed radix)
for N = [8192, 11025]
    t = (0:N-1)' / N;
    xr = 0.3 * sin(2*pi*13*t) + 0.05 * randn(N, 1);
    xi = 0.2 * sin(2*pi*29*t + 0.9) + 0.05 * randn(N, 1);
    writer_f64(c, sprintf('%s/fft_in_cplx_%d_re.f64', d, N), xr, ...
        struct('unit', '', 'description', 'complex input real part'));
    writer_f64(c, sprintf('%s/fft_in_cplx_%d_im.f64', d, N), xi, ...
        struct('unit', '', 'description', 'complex input imag part'));
    writer_c64(c, sprintf('%s/fft_out_cplx_%d', d, N), fft(xr + 1i*xi), ...
        struct('unit', '', 'description', sprintf('fft(z) of the complex input, N=%d', N)));
end

% hilbert envelope semantics of the ECMA roughness (16384 block)
N = 16384;
t = (0:N-1)' / 48000;
xh = 0.5 * (1 + 0.8 * sin(2*pi*70*t)) .* sin(2*pi*1000*t);
writer_f64(c, sprintf('%s/hilbert_in_16384.f64', d), xh, ...
    struct('unit', 'Pa', 'description', 'AM tone for hilbert envelope, 16384 samples'));
zh = hilbert(xh);
writer_c64(c, sprintf('%s/hilbert_out_16384', d), zh, ...
    struct('unit', '', 'description', 'hilbert(x) analytic signal'));
writer_f64(c, sprintf('%s/hilbert_env_16384.f64', d), abs(zh), ...
    struct('unit', 'Pa', 'description', 'abs(hilbert(x)) envelope (pre downsample 32)'));
end

% ========================================================================
% Section: level1/util (spec 4.7)
% =========================================================================

function sec_level1_util(c)
if ~should_run(c, 'level1/util'), return; end
d = 'level1/util';

% calculate_a0 curves + FIR taps
a0_cases = {48000, 9600, 'fastl2007'; ...
            44100, 8820, 'fastl2007'; ...
            44100, 4096, 'fluctuationstrength_osses2016'; ...
            44100, 4096, 'fastl2007'};
for k = 1:size(a0_cases, 1)
    fs = a0_cases{k, 1};
    N = a0_cases{k, 2};
    ty = a0_cases{k, 3};
    [B, freqs, a0] = calculate_a0(fs, N, ty);
    base = sprintf('%s/a0_%s_%d_%d', d, ty, fs, N);
    writer_f64(c, sprintf('%s_freqs.f64', base), freqs(:), ...
        struct('unit', 'Hz', 'description', 'calculate_a0 frequency grid (qb bins)'));
    writer_f64(c, sprintf('%s_a0.f64', base), a0(:), ...
        struct('unit', '', 'description', sprintf('calculate_a0(%d,%d,''%s'') a0 transfer factor', fs, N, ty)));
    writer_f64(c, sprintf('%s_fir.f64', base), B(:), ...
        struct('unit', '', 'description', sprintf('create_a0_FIR taps via fir2, %d coefficients', numel(B))));
end

% Terhardt_filterbank_params for the (N, fs) pairs used
prm = {9600, 48000; 8820, 44100; 11025, 44100; 88200, 44100};
for k = 1:size(prm, 1)
    N = prm{k, 1};
    fs = prm{k, 2};
    P = Terhardt_filterbank_params(N, fs);
    base = sprintf('%s/terhardt_params_%d_%d', d, N, fs);
    writer_json(c, sprintf('%s.json', base), jsonable_(P));
    writer_f64(c, sprintf('%s_freqs.f64', base), P.freqs(:), ...
        struct('unit', 'Hz', 'description', sprintf('Terhardt_filterbank_params(%d,%d).freqs', N, fs)));
end

% excitation patterns of a known synthetic spectrum + the clamp warning unit
util_terhardt_case_(c, d, 70,  'terhardt_exc_1khz_70db');
util_terhardt_case_(c, d, 130, 'terhardt_clamp_1khz_130db', true);

% converter round-trips on a dense grid
f = (20:10:20000)';
z = hz2bark_local(f);
fr = bark2hz_local(z);
writer_f64(c, sprintf('%s/conv_hz_grid.f64', d), f, struct('unit', 'Hz', 'description', 'converter grid'));
writer_f64(c, sprintf('%s/conv_hz2bark.f64', d), z, struct('unit', 'Bark', 'description', 'hz2bark_local(f)'));
writer_f64(c, sprintf('%s/conv_bark2hz_roundtrip.f64', d), fr, struct('unit', 'Hz', 'description', 'bark2hz_local(hz2bark_local(f))'));
phon = (0:0.25:120)';
sone = phon2sone_local(phon);
back = sone2phon_local(sone);
writer_f64(c, sprintf('%s/conv_phon_grid.f64', d), phon, struct('unit', 'phon', 'description', 'converter grid'));
writer_f64(c, sprintf('%s/conv_phon2sone.f64', d), sone, struct('unit', 'sone', 'description', 'phon2sone_local(phon)'));
writer_f64(c, sprintf('%s/conv_sone2phon_roundtrip.f64', d), back, struct('unit', 'phon', 'description', 'sone2phon_local(phon2sone_local(phon))'));
end

function util_terhardt_case_(c, d, db, name, want_warning)
if nargin < 5
    want_warning = false;
end
x = synth_tone(48000, 0.2, 1000, db);
win = blackman(9600, 'periodic');
params = Terhardt_filterbank_params(9600, 48000);
FreqIn = fft(x(1:9600) .* win);
FreqIn = FreqIn(:).';   % Terhardt_filterbank expects a [1 x N] spectrum
writer_c64(c, sprintf('%s/%s_input_spec', d, name), FreqIn, ...
    struct('unit', '', 'description', sprintf('fft of blackman-windowed 1 kHz %d dB tone', db)));
lastwarn('', '');
if want_warning
    ei = Terhardt_filterbank(FreqIn, params);   % nargout<2 => warning fires
    [msg, wid] = lastwarn;
    writer_json(c, sprintf('%s/%s_warnings.json', d, name), ...
        struct('warnings', {{struct('id', string(wid), 'message', string(msg))}}));
else
    [ei, info] = Terhardt_filterbank(FreqIn, params);
    writer_json(c, sprintf('%s/%s_info.json', d, name), jsonable_(info));
end
step = 4;
if c.full, step = 1; end
ei_dec = ei(:, 1:step:end);
meta = struct('unit', '', 'description', 'Terhardt_filterbank excitation patterns ei [Chno x N], columns decimated x4', ...
    'decimated', struct('factor', 4, 'axis', 1, 'original_shape', size(ei)));
if c.full
    meta = struct('unit', '', 'description', 'Terhardt_filterbank excitation patterns ei [Chno x N]');
end
writer_f64(c, sprintf('%s/%s_ei.f64', d, name), ei_dec, meta);
end

function s = jsonable_(S)
s = S;
fn = fieldnames(s);
for i = 1:numel(fn)
    v = s.(fn{i});
    if isnumeric(v) && ~isvector(v) && ~isscalar(v)
        s.(fn{i}) = struct('shape', size(v), 'data', reshape(v, 1, []));
    end
end
end

% ========================================================================
% Section: validation (spec 6, level-2 data)
% =========================================================================

function sec_level1_leq(c)
if ~should_run(c, 'level1/leq'), return; end
d = 'level1/leq';
% one level series (a NaN in it), Get_Leq(levels, fs, dt, framelen) over
% frame layouts: exact frames, padded tail, overlap, fractional dt
L = 60 + 20 * sin((1:23)' * 0.7);
L(5) = NaN;
writer_f64(c, sprintf('%s/levels.f64', d), L, ...
    struct('unit', 'dB', 'description', 'Get_Leq input levels (sample 5 is NaN)'));
cases = {1, 2, 2; 1, 1, 3; 10, 0.5, 1.3; 1, 23, 23; 1, 4, 6};
for k = 1:size(cases, 1)
    [fs, dt, fl] = cases{k, :};
    Leq = Get_Leq(L, fs, dt, fl);
    meta = struct('unit', 'dB', 'description', sprintf( ...
        'Get_Leq(levels, %g, %g, %g), one Leq per buffer column', fs, dt, fl));
    meta.fs = fs;
    meta.dt = dt;
    meta.framelen = fl;
    writer_f64(c, sprintf('%s/leq_case%d.f64', d, k), Leq(:), meta);
end
end

function sec_validation(c)
if ~should_run(c, 'validation'), return; end
val_base = fullfile(c.sqat_root, 'validation');
vsq = fullfile(c.extras_root, 'sound_files', 'validation_SQAT_v1_0');

val_loudness_iso_(c, val_base, vsq);
val_aures_(c, val_base, vsq);
val_sharpness_(c, vsq);
val_fs_(c, vsq);
val_daniel_(c, val_base, vsq);
val_ecma_(c, val_base);
val_slm_(c, val_base);
val_epnl_(c, val_base);
end

function val_loudness_iso_(c, val_base, vsq)
d = 'validation/loudness_iso532_1';
iso = fullfile(val_base, 'Loudness_ISO532_1');

% 3 xlsx: original (renamed lowercase) + derived json, reconferido (spec 8.3)
xlsx_src = { ...
    fullfile(iso, '1_synthetic_signals_stationary_loudness', 'reference_values', ...
        'Results and tests for synthetic signals (stationary loudness).xlsx'), ...
        'results_and_tests_synthetic_signals_stationary_loudness.xlsx'; ...
    fullfile(iso, '2_synthetic_signals_time_varying_loudness', 'reference_values', ...
        'Results and tests for synthetic signals (time varying loudness).xlsx'), ...
        'results_and_tests_synthetic_signals_time_varying_loudness.xlsx'; ...
    fullfile(iso, '3_technical_signals_time_varying_loudness', 'reference_values', ...
        'Results and tests for technical signals (time varying loudness).xlsx'), ...
        'results_and_tests_technical_signals_time_varying_loudness.xlsx'};
for k = 1:size(xlsx_src, 1)
    src = xlsx_src{k, 1};
    dst = xlsx_src{k, 2};
    writer_copy(c, string(src), sprintf('%s/%s', d, dst));
    sheets = sheetnames(src);
    derived = struct();
    skipped = {};
    for s = 1:numel(sheets)
        raw = readcell(src, 'Sheet', sheets{s});
        if numel(raw) > 5000
            % giant formatted sheet: values remain in the xlsx (calamine);
            % the derived json carries only its shape to stay in budget
            derived.(matlab_field_(sheets{s})) = struct('skipped', true, ...
                'size', size(raw), 'reason', 'sheet larger than 5000 cells');
            skipped{end+1} = sheets{s}; %#ok<AGROW>
        else
            derived.(matlab_field_(sheets{s})) = cells_to_jsonable_(raw);
        end
    end
    writer_json(c, sprintf('%s/%s.json', d, dst), derived);
    % reconferir the sheets that were exported (spec 6: json derivado conferido)
    for s = 1:numel(sheets)
        raw = readcell(src, 'Sheet', sheets{s});
        if numel(raw) <= 5000
            chk = cells_to_jsonable_(raw);
            if ~isequal(chk, derived.(matlab_field_(sheets{s})))
                error('export_goldens:xlsx', 'xlsx derived json mismatch: %s / %s', dst, sheets{s});
            end
        end
    end
end

val_loudness_nt_(c, d, xlsx_src{2, 1}, xlsx_src{2, 2}, 6:13, 'free');
val_loudness_nt_(c, d, xlsx_src{3, 1}, xlsx_src{3, 2}, 14:25, 'diffuse');

% 5 stationary reference .mat -> json
for n = 1:5
    src = fullfile(iso, '1_synthetic_signals_stationary_loudness', ...
        'reference_values', sprintf('reference_values_ISO532_1_2017_signal_%d.mat', n));
    S = load(src);
    writer_json(c, sprintf('%s/ref_signal_%d.json', d, n), mat_to_jsonable_(S));
end

% 25 Annex B/C wavs: synthetics 2-13 + calibration + all 12 technicals full
wav_src = { ...
    'Test signal 2 (250 Hz 80 dB).wav', 'test_signal_02_250hz_80db.wav'; ...
    'Test signal 3 (1 kHz 60 dB).wav', 'test_signal_03_1khz_60db.wav'; ...
    'Test signal 4 (4 kHz 40 dB).wav', 'test_signal_04_4khz_40db.wav'; ...
    'Test signal 5 (pinknoise 60 dB).wav', 'test_signal_05_pinknoise_60db.wav'; ...
    'Test signal 6 (tone 250 Hz 30 dB - 80 dB).wav', 'test_signal_06_tone_250hz_30db_80db.wav'; ...
    'Test signal 7 (tone 1 kHz 30 dB - 80 dB).wav', 'test_signal_07_tone_1khz_30db_80db.wav'; ...
    'Test signal 8 (tone 4 kHz 30 dB - 80 dB).wav', 'test_signal_08_tone_4khz_30db_80db.wav'; ...
    'Test signal 9 (pink noise 0 dB - 50 dB).wav', 'test_signal_09_pink_noise_0db_50db.wav'; ...
    'Test signal 10 (tone pulse 1 kHz 10 ms 70 dB).wav', 'test_signal_10_tone_pulse_1khz_10ms_70db.wav'; ...
    'Test signal 11 (tone pulse 1 kHz 50 ms 70 dB).wav', 'test_signal_11_tone_pulse_1khz_50ms_70db.wav'; ...
    'Test signal 12 (tone pulse 1 kHz 500 ms 70 dB).wav', 'test_signal_12_tone_pulse_1khz_500ms_70db.wav'; ...
    'Test signal 13 (combined tone pulses 1 kHz).wav', 'test_signal_13_combined_tone_pulses_1khz.wav'; ...
    'Test signal 14 (propeller-driven airplane).wav', 'test_signal_14_propeller_driven_airplane.wav'; ...
    'Test signal 15 (vehicle interior 40 kmh).wav', 'test_signal_15_vehicle_interior_40kmh.wav'; ...
    'Test signal 16 (hairdryer).wav', 'test_signal_16_hairdryer.wav'; ...
    'Test signal 17 (machine gun).wav', 'test_signal_17_machine_gun.wav'; ...
    'Test signal 18 (hammer).wav', 'test_signal_18_hammer.wav'; ...
    'Test signal 19 (door creak).wav', 'test_signal_19_door_creak.wav'; ...
    'Test signal 20 (shaking coins).wav', 'test_signal_20_shaking_coins.wav'; ...
    'Test signal 21 (jackhammer).wav', 'test_signal_21_jackhammer.wav'; ...
    'Test signal 22 (ratchet wheel (large)).wav', 'test_signal_22_ratchet_wheel_large.wav'; ...
    'Test signal 23 (typewriter).wav', 'test_signal_23_typewriter.wav'; ...
    'Test signal 24 (woodpecker).wav', 'test_signal_24_woodpecker.wav'; ...
    'Test signal 25 (full can rattle).wav', 'test_signal_25_full_can_rattle.wav'; ...
    'calibration signal sine 1kHz 60dB.wav', 'calibration_signal_sine_1khz_60db.wav'};
idx = struct('source_dir', 'sound_files/validation_SQAT_v1_0/Loudness_ISO532_1 (Zenodo 7933206)');
renamed = cell(size(wav_src, 1), 1);
for k = 1:size(wav_src, 1)
    src = fullfile(vsq, 'Loudness_ISO532_1', wav_src{k, 1});
    writer_copy(c, string(src), sprintf('%s/annex_b/%s', d, wav_src{k, 2}));
    renamed{k} = wav_src{k, 2};
end
idx.mapping = struct('original', string(wav_src(:, 1)), 'renamed', string(renamed));
writer_json(c, sprintf('%s/annex_b/index.json', d), idx);
end

function val_loudness_nt_(c, d, src, xlsx_name, ks, field)
% ISO 532-1 Annex B reference N(t): sheet 'Test signal K', cols A-F from row 11
% (time, N, 5 pct band with 1-sample shift, N -/+ max(5 pct, 0.1 sone)) ->
% n_of_t/signal_KK.f64 [n,6]. Resume-safe: existing pairs are skipped.
desc = ['ISO 532-1:2017 Annex B reference N(t) of test signal %d, %s field: ' ...
    'columns [time s, N, Nmin, Nmax (sheet cols C,D: tolerance band with 1-sample ' ...
    'time shift), Nmin, Nmax (sheet cols E,F: N -/+ max(5 pct of N, 0.1 sone), ' ...
    'lower clamped at 0)]'];
for k = ks
    rel = sprintf('%s/n_of_t/signal_%02d.f64', d, k);
    if c.append && isfile(fullfile(c.out_root, rel)) && isfile(fullfile(c.out_root, [rel '.meta.json']))
        continue;
    end
    A = readmatrix(src, 'Sheet', sprintf('Test signal %d', k), 'Range', 'A11:F20000');
    A = A(1:find([isnan(A(:, 1)); true], 1) - 1, :);   % rows up to the first blank time
    writer_f64(c, rel, A, struct('unit', 's,sone,sone,sone,sone,sone', ...
        'description', sprintf(desc, k, field), ...
        'source', struct('m_file', xlsx_name, 'stage', sprintf('Test signal %d', k))));
end
end

function val_aures_(c, ~, vsq)
d = 'validation/tonality_aures1985';
src1 = fullfile(vsq, 'Tonality_Aures1985', '1Bark_tone_prominence_20dB_fc_1khz_44khz_64bit.wav');
src2 = fullfile(vsq, 'Tonality_Aures1985', '1Bark_tone_prominence_60dB_fc_1khz_44khz_64bit.wav');
pairs = {src1, 'aures_prominence_20db_3s'; src2, 'aures_prominence_60db_3s'};
for kp = 1:size(pairs, 1)
    [x, fs] = audioread(pairs{kp, 1});
    n3 = 3 * fs;
    writer_f64(c, sprintf('%s/%s.f64', d, pairs{kp, 2}), x(1:n3), ...
        struct('unit', 'Pa', 'description', sprintf( ...
        '1Bark prominence wav trimmed to first 3 s, fs=%d Hz (64-bit float source)', fs)));
    writer_json(c, sprintf('%s/%s.provenance.json', d, pairs{kp, 2}), struct( ...
        'source', sprintf('sound_files/validation_SQAT_v1_0/Tonality_Aures1985/%s', leaf_name_(pairs{kp, 1})), ...
        'source_sha256', string(sha256_file(pairs{kp, 1})), ...
        'trim', struct('start_s', 0, 'duration_s', 3)));
end
% Zhang/Shrestha spectra enter as-is (spec 6/8.4)
base = fullfile(c.sqat_root, 'validation', 'Tonality_Aures1985', 'reference_values');
writer_copy(c, string(fullfile(base, 'ZhangShrestha2003_AppendixC_Test1.txt')), ...
    sprintf('%s/zhangshrestha2003_appendixc_test1.txt', d));
writer_copy(c, string(fullfile(base, 'ZhangShrestha2003_AppendixC_Test2.txt')), ...
    sprintf('%s/zhangshrestha2003_appendixc_test2.txt', d));
end

function s = leaf_name_(p)
[~, s] = fileparts(char(p));
s = char(s);
end

function val_sharpness_(c, vsq)
d = 'validation/sharpness_din45692';
names = {'narrowband_250.wav', 'narrowband_1000.wav', 'narrowband_4800.wav', 'broadband_1000.wav'};
for k = 1:numel(names)
    src = fullfile(vsq, 'Sharpness_DIN45692', names{k});
    writer_copy(c, string(src), sprintf('%s/%s', d, names{k}));
end
end

function val_fs_(c, vsq)
d = 'validation/fluctuation_strength_osses2016';
src_names = { ...
    'AM-tone-fc-1000_fmod-1_mdept-100-SPL-70-dB.wav', 'am_fc1000_fmod1_m100_70db.wav'; ...
    'AM-tone-fc-1000_fmod-2_mdept-100-SPL-70-dB.wav', 'am_fc1000_fmod2_m100_70db.wav'; ...
    'AM-tone-fc-1000_fmod-4_mdept-100-SPL-60-dB.wav', 'am_fc1000_fmod4_m100_60db.wav'; ...
    'AM-tone-fc-1000_fmod-8_mdept-100-SPL-70-dB.wav', 'am_fc1000_fmod8_m100_70db.wav'; ...
    'AM-tone-fc-1000_fmod-16_mdept-100-SPL-70-dB.wav', 'am_fc1000_fmod16_m100_70db.wav'; ...
    'AM-tone-fc-1000_fmod-32_mdept-100-SPL-70-dB.wav', 'am_fc1000_fmod32_m100_70db.wav'; ...
    'FM-tone-fc-1500_fmod-4_deltaf-700-SPL-70-dB.wav', 'fm_fc1500_fmod4_df700_70db.wav'; ...
    'randomnoise-Fc-8010_BW-15980_Fmod-4_Mdept-100_SPL-60.wav', 'noise_fc8010_bw15980_fmod4_60db.wav'};
for k = 1:size(src_names, 1)
    src = fullfile(vsq, 'FluctuationStrength_Osses2016', src_names{k, 1});
    writer_copy(c, string(src), sprintf('%s/%s', d, src_names{k, 2}));
end
% summary json of the vary_modulation .mat (content record, not a golden)
src = fullfile(vsq, 'FluctuationStrength_Osses2016', 'vary_modulation_freq_fmod_1khz.mat');
S = load(src);
v = S.(first_field_(S));
writer_json(c, sprintf('%s/vary_modulation_freq_resumo.json', d), struct( ...
    'source', 'sound_files/validation_SQAT_v1_0/FluctuationStrength_Osses2016/vary_modulation_freq_fmod_1khz.mat', ...
    'variable', string(first_field_(S)), 'shape', size(v), ...
    'fmod_axis_hz', 0:10:160, 'fs_hz', 44100, ...
    'note', 'columns step fmod 0:10:160 Hz at fc 1 kHz; content record only'));
end

function val_daniel_(c, val_base, vsq)
d = 'validation/roughness_daniel1997';
mats = { ...
    'FM_fmod70_fc1600hz_fdev800_SPL40-80.mat'; 'FM_fmod_fc_1600hz.mat'; ...
    'FM_fmod_fc_1600hz_reference_tone.mat'; 'vary_modulation_depth.mat'; ...
    'vary_modulation_freq_fmod_125hz.mat'; 'vary_modulation_freq_fmod_1khz.mat'; ...
    'vary_modulation_freq_fmod_250hz.mat'; 'vary_modulation_freq_fmod_2khz.mat'; ...
    'vary_modulation_freq_fmod_4khz.mat'; 'vary_modulation_freq_fmod_500hz.mat'; ...
    'vary_modulation_freq_fmod_8khz.mat'};
for k = 1:numel(mats)
    src = fullfile(vsq, 'Roughness_Daniel1997', mats{k});
    S = load(src);
    vn = first_field_(S);
    M = S.(vn);
    if isfield(S, 'fs')
        fs_used = S.fs;
    else
        fs_used = 48000;
    end
    resumo = struct('source', ['sound_files/validation_SQAT_v1_0/Roughness_Daniel1997/' mats{k}], ...
        'variable', string(vn), 'shape', size(M), 'fs_hz', fs_used);
    if contains(mats{k}, '125hz')
        resumo.fmod_axis_hz = 20:10:100;
    elseif startsWith(mats{k}, 'vary_modulation_freq')
        resumo.fmod_axis_hz = 20:10:160;
    elseif contains(mats{k}, 'SPL40-80')
        resumo.spl_axis_db = 40:10:80;
    end
    writer_json(c, sprintf('%s/%s.json', d, ...
        strrep(strrep(lower(mats{k}), '.', '_'), '-', '_')), resumo);
end
% two full rows as f64 (row 1 of two representative files)
row_src = { ...
    'vary_modulation_freq_fmod_1khz.mat', 'row_vary_modulation_freq_fmod_1khz_row1.f64'; ...
    'FM_fmod70_fc1600hz_fdev800_SPL40-80.mat', 'row_fm_fmod70_fc1600hz_fdev800_row1.f64'};
for k = 1:size(row_src, 1)
    S = load(fullfile(vsq, 'Roughness_Daniel1997', row_src{k, 1}));
    vn = first_field_(S);
    if isfield(S, 'fs'), fs_used = S.fs; else, fs_used = 48000; end
    writer_f64(c, sprintf('%s/%s', d, row_src{k, 2}), S.(vn)(1, :).', ...
        struct('unit', 'Pa', 'description', sprintf('%s row 1, fs %d Hz', row_src{k, 1}, fs_used)));
end
% reference curves of the validation scripts
refv = fullfile(val_base, 'Roughness_Daniel1997', '1_AM_modulation_freq', 'reference_values');
fmats = {'fmod_125hz', 'fmod_250hz', 'fmod_500hz', 'fmod_1khz', 'fmod_2khz', 'fmod_4khz', 'fmod_8khz'};
for k = 1:numel(fmats)
    S = load(fullfile(refv, [fmats{k} '.mat']));
    writer_json(c, sprintf('validation/roughness_ecma418_2/%s.json', fmats{k}), ...
        struct('source', sprintf('validation/Roughness_Daniel1997/1_AM_modulation_freq/reference_values/%s.mat (identical blob reused by the ECMA script)', fmats{k}), ...
        'variable', string(first_field_(S)), ...
        'reference_roughness_asper', S.(first_field_(S))));
end
S = load(fullfile(val_base, 'Roughness_Daniel1997', '3_FM_modulation_depth', 'reference_values', 'REF_FM_fmod.mat'));
writer_json(c, sprintf('%s/ref_fm_fmod.json', d), mat_to_jsonable_(S));
S = load(fullfile(val_base, 'Roughness_Daniel1997', '4_FM_level', 'reference_values', 'REF_FM_level.mat'));
writer_json(c, sprintf('%s/ref_fm_level.json', d), mat_to_jsonable_(S));
end

function val_ecma_(c, val_base)
% .asc subset: combined/total curves per metric (spec 6)
asc_sets = { ...
    fullfile(val_base, 'Roughness_ECMA418_2', '2_roughness_software_comparison', 'reference_results'), ...
    'validation/roughness_ecma418_2', { ...
    'TrainStation7-0100-0130.Roughness (Hearing Model) vs. Time.asc', 'asc_roughness_vs_time.asc'; ...
    'TrainStation7-0100-0130.Roughness (Hearing Model) vs. Time_combined_binaural.asc', 'asc_roughness_vs_time_combined_binaural.asc'; ...
    'TrainStation7-0100-0130.Specific Roughness (Hearing Model).asc', 'asc_specific_roughness.asc'; ...
    'TrainStation7-0100-0130.Specific Roughness (Hearing Model)_combined_binaural.asc', 'asc_specific_roughness_combined_binaural.asc'}; ...
    fullfile(val_base, 'Loudness_ECMA418_2', '2_loudness_software_comparison', 'reference_results'), ...
    'validation/loudness_ecma418_2', { ...
    'TrainStation7-0100-0130.Loudness (Hearing Model) vs. Time.asc', 'asc_loudness_vs_time.asc'; ...
    'TrainStation7-0100-0130.Loudness (Hearing Model) vs. Time_combined_binaural.asc', 'asc_loudness_vs_time_combined_binaural.asc'; ...
    'TrainStation7-0100-0130.Specific Loudness (Hearing Model).asc', 'asc_specific_loudness.asc'; ...
    'TrainStation7-0100-0130.Specific Loudness (Hearing Model)_combined_binaural.asc', 'asc_specific_loudness_combined_binaural.asc'}; ...
    fullfile(val_base, 'Tonality_ECMA418_2', '2_tonality_software_comparison', 'reference_results'), ...
    'validation/tonality_ecma418_2', { ...
    'TrainStation7-0100-0130.Tonality (Hearing Model) vs. Time.asc', 'asc_tonality_vs_time.asc'; ...
    'TrainStation7-0100-0130.Specific Tonality (Hearing Model).asc', 'asc_specific_tonality.asc'}};
for s = 1:3
    base_dir = asc_sets{s, 1};
    dst = asc_sets{s, 2};
    map = asc_sets{s, 3};
    for k = 1:size(map, 1)
        src = fullfile(base_dir, map{k, 1});
        if ~isfile(src)
            % directory names may differ slightly; locate by suffix
            hits = dir(fullfile(val_base, '**', map{k, 1}));
            if isempty(hits)
                error('export_goldens:asc', 'asc not found: %s', map{k, 1});
            end
            src = fullfile(hits(1).folder, hits(1).name);
        end
        writer_copy(c, string(src), sprintf('%s/%s', dst, map{k, 2}));
    end
end

% equal-loudness contour vector
src = fullfile(val_base, 'Loudness_ECMA418_2', '1_equal_loudness_level_contours', ...
    'figs', 'spl_ecma_vec.mat');
S = load(src);
writer_json(c, 'validation/loudness_ecma418_2/contours.json', mat_to_jsonable_(S));
end

function val_slm_(c, val_base)
% IEC 61672-1 tables are inline in the 4 validation scripts; extract by
% evaluating the table block (hard fail if the expected vars are missing)
d = 'validation/sound_level_meter';
slm = fullfile(val_base, 'sound_level_meter');
scripts = { ...
    'validation_Do_SLM_frequency_weightings.m', 'frequency_weightings', ...
    {'f_nominal', 'n_index', 'f_exact', 'designGoal', 'class1_upper', 'class1_lower', 'class2_upper', 'class2_lower'}; ...
    'validation_Do_SLM_toneburst_response.m', 'toneburst_response', ...
    {'Tb', 'ref', 'class1_upper', 'class1_lower', 'class2_upper', 'class2_lower'}; ...
    'validation_Do_SLM_repeated_tonebursts.m', 'repeated_tonebursts', ...
    {'Tb_table_ms', 'class1_upper', 'class1_lower', 'class2_upper', 'class2_lower'}; ...
    'validation_Do_SLM_time_weighting.m', 'time_weighting', ...
    {'tol'}};
out = struct();
for k = 1:size(scripts, 1)
    out.(scripts{k, 2}) = extract_inline_tables_( ...
        fullfile(slm, scripts{k, 1}), scripts{k, 3});
end
writer_json(c, sprintf('%s/iec61672_targets.json', d), out);
end

function val_epnl_(c, val_base)
d = 'validation/epnl_far_part36';
% NOY formulating table (loaded exactly like get_PNL.m does)
src = fullfile(c.sqat_root, 'psychoacoustic_metrics', 'EPNL_FAR_Part36', ...
    'helper', 'NOY_FORMULATING_TABLE.m');
T = load(src);
if isstruct(T)
    T = T.NOY_FORMULATING_TABLE;
end
writer_json(c, sprintf('%s/noy_table.json', d), struct( ...
    'source', 'psychoacoustic_metrics/EPNL_FAR_Part36/helper/NOY_FORMULATING_TABLE.m', ...
    'columns', {'band', 'freq', 'SPLa', 'SPLb', 'SPLc', 'SPLd', 'SPLe', 'Mb', 'Mc', 'Md', 'Me'}, ...
    'rows', T));
% tone correction reference values (validation private dir)
hits = dir(fullfile(val_base, 'EPNL_FAR_Part36', '**', 'TONE_CORRECTION_TABLE_REF_VALUES.m'));
if isempty(hits)
    error('export_goldens:epnl', 'TONE_CORRECTION_TABLE_REF_VALUES.m not found under validation/EPNL_FAR_Part36');
end
T2 = load(fullfile(hits(1).folder, hits(1).name));
if isstruct(T2)
    T2 = mat_to_jsonable_(T2);
end
writer_json(c, sprintf('%s/tone_correction_ref.json', d), struct( ...
    'source', 'validation/EPNL_FAR_Part36/.../TONE_CORRECTION_TABLE_REF_VALUES.m', ...
    'data', T2));
end

% ---- validation helpers --------------------------------------------------

function J = cells_to_jsonable_(C)
J = cell(size(C));
for i = 1:numel(C)
    v = C{i};
    if isnumeric(v) || islogical(v)
        J{i} = v;
    elseif ischar(v)
        J{i} = string(v);
    elseif isstring(v)
        J{i} = v;
    elseif isa(v, 'missing')
        J{i} = "";
    elseif iscell(v)
        J{i} = cells_to_jsonable_(v);
    else
        J{i} = "";
    end
end
end

function J = mat_to_jsonable_(S)
J = struct();
fn = fieldnames(S);
for i = 1:numel(fn)
    v = S.(fn{i});
    if isnumeric(v)
        if isvector(v) || isscalar(v)
            J.(fn{i}) = v(:).';
        else
            J.(fn{i}) = struct('shape', size(v), 'data', reshape(v, 1, []));
        end
    elseif ischar(v)
        J.(fn{i}) = string(v);
    elseif isstruct(v)
        J.(fn{i}) = mat_to_jsonable_(v);
    else
        J.(fn{i}) = v;
    end
end
end

function f = matlab_field_(s)
f = matlab.lang.makeValidName(char(s));
f = f(1:min(numel(f), 60));
end

function f = first_field_(S)
f = fieldnames(S);
f = f{1};
end

function T = extract_inline_tables_(script_path, expected_vars)
% targeted extraction: for each expected table variable, find its literal
% assignment in the script (multi-line bracket groups) and eval ONLY that
% fragment. Pure literals make this safe; anything else fails loudly.
txt = fileread(script_path);
lines = regexp(txt, '\r?\n', 'split');
T = struct();
for vi = 1:numel(expected_vars)
    name = expected_vars{vi};
    pat = ['^\s*' name '(\.\w+)?\s*='];
    hit_start = 0;
    for i = 1:numel(lines)
        code = code_part_(lines{i});
        if ~isempty(regexp(code, pat, 'once'))
            hit_start = i;
            break;
        end
    end
    if hit_start == 0
        continue;
    end
    depth = 0;
    frag = {};
    done = false;
    for i = hit_start:hit_start+200
        code = code_part_(lines{i});
        frag{end+1} = code; %#ok<AGROW>
        opens = numel(regexp(code, '[(\[{]', 'match'));
        closes = numel(regexp(code, '[)\]}]', 'match'));
        depth = depth + opens - closes;
        cont = ~isempty(code) && numel(code) >= 3 && strcmp(code(end-2:end), '...');
        if depth <= 0 && ~cont && ~isempty(code) && code(end) == ';'
            done = true;
            break;
        end
        if depth <= 0 && ~cont && ~isempty(code) && code(end) ~= ';'
            break;
        end
    end
    if ~done
        error('export_goldens:slm_extract', ...
            '%s: could not bracket-scan variable %s', leaf_name_(script_path), name);
    end
    flat = regexprep(strjoin(frag, newline), '\.\.\.(\s*\r?\n)+', ' ');
    try
        eval(flat);           % bare eval: the fragment IS an assignment
        v = eval(name);       % read the base variable back
    catch err
        error('export_goldens:slm_extract', ...
            '%s: variable %s fragment failed to eval: %s', ...
            leaf_name_(script_path), name, err.message);
    end
    tok = regexp(strtrim(code_part_(lines{hit_start})), ...
        ['^' name '(\.\w+)'], 'tokens', 'once');
    if isempty(tok) || isempty(tok{1})
        T.(name) = v;
    else
        if ~isfield(T, name) || ~isstruct(T.(name))
            T.(name) = struct();
        end
        T.(name).(tok{1}(2:end)) = v;
    end
end
missing = expected_vars(~ismember(expected_vars, fieldnames(T)));
if ~isempty(missing)
    error('export_goldens:slm_extract', ...
        '%s: expected table vars not found: %s', ...
        leaf_name_(script_path), strjoin(missing, ', '));
end
T = jsonable_(T);
end

function code = code_part_(line)
code = strtrim(line);
m2 = regexp(code, '%', 'split', 'once');
if iscell(m2)
    code = strtrim(m2{1});
end
end

function T = eval_block_(src)
% eval a self-contained table block and snapshot scalar/vector/matrix/struct vars
eval(src);
W = whos;
T = struct();
for i = 1:numel(W)
    if any(strcmp(W(i).name, {'T', 'src', 'W'}))
        continue;
    end
    v = eval(W(i).name);
    if isnumeric(v) || ischar(v) || islogical(v) || isstring(v) || isstruct(v) || iscell(v)
        T.(W(i).name) = v;
    end
end
end

% ========================================================================
% Section: level3/loudness_iso532_1 (spec 5.1)
% =========================================================================

function sec_level3_loudness_iso(c)
mfile = 'psychoacoustic_metrics/Loudness_ISO532_1/Loudness_ISO532_1.m';
if ~should_run(c, 'level3/loudness_iso532_1'), return; end
instrument(c, mfile, loudness_probes_(), 'loudness_iso');
cleanup = onCleanup(@() instrument_clear());
try
    tol = 'N stat abs 0.01 sone; N inst abs 0.05 sone or 1 pct rel; LN abs 0.1 phon; SPL abs 0.1 dB';
    % method 0: the 28-band vector of ISO 532-1:2017 Annex B.2 signal 1,
    % extracted from the validation script's inline table
    lv28 = loudness_m0_vector_(c);
    run_metric_case(c, mkcase_('loudness_iso532_1', 'm0_levels28_annexb2', mfile, ...
        struct('method', 0, 'fs', 0, 'field', 0, 'time_skip', 0, ...
        'input', 'ISO 532-1:2017 Annex B.2 signal 1, 28 third-octave levels 25 Hz..12.5 kHz'), ...
        tol, false, false, "", ...
        @(x) Loudness_ISO532_1(x, 0, 0, 0, 0, false), ...
        loudness_plan_('m0'), lv28));
    writer_f64(c, 'level3/loudness_iso532_1/m0_levels28_annexb2/input.f64', lv28, ...
        struct('unit', 'dB', 'description', '28 third-octave band levels (Annex B.2 signal 1)'));

    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('loudness_iso532_1', 'm1_stat01_1khz_60db', mfile, ...
        struct('method', 1, 'fs', 48000, 'field', 0, 'time_skip', 0), tol, ...
        false, false, "", @(xx) Loudness_ISO532_1(xx, 48000, 0, 1, 0, false), ...
        loudness_plan_('m1'), x));
    writer_f64(c, 'level3/loudness_iso532_1/m1_stat01_1khz_60db/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 60 dB SPL, 1 s'));

    % method 2 anchor: TrainStation 10 s channel 1 (input_ref dedup)
    x_anchor = ts10_(c, 1);
    plan_m2 = loudness_plan_('m2');
    ref = struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', 1);
    run_metric_case(c, mkcase_('loudness_iso532_1', 'm2_anchor01_trainstation10s_ch1', mfile, ...
        struct('method', 2, 'fs', 48000, 'field', 0, 'time_skip', 0), tol, ...
        true, false, "", @(xx) Loudness_ISO532_1(xx, 48000, 0, 2, 0, false), ...
        plan_m2, x_anchor, ref));

    x = synth_tone(48000, 0.5, 1000, 60);
    run_metric_case(c, mkcase_('loudness_iso532_1', 'm2_short01_1khz_60db_05s', mfile, ...
        struct('method', 2, 'fs', 48000, 'field', 0, 'time_skip', 0), tol, ...
        false, false, "", @(xx) Loudness_ISO532_1(xx, 48000, 0, 2, 0, false), ...
        loudness_plan_('m2'), x));
    writer_f64(c, 'level3/loudness_iso532_1/m2_short01_1khz_60db_05s/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 60 dB SPL, 0.5 s'));

    run_metric_case(c, mkcase_('loudness_iso532_1', 'm2_diff01_trainstation10s_ch1', mfile, ...
        struct('method', 2, 'fs', 48000, 'field', 1, 'time_skip', 0), tol, ...
        false, false, "", @(xx) Loudness_ISO532_1(xx, 48000, 1, 2, 0, false), ...
        loudness_plan_('m2'), ts10_(c, 1), ref));

    % diffuse field in the stationary paths (added 2026-10-07: no golden had field 1
    % outside method 2)
    run_metric_case(c, mkcase_('loudness_iso532_1', 'm0_diff01_levels28_annexb2', mfile, ...
        struct('method', 0, 'fs', 0, 'field', 1, 'time_skip', 0, ...
        'input', 'ISO 532-1:2017 Annex B.2 signal 1, 28 third-octave levels 25 Hz..12.5 kHz'), ...
        tol, false, false, "", ...
        @(x) Loudness_ISO532_1(x, 0, 1, 0, 0, false), ...
        loudness_plan_('m0'), lv28));
    writer_f64(c, 'level3/loudness_iso532_1/m0_diff01_levels28_annexb2/input.f64', lv28, ...
        struct('unit', 'dB', 'description', '28 third-octave band levels (Annex B.2 signal 1)'));

    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('loudness_iso532_1', 'm1_diff01_1khz_60db', mfile, ...
        struct('method', 1, 'fs', 48000, 'field', 1, 'time_skip', 0), tol, ...
        false, false, "", @(xx) Loudness_ISO532_1(xx, 48000, 1, 1, 0, false), ...
        loudness_plan_('m1'), x));
    writer_f64(c, 'level3/loudness_iso532_1/m1_diff01_1khz_60db/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 60 dB SPL, 1 s, diffuse field'));
catch err
    clear cleanup
    rethrow(err);
end
end

function cfg = mkcase_(metric, name, mfile, params, tol, anchor, warn_case, wid, fcn, plan, x, input_ref)
cfg = struct();
cfg.metric = metric;
cfg.name = name;
cfg.m_file = mfile;
cfg.params = params;
cfg.tol = tol;
cfg.anchor = anchor;
cfg.warn_case = warn_case;
cfg.expect_warn_id = wid;
cfg.make_fcn = @(varargin) fcn(x);
cfg.input_rel = '';
cfg.probe_plan = plan;
if exist('input_ref', 'var')
    cfg.input_ref = input_ref;
end
end

function probes = loudness_probes_()
% anchors verified unique at baseline 4a99198 (recon 2026-09-22)
probes = struct('anchor', {}, 'code', {});
probes(end+1) = struct('anchor', '        len = size(insig,1);', ...
    'code', {'export_probe(''p1'', struct(''insig'', insig, ''fs'', fs));'});
probes(end+1) = struct('anchor', '        [filteredaudio,fc] = Do_OB13_ISO532_1(insig,fs);', ...
    'code', {'export_probe(''p2'', struct(''filteredaudio'', filteredaudio, ''fc'', fc));'});
probes(end+1) = struct('anchor', ...
    '    % STEP 4 - Apply weighting factor to the first three 1/3 octave bands', ...
    'code', {'export_probe(''p3'', struct(''ThirdOctaveLevel'', ThirdOctaveLevel));'});
probes(end+1) = struct('anchor', '    FNGi = 10*log10(CBI);', ...
    'code', {'export_probe(''p4'', struct(''CorrLevel'', CorrLevel, ''Intens'', Intens));'});
probes(end+1) = struct('anchor', '    LCB(CBI > 0) = FNGi(CBI > 0);', ...
    'code', {'export_probe(''p5'', struct(''CBI'', CBI, ''LCB'', LCB));'});
probes(end+1) = struct('anchor', ...
    '% STEP 7 - Correction of specific loudness within the lowest critical band', ...
    'code', {'export_probe(''p6'', struct(''Le'', Le));'});
probes(end+1) = struct('anchor', '% STEP 8 - Implementation of NL Block', ...
    'code', {'export_probe(''p7'', struct(''CoreL'', CoreL));'});
probes(end+1) = struct('anchor', '% STEP 9 - CALCULATE THE SLOPES', ...
    'code', {'export_probe(''p8'', struct(''CoreL'', CoreL));'});
probes(end+1) = struct('anchor', ...
    '% Specific loudness as a function of Bark number. Only defined for the', ...
    'code', {'export_probe(''p9'', struct(''ns'', ns, ''N_mat'', N_mat));'});
probes(end+1) = struct('anchor', '    ns_dec = zeros(NumSamplesLoudness,240);', ...
    'code', {'export_probe(''p10'', struct(''Total_Loudness'', Total_Loudness, ''Loudness_t1'', Loudness_t1, ''Loudness_t2'', Loudness_t2));'});
end

function plan = loudness_plan_(which)
M = 'psychoacoustic_metrics/Loudness_ISO532_1/Loudness_ISO532_1.m';
p3 = plan1('p3', {pf(1, 'ThirdOctaveLevel', 'probe_p3_third_octave_level.f64', 'dB', ...
    'ThirdOctaveLevel after band loop (STEP 3 end)', M, 'STEP 3')}, struct());
p4 = plan1('p4', {pf(1, 'CorrLevel', 'probe_p4_corr.f64', 'dB', ...
    'CorrLevel RAP/DLL weighting (STEP 4)', M, 'STEP 4'), ...
    pf(1, 'Intens', 'probe_p4_intens.f64', '', 'Intens (STEP 4)', M, 'STEP 4')}, struct());
p5 = plan1('p5', {pf(1, 'CBI', 'probe_p5_cbi.f64', '', 'CBI first 3 critical bands (STEP 5)', M, 'STEP 5'), ...
    pf(1, 'LCB', 'probe_p5_lcb.f64', '', 'LCB first 3 critical bands (STEP 5)', M, 'STEP 5')}, struct());
p6 = plan1('p6', {pf(1, 'Le', 'probe_p6_le.f64', '', 'Le 20 bands post A0/DDF (STEP 6)', M, 'STEP 6')}, struct());
p7 = plan1('p7', {pf(1, 'CoreL', 'probe_p7_corel.f64', '', 'CoreL post lowest-band correction (STEP 7)', M, 'STEP 7')}, struct());
p8 = plan1('p8', {pf(1, 'CoreL', 'probe_p8_corel_nl.f64', '', 'CoreL post NL block, NL_ITER=24 (STEP 8)', M, 'STEP 8')}, struct());
p9 = plan1('p9', {pf(1, 'ns', 'probe_p9_ns.f64', 'sone/Bark', 'ns 240 columns pre-integration (STEP 9)', M, 'STEP 9'), ...
    pf(1, 'N_mat', 'probe_p9_nmat.f64', 'sone', 'N_mat total per sample (STEP 9)', M, 'STEP 9')}, struct());
p10 = plan1('p10', {pf(1, 'Total_Loudness', 'probe_p10_total_loudness.f64', 'sone', ...
    'Total_Loudness post decimation to 500 Hz (STEP 10)', M, 'STEP 10'), ...
    pf(1, 'Loudness_t1', 'probe_p10_loudness_t1.f64', 'sone', 'Loudness_t1 3.5 ms (STEP 10)', M, 'STEP 10'), ...
    pf(1, 'Loudness_t2', 'probe_p10_loudness_t2.f64', 'sone', 'Loudness_t2 70 ms (STEP 10)', M, 'STEP 10')}, struct());
switch which
    case 'm0'
        plan = [p3, p4, p5, p6, p7, p8, p9];
    case 'm1'
        plan = [plan1('p1', {pf(1, 'insig', 'probe_p1_insig48k.f64', 'Pa', ...
            'signal post-resample 48 kHz (STEP 1)', M, 'STEP 1'), ...
            pf(1, 'fs', 'probe_p1_fs.f64', 'Hz', 'fs at pipeline (STEP 1)', M, 'STEP 1')}, struct()), ...
            plan1('p2', {pf(1, 'filteredaudio', 'probe_p2_ob13_filtered.f64', 'Pa', ...
            'Do_OB13 filteredaudio (STEP 2)', M, 'STEP 2'), ...
            pf(1, 'fc', 'probe_p2_fc.f64', 'Hz', 'Do_OB13 fc 28 bands (STEP 2)', M, 'STEP 2')}, struct()), ...
            p3, p4, p5, p6, p7, p8, p9];
    otherwise  % m2
        plan = [plan1('p1', {pf(1, 'insig', 'probe_p1_insig48k.f64', 'Pa', ...
            'signal post-resample 48 kHz (STEP 1)', M, 'STEP 1'), ...
            pf(1, 'fs', 'probe_p1_fs.f64', 'Hz', 'fs at pipeline (STEP 1)', M, 'STEP 1')}, ...
            struct('longdec', 100)), ...
            plan1('p2', {pf(1, 'filteredaudio', 'probe_p2_ob13_filtered.f64', 'Pa', ...
            'Do_OB13 filteredaudio (STEP 2)', M, 'STEP 2'), ...
            pf(1, 'fc', 'probe_p2_fc.f64', 'Hz', 'Do_OB13 fc 28 bands (STEP 2)', M, 'STEP 2')}, ...
            struct('longdec', 100)), p3, p4, p5, p6, p7, p8, p9, p10];
end
end

function v = loudness_m0_vector_(c)
src = fullfile(c.sqat_root, 'validation', 'Loudness_ISO532_1', ...
    '1_synthetic_signals_stationary_loudness', ...
    'validation_stationary_loudness_synthetic_signals.m');
txt = fileread(src);
lines = regexp(txt, '\r?\n', 'split');
stop_pat = 'Loudness_ISO532_1|figure|plot\(|audioread';
block = {};
started = false;
for i = 1:numel(lines)
    L = strtrim(lines{i});
    if ~started
        if isempty(L) || startsWith(L, '%'), continue; end
        started = true;
    end
    cp = regexp(L, '%', 'split', 'once');
    cp = strtrim(cp{1});
    if ~isempty(regexpi(cp, stop_pat, 'once')), break; end
    if ~isempty(L) && ~startsWith(L, '%')
        if isempty(regexpi(cp, '^\s*(clc|clear|close|for|while|if|switch|end|else|elseif|try|catch|return|break|continue|function)')) && ~isempty(cp)
            block{end+1} = cp; %#ok<AGROW>
        end
    end
end
T = eval_block_(regexprep(strjoin(block, newline), '\.\.\.(\s*\r?\n)+', ' '));
fn = fieldnames(T);
v = [];
for i = 1:numel(fn)
    x = T.(fn{i});
    cand = {};
    if isnumeric(x)
        cand = {x};
    elseif iscell(x)
        cand = x(:);
    end
    for j = 1:numel(cand)
        y = cand{j};
        if isnumeric(y) && (isequal(size(y), [1 28]) || isequal(size(y), [28 1]))
            v = y(:).';
            break;
        end
    end
    if ~isempty(v)
        break;
    end
end
if isempty(v)
    error('export_goldens:m0vector', ...
        'Annex B.2 28-level vector not found in validation script 1');
end
end

function x = ts10_(c, chan)
src = fullfile(c.sqat_root, 'sound_files', 'reference_signals', ...
    'ExStereo_TrainStation7-0100-0130.wav');
[x, fs] = audioread(src);
if fs ~= 48000
    error('export_goldens:fs', 'TrainStation expected 48 kHz, got %d', fs);
end
x = double(x(1:10*fs, chan));
end

% ========================================================================
% Section: level3/tonality_aures1985 (spec 5.2)
% =========================================================================

function sec_level3_aures(c)
mfile = 'psychoacoustic_metrics/Tonality_Aures1985/Tonality_Aures1985.m';
if ~should_run(c, 'level3/tonality_aures1985'), return; end
instrument(c, mfile, aures_probes_(), 'aures');
cleanup = onCleanup(@() instrument_clear());
try
    tol = 'K abs 0.01 t.u.';
    ref = struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', 1);

    run_metric_case(c, mkcase_('tonality_aures1985', 'anchor01_trainstation10s_ch1', mfile, ...
        struct('fs', 48000, 'LoudnessField', 0, 'time_skip', 0.05), tol, ...
        true, false, "", @(x) Tonality_Aures1985(x, 48000, 0, 0.05, false), ...
        aures_plan_(true), ts10_(c, 1), ref));

    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('tonality_aures1985', 'tone01_1khz_60db_48k', mfile, ...
        struct('fs', 48000, 'LoudnessField', 0, 'time_skip', 0.05), tol, ...
        false, false, "", @(xx) Tonality_Aures1985(xx, 48000, 0, 0.05, false), ...
        aures_plan_(false), x));
    writer_f64(c, 'level3/tonality_aures1985/tone01_1khz_60db_48k/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 60 dB SPL, 1 s, 48 kHz native'));

    x = synth_pink(44100, 1, 60, 42);
    run_metric_case(c, mkcase_('tonality_aures1985', 'noise01_pink_60db_44k1', mfile, ...
        struct('fs', 44100, 'LoudnessField', 0, 'time_skip', 0.05), tol, ...
        false, false, "", @(xx) Tonality_Aures1985(xx, 44100, 0, 0.05, false), ...
        aures_plan_(false), x));
    writer_f64(c, 'level3/tonality_aures1985/noise01_pink_60db_44k1/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'pink noise 60 dB SPL, 1 s, 44.1 kHz native, rng(42)'));

    try
        rng(42, 'twister');
        nb = synth_noise_band(44100, 1, 1000, 160, 55, 42) + synth_tone(44100, 1, 1000, 65);
        run_metric_case(c, mkcase_('tonality_aures1985', 'nb01_narrowband_plus_tone', mfile, ...
            struct('fs', 44100, 'LoudnessField', 0, 'time_skip', 0.05), tol, ...
            false, false, "", @(xx) Tonality_Aures1985(xx, 44100, 0, 0.05, false), ...
            aures_plan_(false), nb));
        writer_f64(c, 'level3/tonality_aures1985/nb01_narrowband_plus_tone/input.f64', nb, ...
            struct('unit', 'Pa', 'description', '1-Bark noise band fc 1 kHz + 1 kHz tone 65 dB, 44.1 kHz'));
    catch nberr
        dump_section_error('aures_nb01', nberr);
    end

    % diffuse field (added 2026-10-07: every Aures golden had LoudnessField 0)
    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('tonality_aures1985', 'diff01_tone_1khz_60db_48k', mfile, ...
        struct('fs', 48000, 'LoudnessField', 1, 'time_skip', 0.05), tol, ...
        false, false, "", @(xx) Tonality_Aures1985(xx, 48000, 1, 0.05, false), ...
        aures_plan_(false), x));
    writer_f64(c, 'level3/tonality_aures1985/diff01_tone_1khz_60db_48k/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 60 dB SPL, 1 s, 48 kHz, diffuse field'));

    try
        x = synth_tone(44100, 0.1, 1000, 60);
        run_metric_case(c, mkcase_('tonality_aures1985', 'err01_shorter_than_window', mfile, ...
            struct('fs', 44100, 'LoudnessField', 0, 'time_skip', 0.05), tol, ...
            false, true, "", @(xx) Tonality_Aures1985(xx, 44100, 0, 0.05, false), ...
            struct('name', '', 'files', {}, 'nodecimate', false, 'longdec', 0, 'complex', false), x));
        writer_f64(c, 'level3/tonality_aures1985/err01_shorter_than_window/input.f64', x, ...
            struct('unit', 'Pa', 'description', '0.1 s tone: shorter than the 250 ms window -> error'));
    catch ererr
        dump_section_error('aures_err01', ererr);
    end
catch err
    clear cleanup
    rethrow(err);
end
end

function probes = aures_probes_()
g1 = 'if iFrame == 1 || iFrame == ceil(nFrames/2) || iFrame == nFrames; ';
g1e = '; end';
probes = struct('anchor', {}, 'code', {});
probes(end+1) = struct('anchor', 'N=round(fs*time_resolution); % define window length, N bins', ...
    'code', {'export_probe(''a1'', struct(''insig'', insig, ''fs'', fs));'});
probes(end+1) = struct('anchor', 'for iFrame = 1:nFrames', ...
    'code', {'if iFrame == 1; export_probe(''a2'', struct(''frames_dec'', insig(:, 1:10:end), ''shape_full'', size(insig), ''N'', N, ''overlap'', overlap)); end'});
probes(end+1) = struct('anchor', ...
    '    SPLcrop = SPL(MinFrequencyindex:MaxFrequencyIndex); % crop SPL vector from MinFrequencyindex to MaxFrequencyIndex', ...
    'code', {[g1 'export_probe(''a3'', struct(''SPL'', SPL, ''SPLcrop'', SPLcrop))' g1e]});
probes(end+1) = struct('anchor', '        BWnotch = BWnotch(idx);', ...
    'code', {[g1 'export_probe(''a4a'', struct(''ToneF'', ToneF, ''ToneL'', ToneL, ''BW'', BW, ''BWnotch'', BWnotch, ''NTones'', NTones))' g1e]});
probes(end+1) = struct('anchor', 'FreqNoise = FreqSingleSidedinsigSpectrum(:);', ...
    'code', {[g1 'export_probe(''a4b'', struct(''ToneF'', ToneF, ''ToneL'', ToneL, ''BW'', BW, ''Wfoot'', Wfoot))' g1e]});
probes(end+1) = struct('anchor', '    nbL = nbL - 10*log10(ENBW);', ...
    'code', {[g1 'export_probe(''a5'', struct(''nbF'', nbF, ''nbBW'', nbBW, ''nbL'', nbL, ''nbIdx'', nbIdx, ''nbBridge'', nbBridge))' g1e]});
probes(end+1) = struct('anchor', ...
    'filtered_signal=ifft(doubleSideFilteredSpectrum,''symmetric'');  % get filtered signal in time-domain', ...
    'code', {[g1 'export_probe(''a6'', struct(''SPLnoise'', SPLnoise, ''FreqNoise'', FreqNoise, ''filtered_signal'', filtered_signal))' g1e]});
probes(end+1) = struct('anchor', ...
    '            clear y insigSpectrum SingleSidedinsigSpectrum', ...
    'code', {[g1 'export_probe(''a7'', struct(''w_gr_i'', w_gr(iFrame,1), ''L_total'', L_total.Loudness, ''L_filtered'', L_filtered.Loudness))' g1e]});
probes(end+1) = struct('anchor', ...
    '            tone{iFrame,1}.LX=il_SPL_excess(tone{iFrame,1}); %  Sound pressure excess calculation (define aurally relevance of the tones)', ...
    'code', {[g1 'export_probe(''a8'', struct(''Lnoise'', tone{iFrame,1}.Lnoise, ''LX'', tone{iFrame,1}.LX, ''w_tonal_i'', w_tonal(iFrame,1)))' g1e]});
probes(end+1) = struct('anchor', 'w1 = ( 0.13./(dz+0.13) );', ...
    'code', {'export_probe(''a8w1'', struct(''w1'', w1));'});
probes(end+1) = struct('anchor', ...
    'w2 =  ( 1./( sqrt (1+0.2.*(fc./700 + 700./fc).^2) ) ).^(0.29);', ...
    'code', {'export_probe(''a8w2'', struct(''w2'', w2));'});
probes(end+1) = struct('anchor', ...
    '            tonality(iFrame,1) = abs( C.*w_tonal(iFrame,1).^(0.29).*w_gr(iFrame,1).^(0.79) );', ...
    'code', {[g1 'export_probe(''a9'', struct(''tonality_i'', tonality(iFrame,1), ''w_tonal_i'', w_tonal(iFrame,1), ''w_gr_i'', w_gr(iFrame,1), ''C'', C))' g1e]});
probes(end+1) = struct('anchor', ...
    'OUT_statistics = get_statistics( tonality(idx:end), metric_statistics ); % get statistics', ...
    'code', {'export_probe(''a9f'', struct(''tonality'', tonality, ''w_tonal'', w_tonal, ''w_gr'', w_gr, ''idx'', idx));'});
end

function plan = aures_plan_(anchor)
M = 'psychoacoustic_metrics/Tonality_Aures1985/Tonality_Aures1985.m';
if anchor
    parts = [1 2 3];
else
    parts = 1;
end
plan = [ ...
    plan1('a1', {pf(1, 'insig', 'probe_a1_insig.f64', 'Pa', ...
        'signal entering the analysis (post resample-or-native)', M, 'resample'), ...
        pf(1, 'fs', 'probe_a1_fs.f64', 'Hz', 'fs at analysis', M, 'resample')}, ...
        struct('longdec', 100)), ...
    plan1('a2', {pf(1, 'frames_dec', 'probe_a2_frames.f64', 'Pa', ...
        'buffered frames, columns decimated x10 at capture (see case anchor flag)', M, 'buffer'), ...
        pf(1, 'N', 'probe_a2_n.f64', '', 'window length N', M, 'buffer'), ...
        pf(1, 'overlap', 'probe_a2_overlap.f64', '', 'buffer overlap', M, 'buffer')}, ...
        struct('nodecimate', true)), ...
    plan1('a3', [aures_files_(parts, 'SPL', 'probe_a3_spl', 'dB', ...
        'SPL of exemplar frame', M, 'spectra'), ...
        aures_files_(parts, 'SPLcrop', 'probe_a3_splcrop', 'dB', ...
        'SPLcrop 20 Hz..5 kHz of exemplar frame', M, 'spectra')], struct()), ...
    plan1('a4b', [aures_files_(parts, 'ToneF', 'probe_a4_tonef', 'Hz', ...
        'ToneF post-merge exemplar frame', M, 'il_find_sinusoids'), ...
        aures_files_(parts, 'ToneL', 'probe_a4_tonel', 'dB', ...
        'ToneL post-merge exemplar frame', M, 'il_find_sinusoids'), ...
        aures_files_(parts, 'BW', 'probe_a4_bw', 'Hz', ...
        'BW post-merge exemplar frame', M, 'il_find_sinusoids'), ...
        aures_files_(parts, 'Wfoot', 'probe_a4_wfoot', 'Hz', ...
        'Wfoot notch width (separates extraction error from notch error)', M, 'il_find_sinusoids')], struct()), ...
    plan1('a4a', aures_files_(parts, 'BWnotch', 'probe_a4_bwnotch', 'Hz', ...
        'BWnotch pre-merge = max(BW, 4*df)', M, 'il_find_sinusoids'), struct()), ...
    plan1('a5', [aures_files_(parts, 'nbF', 'probe_a5_nbf', 'Hz', ...
        'narrowband frequencies (Aures 2.3.2)', M, 'il_find_narrowband'), ...
        aures_files_(parts, 'nbBW', 'probe_a5_nbbw', 'Hz', ...
        'narrowband bandwidths', M, 'il_find_narrowband'), ...
        aures_files_(parts, 'nbL', 'probe_a5_nbl', 'dB', ...
        'narrowband levels post-ENBW', M, 'il_find_narrowband'), ...
        aures_files_(parts, 'nbBridge', 'probe_a5_nbbridge', '', ...
        'narrowband bridge flags', M, 'il_find_narrowband')], struct()), ...
    plan1('a6', [aures_files_(parts, 'SPLnoise', 'probe_a6_splnoise', 'dB', ...
        'notched noise spectrum', M, 'notch'), ...
        aures_files_(parts, 'filtered_signal', 'probe_a6_filtered', 'Pa', ...
        'filtered signal (ifft symmetric)', M, 'notch')], struct()), ...
    plan1('a8w1', aures_files_(parts, 'w1', 'probe_a8_w1', '', ...
        'w1 inside il_tonal_weighting (call order = frame order)', M, 'il_tonal_weighting'), struct()), ...
    plan1('a8w2', aures_files_(parts, 'w2', 'probe_a8_w2', '', ...
        'w2 inside il_tonal_weighting (call order = frame order)', M, 'il_tonal_weighting'), struct()), ...
    plan1('a7', {pf(1, 'L_total', 'probe_a7_ltotal.f64', 'sone', ...
        'L_total.Loudness frame 1', M, 'loudness'), ...
        pf(1, 'L_filtered', 'probe_a7_lfiltered.f64', 'sone', ...
        'L_filtered.Loudness frame 1', M, 'loudness'), ...
        pf(1, 'w_gr_i', 'probe_a7_wgr.f64', '', 'w_gr frame 1', M, 'loudness')}, struct()), ...
    plan1('a8', {pf(1, 'Lnoise', 'probe_a8_lnoise.f64', 'dB', ...
        'tone Lnoise frame 1', M, 'il_SPL_excess'), ...
        pf(1, 'LX', 'probe_a8_lx.f64', 'dB', 'tone LX frame 1', M, 'il_SPL_excess')}, struct()), ...
    plan1('a9', {pf(1, 'tonality_i', 'probe_a9_tonality_frame1.f64', 't.u.', ...
        'per-frame tonality frame 1', M, 'final'), ...
        pf(1, 'C', 'probe_a9_c.f64', '', 'Aures calibration constant', M, 'final')}, struct()), ...
    plan1('a9f', {pf(1, 'tonality', 'probe_a9_tonality_series.f64', 't.u.', ...
        'tonality full series', M, 'final'), ...
        pf(1, 'w_tonal', 'probe_a9_wtonal_series.f64', '', 'w_tonal full series', M, 'final'), ...
        pf(1, 'w_gr', 'probe_a9_wgr_series.f64', '', 'w_gr full series', M, 'final'), ...
        pf(1, 'idx', 'probe_a9_idx.f64', '', 'stats start index', M, 'final')}, struct())];
end

function fl = aures_files_(parts, fieldname, base, unit, desc, mfile, stage)
fl = cell(numel(parts), 1);
for i = 1:numel(parts)
    fl{i} = pf(parts(i), fieldname, sprintf('%s_frame%02d.f64', base, parts(i)), ...
        unit, desc, mfile, stage);
end
end

% ========================================================================
% Section: level3 ECMA-418-2 trio (spec 5.3)
% =========================================================================

function sec_level3_ecma(c)
if ~should_run(c, 'level3/ecma') && ~should_run(c, 'tonality_ecma418_2') && ...
        ~should_run(c, 'loudness_ecma418_2') && ~should_run(c, 'roughness_ecma418_2')
    return;
end
mT = 'psychoacoustic_metrics/Tonality_ECMA418_2/Tonality_ECMA418_2.m';
mL = 'psychoacoustic_metrics/Loudness_ECMA418_2/Loudness_ECMA418_2.m';
mR = 'psychoacoustic_metrics/Roughness_ECMA418_2/Roughness_ECMA418_2.m';

instrument(c, mT, ecma_ton_probes_(), 'ecma_ton');
instrument(c, mL, ecma_ldn_probes_(), 'ecma_ldn');
instrument(c, mR, ecma_rgh_probes_(), 'ecma_rgh');
cleanup = onCleanup(@() instrument_clear());

try
    % ---- Tonality ECMA -------------------------------------------------
    tolT = 'T abs 0.01 tu_HMS';
    run_metric_case(c, mkcase_('tonality_ecma418_2', 'anchor01_ts10s_ch1_free', mT, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.304), ...
        tolT, true, false, "", ...
        @(x) Tonality_ECMA418_2(x, 48000, "free-frontal", 0.304, false), ...
        ecma_ton_plan_([1 2 3]), ts10_(c, 1), ...
        struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', 1)));

    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('tonality_ecma418_2', 'tone01_1khz_60db', mT, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.304), ...
        tolT, false, false, "", ...
        @(xx) Tonality_ECMA418_2(xx, 48000, "free-frontal", 0.304, false), ...
        ecma_ton_plan_(1), x));
    writer_f64(c, 'level3/tonality_ecma418_2/tone01_1khz_60db/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 60 dB SPL, 1 s, 48 kHz'));

    x = synth_pink(48000, 1, 60, 42);
    run_metric_case(c, mkcase_('tonality_ecma418_2', 'pink01_short', mT, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.304), ...
        tolT, false, false, "", ...
        @(xx) Tonality_ECMA418_2(xx, 48000, "free-frontal", 0.304, false), ...
        ecma_ton_plan_(1), x));
    writer_f64(c, 'level3/tonality_ecma418_2/pink01_short/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'pink noise 60 dB SPL, 1 s, 48 kHz, rng(42)'));

    run_metric_case(c, mkcase_('tonality_ecma418_2', 'diffuse01_ts10s_ch1', mT, ...
        struct('fs', 48000, 'fieldtype', 'diffuse', 'time_skip', 0.304), ...
        tolT, false, false, "", ...
        @(x) Tonality_ECMA418_2(x, 48000, "diffuse", 0.304, false), ...
        ecma_ton_plan_(1), ts10_(c, 1), ...
        struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', 1)));

    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('tonality_ecma418_2', 'tskip01_tone_100ms', mT, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.1), ...
        tolT, false, true, "", ...
        @(xx) Tonality_ECMA418_2(xx, 48000, "free-frontal", 0.1, false), ...
        ecma_ton_plan_(1), x));
    writer_f64(c, 'level3/tonality_ecma418_2/tskip01_tone_100ms/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'time_skip warning case: 0.1 s < 304 ms threshold'));

    ecma_asc30s_(c, 'tonality_ecma418_2', mT, @Tonality30_, tolT);

    % ---- Loudness ECMA ---------------------------------------------------
    tolL = 'N abs 0.02 sone_HMS (spec N'' 0.02 sone_HMS/Bark)';
    run_metric_case(c, mkcase_('loudness_ecma418_2', 'anchor01_ts10s_ch1_free', mL, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.304), ...
        tolL, true, false, "", ...
        @(x) Loudness_ECMA418_2(x, 48000, "free-frontal", 0.304, false), ...
        ecma_ldn_plan_([1 2 3], false), ts10_(c, 1), ...
        struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', 1)));

    run_metric_case(c, mkcase_('loudness_ecma418_2', 'stereo01_ts10s', mL, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.304, ...
        'channels', 'stereo+binaural'), ...
        tolL, false, false, "", ...
        @(x) Loudness_ECMA418_2(x, 48000, "free-frontal", 0.304, false), ...
        ecma_ldn_plan_(1, true), ts10_(c, [1 2]), ...
        struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', [1 2])));

    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('loudness_ecma418_2', 'tone01_1khz_60db', mL, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.304), ...
        tolL, false, false, "", ...
        @(xx) Loudness_ECMA418_2(xx, 48000, "free-frontal", 0.304, false), ...
        ecma_ldn_plan_(1, false), x));
    writer_f64(c, 'level3/loudness_ecma418_2/tone01_1khz_60db/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 60 dB SPL, 1 s, 48 kHz'));

    x = synth_pink(48000, 1, 60, 42);
    run_metric_case(c, mkcase_('loudness_ecma418_2', 'pink01_short', mL, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.304), ...
        tolL, false, false, "", ...
        @(xx) Loudness_ECMA418_2(xx, 48000, "free-frontal", 0.304, false), ...
        ecma_ldn_plan_(1, false), x));
    writer_f64(c, 'level3/loudness_ecma418_2/pink01_short/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'pink noise 60 dB SPL, 1 s, 48 kHz, rng(42)'));

    run_metric_case(c, mkcase_('loudness_ecma418_2', 'diffuse01_ts10s_ch1', mL, ...
        struct('fs', 48000, 'fieldtype', 'diffuse', 'time_skip', 0.304), ...
        tolL, false, false, "", ...
        @(x) Loudness_ECMA418_2(x, 48000, "diffuse", 0.304, false), ...
        ecma_ldn_plan_(1, false), ts10_(c, 1), ...
        struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', 1)));

    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('loudness_ecma418_2', 'tskip01_tone_100ms', mL, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.1), ...
        tolL, false, true, "", ...
        @(xx) Loudness_ECMA418_2(xx, 48000, "free-frontal", 0.1, false), ...
        ecma_ldn_plan_(1, false), x));
    writer_f64(c, 'level3/loudness_ecma418_2/tskip01_tone_100ms/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'time_skip warning case: 0.1 s < 304 ms threshold'));

    ecma_asc30s_(c, 'loudness_ecma418_2', mL, @Loudness30_, tolL);

    % ---- Roughness ECMA ----------------------------------------------------
    tolR = 'R abs 0.005 asper_HMS';
    run_metric_case(c, mkcase_('roughness_ecma418_2', 'anchor01_ts10s_ch1_free', mR, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.320), ...
        tolR, true, false, "", ...
        @(x) Roughness_ECMA418_2(x, 48000, "free-frontal", 0.320, false), ...
        ecma_rgh_plan_([1 2 3]), ts10_(c, 1), ...
        struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', 1)));

    run_metric_case(c, mkcase_('roughness_ecma418_2', 'stereo01_ts10s', mR, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.320, ...
        'channels', 'stereo+binaural'), ...
        tolR, false, false, "", ...
        @(x) Roughness_ECMA418_2(x, 48000, "free-frontal", 0.320, false), ...
        ecma_rgh_plan_(1), ts10_(c, [1 2]), ...
        struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', [1 2])));

    x = synth_am(48000, 1, 1000, 70, 100, 60);
    run_metric_case(c, mkcase_('roughness_ecma418_2', 'am01_fc1k_fmod70_60db', mR, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.320), ...
        tolR, false, false, "", ...
        @(xx) Roughness_ECMA418_2(xx, 48000, "free-frontal", 0.320, false), ...
        ecma_rgh_plan_(1), x));
    writer_f64(c, 'level3/roughness_ecma418_2/am01_fc1k_fmod70_60db/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'AM tone fc 1 kHz fmod 70 Hz depth 100 pct, 60 dB SPL'));

    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('roughness_ecma418_2', 'tone01_1khz_60db', mR, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.320), ...
        tolR, false, false, "", ...
        @(xx) Roughness_ECMA418_2(xx, 48000, "free-frontal", 0.320, false), ...
        ecma_rgh_plan_(1), x));
    writer_f64(c, 'level3/roughness_ecma418_2/tone01_1khz_60db/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 60 dB SPL, 1 s, 48 kHz'));

    x = synth_pink(48000, 1, 60, 42);
    run_metric_case(c, mkcase_('roughness_ecma418_2', 'pink01_short', mR, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.320), ...
        tolR, false, false, "", ...
        @(xx) Roughness_ECMA418_2(xx, 48000, "free-frontal", 0.320, false), ...
        ecma_rgh_plan_(1), x));
    writer_f64(c, 'level3/roughness_ecma418_2/pink01_short/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'pink noise 60 dB SPL, 1 s, 48 kHz, rng(42)'));

    run_metric_case(c, mkcase_('roughness_ecma418_2', 'diffuse01_ts10s_ch1', mR, ...
        struct('fs', 48000, 'fieldtype', 'diffuse', 'time_skip', 0.320), ...
        tolR, false, false, "", ...
        @(x) Roughness_ECMA418_2(x, 48000, "diffuse", 0.320, false), ...
        ecma_rgh_plan_(1), ts10_(c, 1), ...
        struct('path', 'signals/reference/trainstation_10s_stereo.wav', 'channel', 1)));

    x = synth_tone(48000, 1, 1000, 60);
    run_metric_case(c, mkcase_('roughness_ecma418_2', 'tskip01_tone_100ms', mR, ...
        struct('fs', 48000, 'fieldtype', 'free-frontal', 'time_skip', 0.1), ...
        tolR, false, true, "", ...
        @(xx) Roughness_ECMA418_2(xx, 48000, "free-frontal", 0.1, false), ...
        ecma_rgh_plan_(1), x));
    writer_f64(c, 'level3/roughness_ecma418_2/tskip01_tone_100ms/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'time_skip warning case: 0.1 s < 320 ms threshold'));

    ecma_asc30s_(c, 'roughness_ecma418_2', mR, @Roughness30_, tolR);
catch err
    clear cleanup
    rethrow(err);
end
end

function out = Tonality30_(x)
out = Tonality_ECMA418_2(x, 48000, "free-frontal", 0.304, false);
end

function out = Loudness30_(x)
out = Loudness_ECMA418_2(x, 48000, "free-frontal", 0.304, false);
end

function out = Roughness30_(x)
out = Roughness_ECMA418_2(x, 48000, "free-frontal", 0.320, false);
end

function ecma_asc30s_(c, metric, mfile, fcn30, tol)
% spec 5.3 caso asc30s: 30 s stereo, OUT completo, probes decimados,
% estatisticas de desvio MATLAB vs .asc no asc_dev.json; wav NAO versionado
src = fullfile(c.sqat_root, 'sound_files', 'reference_signals', ...
    'ExStereo_TrainStation7-0100-0130.wav');
[x, fs] = audioread(src);
x = double(x);
switch metric
    case 'loudness_ecma418_2'
        series = 'Loudness (Hearing Model) vs. Time.asc';
        tdep = @(o) o.loudnessTDep;
        plan = ecma_ldn_plan_(1, true);
        tsk = 0.304;
    case 'roughness_ecma418_2'
        series = 'Roughness (Hearing Model) vs. Time.asc';
        tdep = @(o) o.roughnessTDep;
        plan = ecma_rgh_plan_(1);
        tsk = 0.320;
    otherwise
        series = 'Tonality (Hearing Model) vs. Time.asc';
        tdep = @(o) o.tonalityTDep;
        plan = ecma_ton_plan_(1);
        tsk = 0.304;
end
ref = struct('path', 'sound_files/reference_signals/ExStereo_TrainStation7-0100-0130.wav', ...
    'external', true, 'sha256', string(sha256_file(src)), 'origin', ...
    'EigenScape TrainStation7-0100-0130, 30 s stereo (see docs/regen-fixtures.md)');
co = run_metric_case(c, mkcase_(metric, 'asc30s_trainstation_stereo', mfile, ...
    struct('fs', fs, 'fieldtype', 'free-frontal', 'time_skip', tsk, ...
    'channels', 'stereo 30 s', 'wav_not_versioned', true), tol, true, false, "", ...
    @(xx) fcn30(xx), plan, x, ref));
if co.skipped
    return;
end
% deviation stats vs the .asc total curve (differences-of-differences insumo)
asc_hits = dir(fullfile(c.sqat_root, 'validation', '**', ...
    ['TrainStation7-0100-0130.' strrep(series, ' ', '?')]));
if isempty(asc_hits)
    warning('export_goldens:asc', 'asc not found for %s; deviation stats skipped', metric);
    return;
end
A = readmatrix(fullfile(asc_hits(1).folder, asc_hits(1).name), 'FileType', 'text');
A = A(~any(isnan(A), 2), :);
OUT30 = co.OUT;
tml = OUT30.timeOut(:);
s = tdep(OUT30);
if size(s, 2) > 1
    s = mean(s, 2);   % documented approximation: mean over channel columns
end
si = interp1(tml, s, A(:, 1), 'linear', 'extrap');
d = si - A(:, 2);
om = struct('asc_source', series, ...
    'aggregation', 'mean over channel columns of the MATLAB series', ...
    'n_points', size(A, 1), 'max_abs_dev', max(abs(d)), ...
    'rms_dev', sqrt(mean(d.^2)), ...
    'mean_rel_dev_pct', 100 * mean(d) / max(mean(abs(A(:, 2))), eps));
writer_json(c, sprintf('level3/%s/asc30s_trainstation_stereo/asc_dev.json', metric), om);
end

function sec_level3_ecma_e4bands(c)
% Adds probe_e4_band02..52 (the other 50 auditory bands; 1, 26 and 53 were
% exported with the case) to the existing Tonality cases tone01 and pink01.
% Additive only: writes new probe files next to the existing ones, never
% touches case.json, OUT files or older probes; bands 1, 26 and 53 are
% recomputed and must equal the stored files (determinism cross-check).
if c.dryrun || ~should_run(c, 'level3/tonality_ecma418_2/e4bands'), return; end
mT = 'psychoacoustic_metrics/Tonality_ECMA418_2/Tonality_ECMA418_2.m';
pr = struct('anchor', 'pn_omz = shmAuditoryFiltBank(pn_om(:, chan), false);', ...
    'code', {'if chan == 1; export_probe(''e4all'', struct(''dec'', pn_omz(1:50:end, :))); end'});
instrument(c, mT, pr, 'ecma_e4');
cleanup = onCleanup(@() instrument_clear()); %#ok<NASGU>
cases = {'tone01_1khz_60db', synth_tone(48000, 1, 1000, 60); ...
    'pink01_short', synth_pink(48000, 1, 60, 42)};
for k = 1:size(cases, 1)
    case_rel = sprintf('level3/tonality_ecma418_2/%s', cases{k, 1});
    d = fullfile(c.out_root, case_rel);
    if c.append && ~c.full && isfile(fullfile(d, 'probe_e4_band02.f64'))
        fprintf('  case %s e4 bands (resume-skip)\n', case_rel);
        continue;
    end
    x = cases{k, 2};
    if ~isequal(rd_f64_(fullfile(d, 'input.f64')), x(:))
        error('export_goldens:e4bands', 'input of %s differs from input.f64', case_rel);
    end
    fprintf('  case %s e4 bands\n', case_rel);
    c = probe_begin(c, case_rel);
    Tonality_ECMA418_2(x, 48000, "free-frontal", 0.304, false);
    probe_off();
    S = load(fullfile(c.probe_dir, 'e4all_0001.mat'));
    B = S.S.dec;
    for z = 1:size(B, 2)
        f = sprintf('probe_e4_band%02d.f64', z);
        if any(z == [1 26 53])
            if ~isequal(rd_f64_(fullfile(d, f)), B(:, z))
                error('export_goldens:e4bands', '%s/%s differs from the stored probe', case_rel, f);
            end
            continue;
        end
        writer_f64(c, [case_rel '/' f], B(:, z), struct('unit', 'Pa', ...
            'description', sprintf('auditory band %d waveform, decimated x50', z), ...
            'source', struct('m_file', 'utilities/ECMA418_2/shmAuditoryFiltBank.m', ...
            'stage', 'shmAuditoryFiltBank')));
    end
end
end

function v = rd_f64_(p)
fid = fopen(p, 'r', 'ieee-le');
v = fread(fid, Inf, 'double');
fclose(fid);
end

function probes = ecma_ton_probes_()
gd = 'if zBand == 61 || zBand == 31 || zBand == 1; ';
gs = 'if zBand == 53 || zBand == 27 || zBand == 1; ';
e = '; end';
probes = struct('anchor', {}, 'code', {});
probes(end+1) = struct('anchor', '    [p_re, ~] = shmResample(insig, fs);', ...
    'code', {'export_probe(''e1'', struct(''p_re_dec'', p_re(1:50:end), ''n_full'', numel(p_re)));'});
probes(end+1) = struct('anchor', 'pn = shmPreProc(p_re, max(blockSize), max(hopSize));', ...
    'code', {'export_probe(''e2'', struct(''pn_dec'', pn(1:50:end, :), ''shape_full'', size(pn)));'});
probes(end+1) = struct('anchor', 'pn_om = shmOutMidEarFilter(pn, fieldtype);', ...
    'code', {'export_probe(''e3'', struct(''pn_om_dec'', pn_om(1:50:end, :), ''shape_full'', size(pn_om)));'});
probes(end+1) = struct('anchor', 'pn_omz = shmAuditoryFiltBank(pn_om(:, chan), false);', ...
    'code', {'if chan == 1; export_probe(''e4'', struct(''b01'', pn_omz(1:50:end, 1), ''b26'', pn_omz(1:50:end, 26), ''b53'', pn_omz(1:50:end, 53), ''shape_full'', size(pn_omz))); end'});
probes(end+1) = struct('anchor', ...
    '        [pn_lz, ~] = shmSignalSegment(pn_omzDupe(:, zBand), 1,...', ...
    'code', {[gd 'export_probe(''t1'', struct(''band'', zBand, ''blocks'', pn_lz(1:min(3, size(pn_lz,1)), :), ''shape_full'', size(pn_lz)))' e]});
probes(end+1) = struct('anchor', ...
    '            = shmBasisLoudness(pn_lz, bandCentreFreqsDupe(zBand));', ...
    'code', {[gd 'export_probe(''t2'', struct(''band'', zBand, ''pn_rlz'', pn_rlz(1:min(3, size(pn_rlz,1)), :), ''bandBasisLoudness'', bandBasisLoudness))' e]});
probes(end+1) = struct('anchor', ...
    '        unbiasedNormACF = unscaledACF(1:blockSizeDupe(zBand), :)./denom;', ...
    'code', {[gd 'export_probe(''t3'', struct(''band'', zBand, ''unscaledACF'', unscaledACF(1:min(64, end), 1:min(3, end)), ''unbiasedNormACF'', unbiasedNormACF(1:min(64, end), 1:min(3, end))))' e]});
probes(end+1) = struct('anchor', ...
    '        lagWindowACF(mz_start:mz_end, :) = meanScaledACF(mz_start:mz_end, :)...', ...
    'code', {[gd 'export_probe(''t4'', struct(''band'', zBand, ''meanScaledACF'', meanScaledACF(1:min(64, end), 1:min(3, end)), ''lagWindowACF'', lagWindowACF(1:min(64, end), 1:min(3, end))))' e]});
probes(end+1) = struct('anchor', ...
    '        bandTonalFreqs = bandTonalFreqs(1:l_end);', ...
    'code', {[gd 'export_probe(''t5'', struct(''band'', zBand, ''bandTonalLoudness'', bandTonalLoudness, ''bandTonalFreqs'', bandTonalFreqs, ''bandLoudness'', bandLoudness))' e]});
probes(end+1) = struct('anchor', ...
    '        SNRlz = shmNoiseRedLowPass(SNRlz1, sampleRate1875);', ...
    'code', {[gd 'export_probe(''t6a'', struct(''band'', zBand, ''SNRlz1'', SNRlz1(1:min(64, end)), ''SNRlz'', SNRlz(1:min(64, end)), ''nrlz'', bandTonalLoudness))' e]});
probes(end+1) = struct('anchor', ...
    '        specNoiseLoudness(:, zBand, chan) = bandNoiseLoudness;', ...
    'code', {[gs 'export_probe(''t6b'', struct(''band'', zBand, ''specTonalLoudness_col'', specTonalLoudness(:, zBand, chan), ''specNoiseLoudness_col'', specNoiseLoudness(:, zBand, chan)))' e]});
probes(end+1) = struct('anchor', ...
    '    specTonality = cal_T*cal_Tx*ql.*specTonalLoudness;  % time-dependent specific tonality', ...
    'code', {'export_probe(''t7a'', struct(''overallSNR'', overallSNR(1:min(64, end), :), ''ql'', ql(1:min(64, end), :)));'});
probes(end+1) = struct('anchor', ...
    '    [tonalityTDep(:, chan), zmax] = max(specTonality(:, :, chan), [], 2);', ...
    'code', {'export_probe(''t7b'', struct(''tonalityTDep_ch'', tonalityTDep(:, chan), ''zmax'', zmax));'});
probes(end+1) = struct('anchor', ...
    '    tonalityAvg(chan) = sum(tonalityTDep(mask, chan))/(nnz(mask) + epsilon); %<--- time index takes <time_skip> into consideration', ...
    'code', {'export_probe(''t7c'', struct(''tonalityAvg_ch'', tonalityAvg(chan), ''mask_dec'', mask(1:20:end), ''tonalityTDepFreqs_ch'', tonalityTDepFreqs(:, chan)));'});
end

function probes = ecma_ldn_probes_()
probes = struct('anchor', {}, 'code', {});
probes(end+1) = struct('anchor', ...
    '    specLoudness(:, :, chan) = (specTonalLoudness(:, :, chan).^maxLoudnessFuncel...', ...
    'code', {'export_probe(''l1'', struct(''maxLoudnessFuncel'', maxLoudnessFuncel, ''specLoudness_ch'', specLoudness(:, :, chan)));'});
probes(end+1) = struct('anchor', ...
    '    specLoudness(:, :, 3) = sqrt(sum(specLoudness(:, :, 1:2).^2, 3)/2);', ...
    'code', {'export_probe(''l2'', struct(''specLoudness_bin'', specLoudness(:, :, 3)));'});
probes(end+1) = struct('anchor', ...
    '    loudnessPowAvg = (sum(loudnessTDep(time_skip_idx:end,...', ...
    'code', {'export_probe(''l3'', struct(''loudnessTDep'', loudnessTDep, ''specLoudnessPowAvg'', specLoudnessPowAvg, ''loudnessPowAvg'', loudnessPowAvg, ''time_skip_idx'', time_skip_idx));'});
end

function probes = ecma_rgh_probes_()
gd = 'if zBand == 53 || zBand == 27 || zBand == 1; ';
e = '; end';
probes = struct('anchor', {}, 'code', {});
probes(end+1) = struct('anchor', '    [p_re, ~] = shmResample(insig, fs);', ...
    'code', {'export_probe(''e1'', struct(''p_re_dec'', p_re(1:50:end), ''n_full'', numel(p_re)));'});
probes(end+1) = struct('anchor', ...
    'pn = shmPreProc(p_re, max(blockSize), max(hopSize), true, false);', ...
    'code', {'export_probe(''e2'', struct(''pn_dec'', pn(1:50:end, :), ''shape_full'', size(pn)));'});
probes(end+1) = struct('anchor', 'pn_om = shmOutMidEarFilter(pn, fieldtype);', ...
    'code', {'export_probe(''e3'', struct(''pn_om_dec'', pn_om(1:50:end, :), ''shape_full'', size(pn_om)));'});
probes(end+1) = struct('anchor', 'pn_omz = shmAuditoryFiltBank(pn_om(:, chan), false);', ...
    'code', {'if chan == 1; export_probe(''e4'', struct(''b01'', pn_omz(1:50:end, 1), ''b26'', pn_omz(1:50:end, 26), ''b53'', pn_omz(1:50:end, 53), ''shape_full'', size(pn_omz))); end'});
probes(end+1) = struct('anchor', ...
    '        [pn_lz, iBlocksOut] = shmSignalSegment(pn_omz(:, zBand), 1, blockSize,...', ...
    'code', {[gd 'export_probe(''r1'', struct(''band'', zBand, ''blocks'', pn_lz(1:min(3, size(pn_lz,1)), :), ''iBlocksOut'', iBlocksOut))' e]});
probes(end+1) = struct('anchor', ...
    '        basisLoudness(:, :, zBand) = bandBasisLoudness;', ...
    'code', {[gd 'export_probe(''r2'', struct(''band'', zBand, ''bandBasisLoudness'', bandBasisLoudness))' e]});
probes(end+1) = struct('anchor', ...
    '        envelopes(:, :, zBand) = downsample(abs(hilbert(pn_lz)), downSample, 0);', ...
    'code', {[gd 'export_probe(''r3'', struct(''band'', zBand, ''envelope_cols'', envelopes(:, 1:min(3, end), zBand)))' e]});
probes(end+1) = struct('anchor', ...
    '                                               blockSize1500, [], nBands))).^2;', ...
    'code', {'export_probe(''r4'', struct(''envelopeWin_cols'', envelopeWin(:, 1:min(3, end), 1), ''modSpectra_slice'', modSpectra(1:min(64, end), 1:min(3, end), 1)));'});
probes(end+1) = struct('anchor', ...
    '    modWeightSpectraAvg = modSpectraAvg.*weightingFactor; % Equation 69 [Phihat(k)_E,l,z]', ...
    'code', {'export_probe(''r5'', struct(''modSpectraAvg_slice'', modSpectraAvg(1:min(64, end), 1:min(3, end), 1), ''clipWeight'', clipWeight, ''weightingFactor_slice'', weightingFactor(1:min(64, end), 1:min(3, end)), ''modWeightSpectraAvg_slice'', modWeightSpectraAvg(1:min(64, end), 1:min(3, end), 1)));'});
probes(end+1) = struct('anchor', ...
    '                PhiPks = PhiPks(mask);  % [Phihat(k_p,i(l,z))]', ...
    'code', {'if lBlock == 1 && zBand == 1; export_probe(''r6a'', struct(''kLocs'', kLocs, ''PhiPks'', PhiPks)); end'});
probes(end+1) = struct('anchor', ...
    '                    modRate(iPeak, lBlock, zBand) = modRateEst + biasAdjust;', ...
    'code', {'if lBlock == 1 && zBand == 1 && iPeak == 1; export_probe(''r6b'', struct(''modAmp_slice'', modAmp(:, 1:min(3, end), 1), ''modRate_slice'', modRate(:, 1:min(3, end), 1), ''modRateEst'', modRateEst, ''biasAdjust'', biasAdjust)); end'});
probes(end+1) = struct('anchor', ...
    '    modAmpMax = modMaxLoWeight;', ...
    'code', {'export_probe(''r7'', struct(''modFundRate'', modFundRate, ''modMaxWeight_slice'', modMaxWeight(:, 1:min(3, end), 1), ''modAmpHiWeight_slice'', modAmpHiWeight(:, 1:min(3, end), 1)));'});
probes(end+1) = struct('anchor', ...
    '    modAmpMax(modAmpMax < 0.074376) = 0;', ...
    'code', {'export_probe(''r8a'', struct(''modAmpMax'', modAmpMax));'});
probes(end+1) = struct('anchor', ...
    '        specRoughEst(:, zBand) = pchip(x, modAmpMax(:, zBand), xq);', ...
    'code', {[gd 'export_probe(''r8b'', struct(''band'', zBand, ''specRoughEst_col'', specRoughEst(:, zBand)))' e]});
probes(end+1) = struct('anchor', ...
    '    specRoughness(:, :, chan) = shmRoughLowPass(specRoughEstTform, sampleRate50, ...', ...
    'code', {'export_probe(''r8c'', struct(''specRoughEstTform_slice'', specRoughEstTform(1:min(64, end), 1:min(3, end)), ''specRoughness_ch'', specRoughness(:, :, chan)));'});
end

function plan = ecma_ton_plan_(parts)
M = 'psychoacoustic_metrics/Tonality_ECMA418_2/Tonality_ECMA418_2.m';
plan = [ ...
    plan1('e1', {pf(1, 'p_re_dec', 'probe_e1_pre.f64', 'Pa', ...
        'p_re post-resample 48 kHz, decimated x50 at capture (full input is the case input)', ...
        'utilities/ECMA418_2/shmResample.m', 'shmResample'), ...
        pf(1, 'n_full', 'probe_e1_n.f64', '', 'full length of p_re', ...
        'utilities/ECMA418_2/shmResample.m', 'shmResample')}, struct('nodecimate', true, 'optional', true)), ...
    plan1('e2', {pf(1, 'pn_dec', 'probe_e2_preproc.f64', 'Pa', ...
        'pn post fade-in + zero-pad, decimated x50 at capture', ...
        'utilities/ECMA418_2/shmPreProc.m', 'shmPreProc')}, struct('nodecimate', true)), ...
    plan1('e3', {pf(1, 'pn_om_dec', 'probe_e3_omear.f64', 'Pa', ...
        'pn_om post outer/middle ear filter, decimated x50', ...
        'utilities/ECMA418_2/shmOutMidEarFilter.m', 'shmOutMidEarFilter')}, struct('nodecimate', true)), ...
    plan1('e4', {pf(1, 'b01', 'probe_e4_band01.f64', 'Pa', ...
        'auditory band 1 waveform, decimated x50', ...
        'utilities/ECMA418_2/shmAuditoryFiltBank.m', 'shmAuditoryFiltBank'), ...
        pf(1, 'b26', 'probe_e4_band26.f64', 'Pa', 'auditory band 26 (~1 kHz) waveform', ...
        'utilities/ECMA418_2/shmAuditoryFiltBank.m', 'shmAuditoryFiltBank'), ...
        pf(1, 'b53', 'probe_e4_band53.f64', 'Pa', 'auditory band 53 (edge) waveform', ...
        'utilities/ECMA418_2/shmAuditoryFiltBank.m', 'shmAuditoryFiltBank')}, ...
        struct('nodecimate', true)), ...
    ecma_parts_plan_(parts, 't1', {'blocks'}, {'probe_t1_segment'}, {'Pa'}, ...
        'segmented blocks (exemplar band, first 3 blocks)', M, 'shmSignalSegment', true), ...
    ecma_parts_plan_(parts, 't2', {'pn_rlz', 'bandBasisLoudness'}, {'probe_t2_pnrlz', 'probe_t2_basisloudness'}, ...
        {'Pa', 'sone_HMS'}, 'rectified segments + basis loudness (exemplar band)', M, 'shmBasisLoudness', false), ...
    ecma_parts_plan_(parts, 't3', {'unscaledACF', 'unbiasedNormACF'}, {'probe_t3_unscaledacf', 'probe_t3_unbiasednormacf'}, ...
        {'', ''}, 'ACF slices 64 x 3 (exemplar band)', M, 'Eq 27-30', false), ...
    ecma_parts_plan_(parts, 't4', {'meanScaledACF', 'lagWindowACF'}, {'probe_t4_meanscaledacf', 'probe_t4_lagwindowacf'}, ...
        {'', ''}, 'band-averaged + lag-windowed ACF slices', M, 'Eq 31-35', false), ...
    ecma_parts_plan_(parts, 't5', {'bandTonalLoudness', 'bandTonalFreqs', 'bandLoudness'}, ...
        {'probe_t5_bandtonalloudness', 'probe_t5_bandtonalfreqs', 'probe_t5_bandloudness'}, ...
        {'sone_HMS', 'Hz', 'sone_HMS'}, 'post-FFT tonal loudness terms (exemplar band, post 187.5 Hz interp)', ...
        M, 'Eq 36-40', false), ...
    ecma_parts_plan_(parts, 't6a', {'SNRlz1', 'SNRlz', 'nrlz'}, ...
        {'probe_t6_snrlz1', 'probe_t6_snrlz', 'probe_t6_nrlz'}, ...
        {'', '', 'sone_HMS'}, 'noise reduction SNR terms (exemplar dupe band)', M, 'Eq 42-47', false), ...
    ecma_parts_plan_(parts, 't6b', {'specTonalLoudness_col', 'specNoiseLoudness_col'}, ...
        {'probe_t6_spectraltonalloudness', 'probe_t6_specnoiseloudness'}, ...
        {'sone_HMS', 'sone_HMS'}, 'stacked spec tonal/noise loudness columns (exemplar band)', M, 'Eq 42-47', false), ...
    plan1('t7a', {pf(1, 'overallSNR', 'probe_t7_overallsnr.f64', '', ...
        'overallSNR slice', M, 'Eq 48-61'), ...
        pf(1, 'ql', 'probe_t7_ql.f64', '', 'sigmoidal scaling ql slice', M, 'Eq 48-61')}, struct()), ...
    plan1('t7b', {pf(1, 'tonalityTDep_ch', 'probe_t7_tonalitytdep.f64', 'tu_HMS', ...
        'tonalityTDep channel 1', M, 'Eq 48-61'), ...
        pf(1, 'zmax', 'probe_t7_zmax.f64', '', 'argmax band per time', M, 'Eq 48-61')}, struct()), ...
    plan1('t7c', {pf(1, 'tonalityAvg_ch', 'probe_t7_tonalityavg.f64', 'tu_HMS', ...
        'time-averaged tonality', M, 'Eq 48-61'), ...
        pf(1, 'tonalityTDepFreqs_ch', 'probe_t7_tonalitytdepfreqs.f64', 'Hz', ...
        'tonality frequencies over time', M, 'Eq 48-61')}, struct())];
end

function plan = ecma_parts_plan_(parts, name, fields, bases, units, desc, mfile, stage, nodec)
fl = {};
for i = 1:numel(fields)
    for k = 1:numel(parts)
        if numel(parts) == 1
            fname = sprintf('%s.f64', bases{i});
        else
            fname = sprintf('%s_%02d.f64', bases{i}, parts(k));
        end
        fl{end+1} = pf(parts(k), fields{i}, fname, units{i}, desc, mfile, stage); %#ok<AGROW>
    end
end
plan = plan1(name, fl, struct('nodecimate', nodec, 'optional', true));
end

function plan = ecma_ldn_plan_(parts, stereo)
M = 'psychoacoustic_metrics/Loudness_ECMA418_2/Loudness_ECMA418_2.m';
plan = [ ...
    ecma_ton_plan_(parts), ...
    plan1('l1', {pf(1, 'maxLoudnessFuncel', 'probe_l1_maxloudnessfuncel.f64', '', ...
        'Eq 114 max-combine exponent per band/time', M, 'Eq 113/114'), ...
        pf(1, 'specLoudness_ch', 'probe_l1_specloudness.f64', 'sone_HMS/Bark', ...
        'combined specific loudness channel', M, 'Eq 113/114')}, struct()), ...
    plan1('l3', {pf(1, 'loudnessTDep', 'probe_l3_loudnesstdep.f64', 'sone_HMS', ...
        'loudnessTDep Eq 115-116', M, 'Eq 115-117'), ...
        pf(1, 'specLoudnessPowAvg', 'probe_l3_specloudnesspowavg.f64', 'sone_HMS/Bark', ...
        'power-averaged specific loudness Eq 117', M, 'Eq 115-117'), ...
        pf(1, 'loudnessPowAvg', 'probe_l3_loudnesspowavg.f64', 'sone_HMS', ...
        'power-averaged loudness Eq 115', M, 'Eq 115-117'), ...
        pf(1, 'time_skip_idx', 'probe_l3_timeskipidx.f64', '', 'time_skip index', M, 'Eq 115-117')}, ...
        struct())];
if stereo
    plan = [plan, plan1('l2', {pf(1, 'specLoudness_bin', 'probe_l2_specloudness_bin.f64', ...
        'sone_HMS/Bark', 'binaural combined specific loudness Eq 118', M, 'Eq 118')}, ...
        struct())];
end
end

function plan = ecma_rgh_plan_(parts)
M = 'psychoacoustic_metrics/Roughness_ECMA418_2/Roughness_ECMA418_2.m';
plan = [ ...
    plan1('e1', {pf(1, 'p_re_dec', 'probe_e1_pre.f64', 'Pa', ...
        'p_re post-resample 48 kHz, decimated x50 at capture', ...
        'utilities/ECMA418_2/shmResample.m', 'shmResample')}, struct('nodecimate', true, 'optional', true)), ...
    plan1('e2', {pf(1, 'pn_dec', 'probe_e2_preproc.f64', 'Pa', ...
        'pn post fade-in + start zero-pad, decimated x50', ...
        'utilities/ECMA418_2/shmPreProc.m', 'shmPreProc')}, struct('nodecimate', true)), ...
    plan1('e3', {pf(1, 'pn_om_dec', 'probe_e3_omear.f64', 'Pa', ...
        'pn_om post outer/middle ear filter, decimated x50', ...
        'utilities/ECMA418_2/shmOutMidEarFilter.m', 'shmOutMidEarFilter')}, struct('nodecimate', true)), ...
    plan1('e4', {pf(1, 'b01', 'probe_e4_band01.f64', 'Pa', 'auditory band 1 waveform', ...
        'utilities/ECMA418_2/shmAuditoryFiltBank.m', 'shmAuditoryFiltBank')}, struct('nodecimate', true)), ...
    ecma_parts_plan_(parts, 'r1', {'blocks'}, {'probe_r1_segment'}, {'Pa'}, ...
        'segmented blocks (exemplar band, first 3)', M, 'section 7.1.1', true), ...
    ecma_parts_plan_(parts, 'r2', {'bandBasisLoudness'}, {'probe_r2_basisloudness'}, {'sone_HMS'}, ...
        'basis loudness per band (exemplar)', M, 'shmBasisLoudness', false), ...
    ecma_parts_plan_(parts, 'r3', {'envelope_cols'}, {'probe_r3_envelope'}, {'Pa'}, ...
        'hilbert envelope post downsample 32, first 3 blocks (exemplar band)', M, 'Eq 65', false), ...
    plan1('r4', {pf(1, 'envelopeWin_cols', 'probe_r4_envelopewin.f64', 'Pa', ...
        'hann(512)-windowed envelopes, first 3 blocks band 1', M, 'Eq 66-67'), ...
        pf(1, 'modSpectra_slice', 'probe_r4_modspectra.f64', '', ...
        'modulation spectra slice 64 x 3 band 1', M, 'Eq 66-67')}, struct('nodecimate', true)), ...
    plan1('r5', {pf(1, 'modSpectraAvg_slice', 'probe_r5_modspectraavg.f64', '', ...
        'band-averaged modulation spectra slice', M, 'Eq 68'), ...
        pf(1, 'clipWeight', 'probe_r5_clipweight.f64', '', 'Eq 71 clip weight', M, 'Eq 71'), ...
        pf(1, 'weightingFactor_slice', 'probe_r5_weightingfactor.f64', '', 'Eq 70 weighting slice', M, 'Eq 70'), ...
        pf(1, 'modWeightSpectraAvg_slice', 'probe_r5_modweightspectraavg.f64', '', ...
        'weighted averaged modulation spectra Eq 69', M, 'Eq 69')}, struct('nodecimate', true)), ...
    plan1('r6a', {pf(1, 'kLocs', 'probe_r6_klocs.f64', '', 'peak locations block 1 band 1', M, 'Eq 72-81'), ...
        pf(1, 'PhiPks', 'probe_r6_phipks.f64', '', 'peak values block 1 band 1', M, 'Eq 72-81')}, ...
        struct('nodecimate', true, 'optional', true)), ...
    plan1('r6b', {pf(1, 'modAmp_slice', 'probe_r6_modamp.f64', '', 'modAmp slice', M, 'Eq 82'), ...
        pf(1, 'modRate_slice', 'probe_r6_modrate.f64', 'Hz', 'modRate slice Eq 77', M, 'Eq 77'), ...
        pf(1, 'modRateEst', 'probe_r6_modrateest.f64', 'Hz', 'Eq 76 estimate', M, 'Eq 76'), ...
        pf(1, 'biasAdjust', 'probe_r6_biasadjust.f64', 'Hz', 'Eq 78 bias correction', M, 'Eq 78')}, ...
        struct('nodecimate', true, 'optional', true)), ...
    plan1('r7', {pf(1, 'modFundRate', 'probe_r7_modfundrate.f64', 'Hz', ...
        'fundamental modulation rate per block/band', M, 'Eq 83-96'), ...
        pf(1, 'modMaxWeight_slice', 'probe_r7_modmaxweight.f64', '', 'Eq 92 weights slice', M, 'Eq 92'), ...
        pf(1, 'modAmpHiWeight_slice', 'probe_r7_modamphiweight.f64', '', 'hi-rate weighted amplitude slice', ...
        M, 'Eq 83-96')}, struct('nodecimate', true)), ...
    plan1('r8a', {pf(1, 'modAmpMax', 'probe_r8_modampmax.f64', '', 'modAmpMax Eq 95', M, 'Eq 83-96')}, struct()), ...
    ecma_parts_plan_(parts, 'r8b', {'specRoughEst_col'}, {'probe_r8_specroughest'}, {''}, ...
        'pchip-50Hz specific roughness estimate (exemplar band)', M, 'Eq 97-112', false), ...
    plan1('r8c', {pf(1, 'specRoughEstTform_slice', 'probe_r8_specroughesttform.f64', '', ...
        'transformed estimate slice', M, 'Eq 97-112'), ...
        pf(1, 'specRoughness_ch', 'probe_r8_specroughness.f64', 'asper_HMS/Bark', ...
        'specific roughness post shmRoughLowPass', M, 'Eq 97-112')}, struct('nodecimate', true))];
end

% ========================================================================
% Section: level3/roughness_daniel1997 (spec 5.4)
% =========================================================================

function sec_level3_daniel(c)
mfile = 'psychoacoustic_metrics/Roughness_Daniel1997/Roughness_Daniel1997.m';
if ~should_run(c, 'level3/roughness_daniel1997'), return; end
instrument(c, mfile, daniel_probes_(), 'daniel');
cleanup = onCleanup(@() instrument_clear());
try
    tol = 'R abs 0.01 asper or 1 pct rel (whichever is larger)';

    [xref, fsr] = audioread(fullfile(c.sqat_root, 'sound_files', ...
        'reference_signals', 'RefSignal_Roughness_Daniel1997.wav'));
    xref = double(xref(:, 1));
    run_metric_case(c, mkcase_('roughness_daniel1997', 'ref01_refsignal_5s_48k', mfile, ...
        struct('fs', fsr, 'time_skip', 0), tol, true, false, "", ...
        @(x) Roughness_Daniel1997(x, fsr, 0, false), daniel_plan_(true), xref, ...
        struct('path', 'signals/reference/refsignal_daniel_5s.wav', 'channel', 1)));

    x = synth_am(48000, 2, 1000, 70, 100, 60);
    run_metric_case(c, mkcase_('roughness_daniel1997', 'am01_fc1k_fmod70_60db', mfile, ...
        struct('fs', 48000, 'time_skip', 0), tol, false, false, "", ...
        @(xx) Roughness_Daniel1997(xx, 48000, 0, false), daniel_plan_(false), x));
    writer_f64(c, 'level3/roughness_daniel1997/am01_fc1k_fmod70_60db/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'AM tone fc 1 kHz fmod 70 Hz depth 100 pct, 60 dB SPL, 2 s'));

    x = synth_tone(48000, 2, 1000, 130);
    run_metric_case(c, mkcase_('roughness_daniel1997', 'clamp01_1khz_130db', mfile, ...
        struct('fs', 48000, 'time_skip', 0), tol, ...
        false, true, 'SQAT:Roughness:TerhardtSlopeClamped', ...
        @(xx) Roughness_Daniel1997(xx, 48000, 0, false), daniel_plan_(false), x));
    writer_f64(c, 'level3/roughness_daniel1997/clamp01_1khz_130db/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 130 dB SPL: Terhardt slope clamp warning case'));

    x = [zeros(round(0.5*48000), 1); xref(1:round(2*48000))];
    run_metric_case(c, mkcase_('roughness_daniel1997', 'sil01_silence_plus_ref', mfile, ...
        struct('fs', 48000, 'time_skip', 0), tol, false, false, "", ...
        @(xx) Roughness_Daniel1997(xx, 48000, 0, false), daniel_plan_(false), x));
    writer_f64(c, 'level3/roughness_daniel1997/sil01_silence_plus_ref/input.f64', x, ...
        struct('unit', 'Pa', 'description', '0.5 s silence + first 2 s of RefSignal (windows without component)'));

    S = load(fullfile(c.extras_root, 'sound_files', 'validation_SQAT_v1_0', ...
        'Roughness_Daniel1997', 'vary_modulation_freq_fmod_1khz.mat'));
    vn = first_field_(S);
    if isfield(S, 'fs'), fsm = S.fs; else, fsm = 48000; end
    xm = S.(vn)(1, :).';
    run_metric_case(c, mkcase_('roughness_daniel1997', 'mat01_vary_fmod_1khz_row1', mfile, ...
        struct('fs', fsm, 'time_skip', 0, 'input_source', ...
        'sound_files/validation_SQAT_v1_0/Roughness_Daniel1997/vary_modulation_freq_fmod_1khz.mat row 1 (Zenodo 7933206)'), ...
        tol, false, false, "", @(xx) Roughness_Daniel1997(xx, fsm, 0, false), ...
        daniel_plan_(false), xm, ...
        struct('path', 'validation/roughness_daniel1997/row_vary_modulation_freq_fmod_1khz_row1.f64')));
catch err
    clear cleanup
    rethrow(err);
end
end

function probes = daniel_probes_()
g = 'if windowNum == 1 || windowNum == ceil(n/2) || windowNum == n; ';
e = '; end';
probes = struct('anchor', {}, 'code', {});
probes(end+1) = struct('anchor', '    window = blackman(N,''periodic'');', ...
    'code', {'export_probe(''d1'', struct(''audio'', audio, ''fs'', fs));'});
probes(end+1) = struct('anchor', ...
    '    FreqIn = a0.*fft( transpose(dataIn*AmpCal) );', ...
    'code', {[g 'export_probe(''d2'', struct(''dataIn'', dataIn, ''FreqIn_re'', real(FreqIn), ''FreqIn_im'', imag(FreqIn), ''a0'', a0, ''window'', window, ''AmpCal'', AmpCal))' e]});
probes(end+1) = struct('anchor', ...
    '    [ei, info] = Terhardt_filterbank(FreqIn, params);', ...
    'code', {[g 'export_probe(''d3'', struct(''ei'', ei, ''clamp_n'', info.clamp.n, ''clampLdB'', info.clamp.LdB, ''clampFreq'', info.clamp.freq))' e]});
probes(end+1) = struct('anchor', ...
    '    [mdept,hBPi] = il_modulation_depths(ei,Hweight);', ...
    'code', {[g 'export_probe(''d4'', struct(''mdept'', mdept, ''hBPi_slice'', hBPi(:, 1:min(256, end))))' e]});
probes(end+1) = struct('anchor', '    ki = il_cross_correlation(hBPi);', ...
    'code', {[g 'export_probe(''d5'', struct(''ki'', ki))' e]});
probes(end+1) = struct('anchor', ...
    '    ri = il_specific_roughness(mdept,ki,gzi,Cal,Chno);', ...
    'code', {[g 'export_probe(''d6'', struct(''ri'', ri, ''gzi'', gzi, ''Cal'', Cal))' e]});
end

function plan = daniel_plan_(anchor)
M = 'psychoacoustic_metrics/Roughness_Daniel1997/Roughness_Daniel1997.m';
if anchor
    parts = [1 2 3];
else
    parts = 1;
end
pe = {}; pm = {}; ph = {}; pk = {}; pr = {};
for k = 1:numel(parts)
    suf = '';
    if numel(parts) > 1
        suf = sprintf('_w%02d', parts(k));
    end
    pe{end+1} = pf(parts(k), 'ei', sprintf('probe_d3_excitation%s.f64', suf), '', ...
        'Terhardt filterbank excitation of window', M, 'Terhardt_filterbank'); %#ok<AGROW>
    pm{end+1} = pf(parts(k), 'mdept', sprintf('probe_d4_moddepth%s.f64', suf), '', ...
        'modulation depths', M, 'il_modulation_depths'); %#ok<AGROW>
    ph{end+1} = pf(parts(k), 'hBPi_slice', sprintf('probe_d4_hbpi%s.f64', suf), '', ...
        'band-passed envelope spectra slice (first 256 bins)', M, 'il_modulation_depths'); %#ok<AGROW>
    pk{end+1} = pf(parts(k), 'ki', sprintf('probe_d5_crosscorr%s.f64', suf), '', ...
        'cross-correlation coefficients', M, 'il_cross_correlation'); %#ok<AGROW>
    pr{end+1} = pf(parts(k), 'ri', sprintf('probe_d6_specific%s.f64', suf), 'asper/Bark', ...
        'specific roughness pattern of window', M, 'il_specific_roughness'); %#ok<AGROW>
end
plan = [ ...
    plan1('d1', {pf(1, 'audio', 'probe_d1_insig48k.f64', 'Pa', ...
        'audio post-resample-or-native 48 kHz', M, 'resample'), ...
        pf(1, 'fs', 'probe_d1_fs.f64', 'Hz', 'fs of analysis', M, 'resample')}, ...
        struct('longdec', 100)), ...
    plan1('d2', {pf(1, 'dataIn', 'probe_d2_datain_w1.f64', 'Pa', ...
        'windowed data of window 1', M, 'fft window'), ...
        pf(1, 'FreqIn_re', 'probe_d2_freqin_w1_re.f64', '', 'window spectrum real part', M, 'fft window'), ...
        pf(1, 'FreqIn_im', 'probe_d2_freqin_w1_im.f64', '', 'window spectrum imag part', M, 'fft window'), ...
        pf(1, 'a0', 'probe_d2_a0.f64', '', 'a0 weighting in frequency', M, 'calculate_a0'), ...
        pf(1, 'window', 'probe_d2_window.f64', '', 'blackman window', M, 'window'), ...
        pf(1, 'AmpCal', 'probe_d2_ampcal.f64', '', 'calibration factor', M, 'AmpCal')}, ...
        struct('nodecimate', true)), ...
    plan1('d3', pe, struct('nodecimate', true)), ...
    plan1('d4', [pm, ph], struct('nodecimate', true)), ...
    plan1('d5', pk, struct('nodecimate', true)), ...
    plan1('d6', [pr, ...
        pf(1, 'gzi', 'probe_d6_gzi.f64', '', 'gzi weighting function', M, 'Get_gzi_roughness'), ...
        pf(1, 'Cal', 'probe_d6_cal.f64', '', 'calibration constant', M, 'cal')], ...
        struct('nodecimate', true))];
end

% ========================================================================
% Section: level3/fluctuation_strength_osses2016 (spec 5.5)
% =========================================================================

function sec_level3_fs(c)
mfile = 'psychoacoustic_metrics/FluctuationStrength_Osses2016/FluctuationStrength_Osses2016.m';
if ~should_run(c, 'level3/fluctuation_strength_osses2016'), return; end
instrument(c, mfile, fs_probes_(), 'fs_osses');
cleanup = onCleanup(@() instrument_clear());
try
    tol = 'F abs 0.01 vacil';

    x = synth_am(44100, 8, 1000, 4, 100, 70);
    run_metric_case(c, mkcase_('fluctuation_strength_osses2016', 'anchor01_am4hz_70db_m1', mfile, ...
        struct('fs', 44100, 'method', 1, 'time_skip', 0), tol, ...
        true, false, "", @(xx) FluctuationStrength_Osses2016(xx, 44100, 1, 0, false), ...
        fs_plan_(true), x));
    writer_f64(c, 'level3/fluctuation_strength_osses2016/anchor01_am4hz_70db_m1/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'AM tone fc 1 kHz fmod 4 Hz depth 100 pct, 70 dB SPL, 8 s, 44.1 kHz'));

    x = synth_pink(44100, 1, 70, 42);
    run_metric_case(c, mkcase_('fluctuation_strength_osses2016', 'm0_01_stationary_pink', mfile, ...
        struct('fs', 44100, 'method', 0, 'time_skip', 0), tol, ...
        false, false, "", @(xx) FluctuationStrength_Osses2016(xx, 44100, 0, 0, false), ...
        fs_plan_(false), x));
    writer_f64(c, 'level3/fluctuation_strength_osses2016/m0_01_stationary_pink/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'stationary pink noise 70 dB SPL, 1 s, method 0'));

    x = synth_am(44100, 1.5, 1000, 4, 100, 70);
    run_metric_case(c, mkcase_('fluctuation_strength_osses2016', 'short01_lt2s_switch_m0', mfile, ...
        struct('fs', 44100, 'method', 1, 'time_skip', 0), tol, ...
        false, true, "", @(xx) FluctuationStrength_Osses2016(xx, 44100, 1, 0, false), ...
        fs_plan_(false), x));
    writer_f64(c, 'level3/fluctuation_strength_osses2016/short01_lt2s_switch_m0/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1.5 s AM tone: shorter than 2 s, method auto-switches to 0 (warning)'));

    x = synth_tone(44100, 2, 1000, 130);
    run_metric_case(c, mkcase_('fluctuation_strength_osses2016', 'clamp01_1khz_130db', mfile, ...
        struct('fs', 44100, 'method', 1, 'time_skip', 0), tol, ...
        false, true, 'SQAT:FluctuationStrength:TerhardtSlopeClamped', ...
        @(xx) FluctuationStrength_Osses2016(xx, 44100, 1, 0, false), fs_plan_(false), x));
    writer_f64(c, 'level3/fluctuation_strength_osses2016/clamp01_1khz_130db/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 130 dB SPL: Terhardt slope clamp warning case'));

    x = synth_am(44100, 2, 1000, 4, 100, 60) + synth_tone(44100, 2, 16000, 100);
    run_metric_case(c, mkcase_('fluctuation_strength_osses2016', 'comp01_16khz_100db', mfile, ...
        struct('fs', 44100, 'method', 1, 'time_skip', 0), tol, ...
        false, false, "", @(xx) FluctuationStrength_Osses2016(xx, 44100, 1, 0, false), ...
        fs_plan_(false), x));
    writer_f64(c, 'level3/fluctuation_strength_osses2016/comp01_16khz_100db/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'AM tone + 16 kHz tone 100 dB (component above the last band)'));

    x = synth_noise_band(44100, 2, 1000, 800, 70, 42);
    run_metric_case(c, mkcase_('fluctuation_strength_osses2016', 'xcorr01_noise_band', mfile, ...
        struct('fs', 44100, 'method', 1, 'time_skip', 0), tol, ...
        false, true, "", @(xx) FluctuationStrength_Osses2016(xx, 44100, 1, 0, false), ...
        fs_plan_(false), x));
    writer_f64(c, 'level3/fluctuation_strength_osses2016/xcorr01_noise_band/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'noise band fc 1 kHz BW 800 Hz: cross-correlation warning case'));

    % struct_opt.a0_type = 'fastl2007': the only option of struct_opt.
    x = synth_am(44100, 4, 1000, 4, 100, 70);   % > 2 s: stays method 1
    run_metric_case(c, mkcase_('fluctuation_strength_osses2016', 'a0f01_am4hz_70db_fastl2007', mfile, ...
        struct('fs', 44100, 'method', 1, 'time_skip', 0, 'a0_type', 'fastl2007'), tol, ...
        false, false, "", ...
        @(xx) FluctuationStrength_Osses2016(xx, 44100, 1, 0, false, struct('a0_type', 'fastl2007')), ...
        fs_plan_(false), x));
    writer_f64(c, 'level3/fluctuation_strength_osses2016/a0f01_am4hz_70db_fastl2007/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'AM tone fc 1 kHz fmod 4 Hz depth 100 pct, 70 dB SPL, 4 s, a0_type fastl2007'));
catch err
    clear cleanup
    rethrow(err);
end
end

function probes = fs_probes_()
g = 'if iFrame == nFrames || iFrame == ceil(nFrames/2) || iFrame == 1; ';
e = '; end';
probes = struct('anchor', {}, 'code', {});
probes(end+1) = struct('anchor', 'overlap = round(0.9*N);', ...
    'code', {'export_probe(''f1'', struct(''insig'', insig, ''fs'', fs, ''N'', N, ''overlap'', overlap));'});
probes(end+1) = struct('anchor', 'for iFrame = nFrames:-1:1', ...
    'code', {'if iFrame == nFrames; export_probe(''f2'', struct(''frames_dec'', insig(:, 1:10:end), ''shape_full'', size(insig), ''nFrames'', nFrames)); end'});
probes(end+1) = struct('anchor', ...
    '    signal = il_PeripheralHearingSystem_t(signal,fs,struct_opt); ', ...
    'code', {[g 'export_probe(''f3'', struct(''signal'', signal))' e]});
probes(end+1) = struct('anchor', ...
    '    [ei, ~, ~, clamp] = TerhardtExcitationPatterns(signal,fs,dBFS); % <clamp> requested, so the filterbank does not warn per frame', ...
    'code', {[g 'export_probe(''f4'', struct(''ei_slice'', ei(:, 1:min(256, end)), ''clamp_n'', clamp.n, ''clampLdB'', clamp.LdB, ''clampFreq'', clamp.freq))' e]});
probes(end+1) = struct('anchor', ...
    '    [mdept,hBPi] = il_modulation_depths(ei,model_par.Hweight);', ...
    'code', {[g 'export_probe(''f5'', struct(''mdept'', mdept, ''hBPi_slice'', hBPi(:, 1:min(256, end))))' e]});
probes(end+1) = struct('anchor', '    Ki = il_cross_correlation(hBPi);', ...
    'code', {[g 'export_probe(''f6'', struct(''Ki'', Ki))' e]});
probes(end+1) = struct('anchor', ...
    '    fi(iFrame,:)  = model_par.cal * fi_;', ...
    'code', {[g 'export_probe(''f7'', struct(''fi_'', fi_, ''fi_row'', fi(iFrame, :), ''fluct_i'', fluct(iFrame)))' e]});
end

function plan = fs_plan_(anchor)
M = 'psychoacoustic_metrics/FluctuationStrength_Osses2016/FluctuationStrength_Osses2016.m';
if anchor
    parts = [1 2 3];
else
    parts = 1;
end
p3 = {}; p4 = {}; p5 = {}; p6 = {}; p7 = {};
for k = 1:numel(parts)
    suf = '';
    if numel(parts) > 1
        suf = sprintf('_f%02d', parts(k));
    end
    p3{end+1} = pf(parts(k), 'signal', sprintf('probe_f3_peripheral%s.f64', suf), 'Pa', ...
        'post a0 FIR peripheral hearing system (time domain)', M, 'il_PeripheralHearingSystem_t'); %#ok<AGROW>
    p4{end+1} = pf(parts(k), 'ei_slice', sprintf('probe_f4_excitation%s.f64', suf), '', ...
        'excitation patterns slice (first 256 bins)', M, 'TerhardtExcitationPatterns'); %#ok<AGROW>
    p5{end+1} = pf(parts(k), 'mdept', sprintf('probe_f5_moddepth%s.f64', suf), '', ...
        'modulation depths', M, 'il_modulation_depths'); %#ok<AGROW>
    p6{end+1} = pf(parts(k), 'Ki', sprintf('probe_f6_crosscorr%s.f64', suf), '', ...
        'cross-correlation (2 x Chno)', M, 'il_cross_correlation'); %#ok<AGROW>
    p7{end+1} = pf(parts(k), 'fi_', sprintf('probe_f7_specific_raw%s.f64', suf), 'vacil/Bark', ...
        'raw specific FS of frame', M, 'il_specific_fluctuation'); %#ok<AGROW>
    p7{end+1} = pf(parts(k), 'fi_row', sprintf('probe_f7_specific%s.f64', suf), 'vacil/Bark', ...
        'calibrated specific FS row', M, 'il_specific_fluctuation'); %#ok<AGROW>
end
plan = [ ...
    plan1('f1', {pf(1, 'insig', 'probe_f1_insig44k1.f64', 'Pa', ...
        'signal post-resample-or-native 44.1 kHz', M, 'resample'), ...
        pf(1, 'fs', 'probe_f1_fs.f64', 'Hz', 'fs of analysis', M, 'resample'), ...
        pf(1, 'N', 'probe_f1_n.f64', '', 'window length N', M, 'buffer'), ...
        pf(1, 'overlap', 'probe_f1_overlap.f64', '', 'buffer overlap 0.9*N', M, 'buffer')}, ...
        struct('longdec', 100)), ...
    plan1('f2', {pf(1, 'frames_dec', 'probe_f2_frames.f64', 'Pa', ...
        'buffered frames, columns decimated x10 at capture', M, 'buffer'), ...
        pf(1, 'nFrames', 'probe_f2_nframes.f64', '', 'frame count', M, 'buffer')}, ...
        struct('nodecimate', true)), ...
    plan1('f3', p3, struct('nodecimate', true)), ...
    plan1('f4', p4, struct('nodecimate', true)), ...
    plan1('f5', p5, struct('nodecimate', true)), ...
    plan1('f6', p6, struct('nodecimate', true)), ...
    plan1('f7', p7, struct('nodecimate', true))];
end

% ========================================================================
% Section: level3/sharpness_din45692 (spec 5.6)
% =========================================================================

function sec_level3_sharpness(c)
mfile = 'psychoacoustic_metrics/Sharpness_DIN45692/Sharpness_DIN45692.m';
if ~should_run(c, 'level3/sharpness_din45692'), return; end
instrument(c, mfile, sharpness_probes_(), 'sharpness');
cleanup = onCleanup(@() instrument_clear());
try
    tol = 'S abs 0.01 acum';
    cases = { ...
        'nb01_1khz_60db', @(x) synth_noise_band(48000, 1, 1000, 160, 60, 42), ...
            'narrowband noise fc 1 kHz BW 160 Hz, 60 dB SPL'; ...
        'bb01_pink_60db', @(x) synth_pink(48000, 1, 60, 42), ...
            'broadband pink noise 60 dB SPL'; ...
        'lvl01_1khz_40db', @(x) synth_noise_band(48000, 1, 1000, 160, 40, 42), ...
            'narrowband noise 1 kHz, 40 dB SPL'; ...
        'lvl02_1khz_80db', @(x) synth_noise_band(48000, 1, 1000, 160, 80, 42), ...
            'narrowband noise 1 kHz, 80 dB SPL'; ...
        'wa01_pink_60db_aures', @(x) synth_pink(48000, 1, 60, 42), ...
            'pink noise 60 dB SPL, Aures weighting'; ...
        'wa02_pink_80db_aures', @(x) synth_pink(48000, 1, 80, 42), ...
            'pink noise 80 dB SPL, Aures weighting (level dependent)'; ...
        'wb01_pink_60db_bismarck', @(x) synth_pink(48000, 1, 60, 42), ...
            'pink noise 60 dB SPL, von Bismarck weighting'; ...
        'wb02_nb4k_60db_bismarck', @(x) synth_noise_band(48000, 1, 4000, 160, 60, 42), ...
            'narrowband noise 4 kHz, 60 dB SPL, von Bismarck weighting'};
    for k = 1:size(cases, 1)
        x = cases{k, 2}([]);
        wt = 'DIN45692';
        if contains(cases{k, 1}, 'aures'), wt = 'aures'; end
        if contains(cases{k, 1}, 'bismarck'), wt = 'bismarck'; end
        run_metric_case(c, mkcase_('sharpness_din45692', cases{k, 1}, mfile, ...
            struct('fs', 48000, 'weight_type', wt, 'LoudnessField', 0, ...
            'LoudnessMethod', 1, 'time_skip', 0), tol, ...
            k == 1, false, "", ...
            @(xx) Sharpness_DIN45692(xx, 48000, wt, 0, 1, 0, false, false), ...
            sharpness_plan_(), x));
        writer_f64(c, sprintf('level3/sharpness_din45692/%s/input.f64', cases{k, 1}), x, ...
            struct('unit', 'Pa', 'description', cases{k, 3}));
    end

    % diffuse field and time-varying loudness (added 2026-10-07: every sharpness golden
    % had LoudnessField 0 and LoudnessMethod 1)
    x = synth_pink(48000, 1, 60, 42);
    run_metric_case(c, mkcase_('sharpness_din45692', 'diff01_pink_60db', mfile, ...
        struct('fs', 48000, 'weight_type', 'DIN45692', 'LoudnessField', 1, ...
        'LoudnessMethod', 1, 'time_skip', 0), tol, false, false, "", ...
        @(xx) Sharpness_DIN45692(xx, 48000, 'DIN45692', 1, 1, 0, false, false), ...
        sharpness_plan_(), x));
    writer_f64(c, 'level3/sharpness_din45692/diff01_pink_60db/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'pink noise 60 dB SPL, diffuse field'));
    x = synth_am(48000, 2, 1000, 4, 100, 60);
    run_metric_case(c, mkcase_('sharpness_din45692', 'tv01_am4hz_1khz_60db', mfile, ...
        struct('fs', 48000, 'weight_type', 'DIN45692', 'LoudnessField', 0, ...
        'LoudnessMethod', 2, 'time_skip', 0.5), tol, false, false, "", ...
        @(xx) Sharpness_DIN45692(xx, 48000, 'DIN45692', 0, 2, 0.5, false, false), ...
        empty_plan_(), x));
    writer_f64(c, 'level3/sharpness_din45692/tv01_am4hz_1khz_60db/input.f64', x, ...
        struct('unit', 'Pa', 'description', '1 kHz tone 100 % AM at 4 Hz, 60 dB SPL, 2 s, time-varying'));
catch err
    clear cleanup
    rethrow(err);
end
end

function probes = sharpness_probes_()
probes = struct('anchor', {}, 'code', {});
probes(end+1) = struct('anchor', ...
    '    loudness_sones = sum(L.SpecificLoudness, 2).*0.10;', ...
    'code', {'export_probe(''s1'', struct(''SpecificLoudness'', L.SpecificLoudness, ''Loudness'', L.Loudness));'});
probes(end+1) = struct('anchor', ...
    '    loudness_sones = sum(L.InstantaneousSpecificLoudness, 2).*0.10;', ...
    'code', {'export_probe(''s1tv'', struct(''SpecificLoudness'', L.InstantaneousSpecificLoudness, ''Loudness'', L.InstantaneousLoudness));'});
probes(end+1) = struct('anchor', ...
    '        s = k * sum(SpecificLoudness.*g.*z.*0.10, 2) ./ loudness_sones;', ...
    'code', {'if exist(''s'', ''var''); export_probe(''s2'', struct(''g'', g, ''z'', z, ''k'', k, ''s'', s, ''SpecificLoudness'', SpecificLoudness)); end'});
end

function plan = sharpness_plan_()
M = 'psychoacoustic_metrics/Sharpness_DIN45692/Sharpness_DIN45692.m';
plan = [ ...
    plan1('s1', {pf(1, 'SpecificLoudness', 'probe_s1_loudness_used.f64', 'sone/Bark', ...
        'SpecificLoudness consumed by the sharpness integration', ...
        'psychoacoustic_metrics/Loudness_ISO532_1/Loudness_ISO532_1.m', 'method 1'), ...
        pf(1, 'Loudness', 'probe_s1_total.f64', 'sone', 'total loudness consumed', ...
        'psychoacoustic_metrics/Loudness_ISO532_1/Loudness_ISO532_1.m', 'method 1')}, ...
        struct()), ...
    plan1('s2', {pf(1, 'g', 'probe_s2_weight.f64', '', 'per-band weighting factor g(z)', M, ...
        'il_sharpWeights'), ...
        pf(1, 'z', 'probe_s2_barkaxis.f64', 'Bark', 'bark axis', M, 'linspace'), ...
        pf(1, 'k', 'probe_s2_k.f64', '', 'calibration constant k', M, 'k'), ...
        pf(1, 's', 'probe_s2_sharpness_raw.f64', 'acum', 'sharpness before OUT assignment', M, ...
        'DIN45692 integral'), ...
        pf(1, 'SpecificLoudness', 'probe_s2_specloudness.f64', 'sone/Bark', ...
        'specific loudness entering the integral', M, 'integral')}, struct('optional', true))];
end

% ========================================================================
% Section: level3/epnl_far_part36 (spec 5.7)
% =========================================================================

function sec_level3_epnl(c)
mfile = 'psychoacoustic_metrics/EPNL_FAR_Part36/EPNL_FAR_Part36.m';
if ~should_run(c, 'level3/epnl_far_part36'), return; end
instrument(c, mfile, epnl_probes_(), 'epnl');
cleanup = onCleanup(@() instrument_clear());
try
    tol = 'EPNL abs 0.1 EPNdB; PNL(T)/PNLT(T) abs 0.1 dB';

    % method 1 golden (non-normative input: ISO Annex B.5 airplane)
    src = fullfile(c.extras_root, 'sound_files', 'validation_SQAT_v1_0', ...
        'Loudness_ISO532_1', 'Test signal 14 (propeller-driven airplane).wav');
    [x, fs] = audioread(src);
    x = double(x(:, 1));
    run_metric_case(c, mkcase_('epnl_far_part36', 'm1_aircraft01_iso_b5', mfile, ...
        struct('fs', fs, 'method', 1, 'dt', 0.5, 'threshold', 10, ...
        'input_source', 'ISO 532-1:2017 Annex B.5 Test signal 14 (Zenodo 7933206)'), ...
        tol, true, false, "", ...
        @(xx) EPNL_FAR_Part36(xx, fs, 1, 0.5, 10, false), epnl_plan_(), x));
    writer_f64(c, 'level3/epnl_far_part36/m1_aircraft01_iso_b5/input.f64', x, ...
        struct('unit', 'Pa', 'description', 'propeller-driven airplane, Annex B.5 test signal 14'));

    % method 0 synthetic matrix [nTime x 24]
    nt = 20;
    tcol = (0:nt-1)' * 0.5;
    band_shape = 1 ./ (1 + (([1:24]' - 6) / 5).^2);
    SPLm = 70 + 25 * exp(-((tcol - 4) / 1.5).^2) * band_shape.';
    run_metric_case(c, mkcase_('epnl_far_part36', 'm0_matrix01_synthetic', mfile, ...
        struct('fs', 0, 'method', 0, 'dt', 0.5, 'threshold', 10, ...
        'input', 'synthetic 24-band SPL matrix, gaussian burst at t=2 s'), ...
        tol, false, false, "", ...
        @(xx) EPNL_FAR_Part36(xx, 0, 0, 0.5, 10, false), epnl_plan_m0_, SPLm));
    writer_f64(c, 'level3/epnl_far_part36/m0_matrix01_synthetic/input.f64', SPLm, ...
        struct('unit', 'dB', 'description', 'method 0: SPL[nTime x 24], 50 Hz..10 kHz, dt 0.5 s'));

    % method 0 wrong column count: warning + early return
    badcols = SPLm(:, 1:23);
    run_metric_case(c, mkcase_('epnl_far_part36', 'm0col01_23columns_warn', mfile, ...
        struct('fs', 0, 'method', 0, 'dt', 0.5, 'threshold', 10, ...
        'note', 'expected: warning + early return, OUT empty'), ...
        tol, false, true, "", ...
        @(xx) EPNL_FAR_Part36(xx, 0, 0, 0.5, 10, false), ...
        empty_plan_, badcols));
    writer_f64(c, 'level3/epnl_far_part36/m0col01_23columns_warn/input.f64', SPLm(:, 1:23), ...
        struct('unit', 'dB', 'description', '23-column matrix: nFreq=24 warning case'));

    % duration-correction warning: PNLT never decays below PNLTM-threshold
    x = synth_tone(48000, 10, 1000, 80);
    writer_f64(c, 'signals/synthetic/tone_1khz_80db_10s_48k.f64', x, ...
        struct('unit', 'Pa', 'description', 'constant 1 kHz tone 80 dB SPL, 10 s'));
    run_metric_case(c, mkcase_('epnl_far_part36', 'dur01_constant_tone_warn', mfile, ...
        struct('fs', 48000, 'method', 1, 'dt', 0.5, 'threshold', 10), ...
        tol, false, true, "", ...
        @(xx) EPNL_FAR_Part36(xx, 48000, 1, 0.5, 10, false), ...
        empty_plan_, x, ...
        struct('path', 'signals/synthetic/tone_1khz_80db_10s_48k.f64')));
catch err
    clear cleanup
    rethrow(err);
end
end

function probes = epnl_probes_()
probes = struct('anchor', {}, 'code', {});
probes(end+1) = struct('anchor', ...
    '        SPL_TOB_spectra = 10*log10( (Psquared_TOB+TINY_VALUE)/I_REF ); % main SPL[nTime*,nFreq] matrix used for the EPNL calculation', ...
    'code', {'export_probe(''n1'', struct(''SPL_TOB_spectra'', SPL_TOB_spectra));'});
probes(end+1) = struct('anchor', ...
    '        [PN, PNL, PNLM, PNLM_idx] = get_PNL(SPL_TOB_spectra);', ...
    'code', {'export_probe(''n2'', struct(''PN'', PN, ''PNL'', PNL, ''PNLM'', PNLM, ''PNLM_idx'', PNLM_idx));'});
probes(end+1) = struct('anchor', ...
    '        [PNLT, PNLTM, PNLTM_idx, ~] = get_PNLT(SPL_TOB_spectra, fc_TOB, PNL);', ...
    'code', {'export_probe(''n4'', struct(''PNLT'', PNLT, ''PNLTM'', PNLTM, ''PNLTM_idx'', PNLTM_idx, ''fc_TOB'', fc_TOB));'});
probes(end+1) = struct('anchor', ...
    '        [PNLT, PNLTM, PNLTM_idx, ~] = get_PNLT(SPL_TOB_spectra, fc_TOB, PNL);', ...
    'code', {'[pnlt2_, pnltm2_, idx2_, tc_] = get_PNLT(SPL_TOB_spectra, fc_TOB, PNL); export_probe(''n4b'', struct(''tcS'', tc_.S, ''tcdiff'', tc_.diff, ''tcdelS'', tc_.delS, ''tcSPLP'', tc_.SPLP, ''tcSP'', tc_.SP, ''tcSB'', tc_.SB, ''tcSPLPP'', tc_.SPLPP, ''tcF'', tc_.F, ''tcC'', tc_.C));'});
probes(end+1) = struct('anchor', ...
    '        [D, idx_t1, idx_t2] = get_Duration_Correction( PNLT, PNLTM, PNLTM_idx, dt, threshold );', ...
    'code', {'export_probe(''n5'', struct(''D'', D, ''idx_t1'', idx_t1, ''idx_t2'', idx_t2));'});
end

function plan = epnl_plan_()
M = 'psychoacoustic_metrics/EPNL_FAR_Part36/EPNL_FAR_Part36.m';
plan = [ ...
    plan1('n1', {pf(1, 'SPL_TOB_spectra', 'probe_n1_ob13_per_block.f64', 'dB', ...
        '1/3-octave SPL per dt block', 'sound_level_meter/Do_OB13_ISO532_1.m', 'per-block mean')}, ...
        struct('nodecimate', true)), ...
    plan1('n2', {pf(1, 'PN', 'probe_n2_noy_per_block.f64', 'noy', ...
        'NOY per block (table interpolation)', M, 'get_PNL'), ...
        pf(1, 'PNL', 'probe_n3_pnl.f64', 'PNdB', 'PNL per block', M, 'get_PNL'), ...
        pf(1, 'PNLM', 'probe_n3_pnlm.f64', 'PNdB', 'PNLmax', M, 'get_PNL'), ...
        pf(1, 'PNLM_idx', 'probe_n3_pnlm_idx.f64', '', 'index of PNLM', M, 'get_PNL')}, ...
        struct('nodecimate', true)), ...
    plan1('n4', {pf(1, 'PNLT', 'probe_n4_pnlt.f64', 'PNdB', ...
        'PNLT per block (tone corrected)', M, 'get_PNLT'), ...
        pf(1, 'PNLTM', 'probe_n4_pnltm.f64', 'PNdB', 'PNLTmax', M, 'get_PNLT'), ...
        pf(1, 'fc_TOB', 'probe_n4_fctob.f64', 'Hz', 'fc_TOB', M, 'get_PNLT')}, ...
        struct('nodecimate', true)), ...
    plan1('n4b', { ...
        pf(1, 'tcS', 'probe_n4b_s.f64', '', 'tone-correction verification: S', M, 'get_PNLT OUT'), ...
        pf(1, 'tcdiff', 'probe_n4b_diff.f64', '', 'tone-correction verification: diff', M, 'get_PNLT OUT'), ...
        pf(1, 'tcdelS', 'probe_n4b_dels.f64', '', 'tone-correction verification: delS', M, 'get_PNLT OUT'), ...
        pf(1, 'tcSPLP', 'probe_n4b_splp.f64', 'dB', 'tone-correction verification: SPLP', M, 'get_PNLT OUT'), ...
        pf(1, 'tcSP', 'probe_n4b_sp.f64', 'dB', 'tone-correction verification: SP', M, 'get_PNLT OUT'), ...
        pf(1, 'tcSB', 'probe_n4b_sb.f64', 'dB', 'tone-correction verification: SB', M, 'get_PNLT OUT'), ...
        pf(1, 'tcSPLPP', 'probe_n4b_splpp.f64', 'dB', 'tone-correction verification: SPLPP', M, 'get_PNLT OUT'), ...
        pf(1, 'tcF', 'probe_n4b_f.f64', 'Hz', 'tone-correction verification: F', M, 'get_PNLT OUT'), ...
        pf(1, 'tcC', 'probe_n4b_c.f64', 'dB', 'tone-correction verification: C', M, 'get_PNLT OUT')}, ...
        struct('nodecimate', true)), ...
    plan1('n5', {pf(1, 'D', 'probe_n5_duration_correction.f64', 'dB', ...
        'duration correction D', M, 'get_Duration_Correction'), ...
        pf(1, 'idx_t1', 'probe_n5_idxt1.f64', '', 'integration start index', M, ...
        'get_Duration_Correction'), ...
        pf(1, 'idx_t2', 'probe_n5_idxt2.f64', '', 'integration end index', M, ...
        'get_Duration_Correction')}, struct('nodecimate', true))];
end

function plan = epnl_plan_m0_()
full = epnl_plan_();
plan = full(2:5);
end

function plan = empty_plan_()
plan = struct('name', '', 'files', {}, 'nodecimate', true, 'longdec', 0, 'complex', false);
end

% ========================================================================
% Section: level3/psychoacoustic_annoyance (spec 5.8)
% =========================================================================

function sec_level3_pa(c)
if ~should_run(c, 'level3/psychoacoustic_annoyance'), return; end
mW = 'psychoacoustic_metrics/PsychoacousticAnnoyance_Widmann1992/PsychoacousticAnnoyance_Widmann1992.m';
mZ = 'psychoacoustic_metrics/PsychoacousticAnnoyance_Zwicker1999/PsychoacousticAnnoyance_Zwicker1999.m';
mM = 'psychoacoustic_metrics/PsychoacousticAnnoyance_More2010/PsychoacousticAnnoyance_More2010.m';
mD = 'psychoacoustic_metrics/PsychoacousticAnnoyance_Di2016/PsychoacousticAnnoyance_Di2016.m';
instrument(c, mW, pa_probes_(false), 'pa_widmann');
instrument(c, mM, pa_probes_(true), 'pa_more');
instrument(c, mD, pa_probes_(true), 'pa_di');
cleanup = onCleanup(@() instrument_clear());
try
    tol = 'PA 2 pct rel';
    calm = synth_pink(48000, 5, 60, 42);
    aggressive = synth_am(48000, 5, 1000, 70, 100, 72) + ...
        synth_noise_band(48000, 5, 4000, 2000, 68, 43);
    writer_f64(c, 'signals/synthetic/pa_calm_pink_5s_48k.f64', calm, ...
        struct('unit', 'Pa', 'description', 'PA calm input: pink noise 60 dB SPL, 5 s, rng(42)'));
    writer_f64(c, 'signals/synthetic/pa_aggressive_am_noise_5s_48k.f64', aggressive, ...
        struct('unit', 'Pa', 'description', 'PA aggressive input: AM 70 Hz tone 72 dB + band noise 68 dB, 5 s'));
    ref_calm = struct('path', 'signals/synthetic/pa_calm_pink_5s_48k.f64');
    ref_aggr = struct('path', 'signals/synthetic/pa_aggressive_am_noise_5s_48k.f64');
    models = { ...
        'widmann1992', mW, @(x) PsychoacousticAnnoyance_Widmann1992(x, 48000, 0, 0, false, false), false; ...
        'zwicker1999', mZ, @(x) PsychoacousticAnnoyance_Zwicker1999(x, 48000, 0, 0, false, false), false; ...
        'more2010', mM, @(x) PsychoacousticAnnoyance_More2010(x, 48000, 0, 0, false, false), true; ...
        'di2016', mD, @(x) PsychoacousticAnnoyance_Di2016(x, 48000, 0, 0, false, false), true};
    for k = 1:size(models, 1)
        tag = models{k, 1};
        fcn = models{k, 3};
        plan = pa_plan_(models{k, 4});
        run_metric_case(c, mkcase_('psychoacoustic_annoyance', ...
            sprintf('%s_calm_pink', tag), models{k, 2}, ...
            struct('fs', 48000, 'LoudnessField', 0, 'time_skip', 0), ...
            tol, strcmp(tag, 'widmann1992'), false, "", fcn, plan, calm, ref_calm));
        run_metric_case(c, mkcase_('psychoacoustic_annoyance', ...
            sprintf('%s_aggressive_am_noise', tag), models{k, 2}, ...
            struct('fs', 48000, 'LoudnessField', 0, 'time_skip', 0), ...
            tol, false, false, "", fcn, plan, aggressive, ref_aggr));
    end
    % diffuse field (added 2026-10-07: every annoyance golden had LoudnessField 0)
    diffuse = { ...
        'widmann1992', mW, @(x) PsychoacousticAnnoyance_Widmann1992(x, 48000, 1, 0, false, false), false; ...
        'zwicker1999', mZ, @(x) PsychoacousticAnnoyance_Zwicker1999(x, 48000, 1, 0, false, false), false; ...
        'more2010', mM, @(x) PsychoacousticAnnoyance_More2010(x, 48000, 1, 0, false, false), true; ...
        'di2016', mD, @(x) PsychoacousticAnnoyance_Di2016(x, 48000, 1, 0, false, false), true};
    for k = 1:size(diffuse, 1)
        run_metric_case(c, mkcase_('psychoacoustic_annoyance', ...
            sprintf('%s_diff01_aggressive_am_noise', diffuse{k, 1}), diffuse{k, 2}, ...
            struct('fs', 48000, 'LoudnessField', 1, 'time_skip', 0), ...
            tol, false, false, "", diffuse{k, 3}, pa_plan_(diffuse{k, 4}), aggressive, ref_aggr));
    end
    % signals shorter than 2 s: the models compute only the scalar annoyance (the
    % stationary FS path), no time-varying probes exist there (added after F0.7 for F8)
    calm_s = synth_pink(48000, 1.5, 60, 42);
    aggr_s = synth_am(48000, 1.5, 1000, 70, 100, 72) + ...
        synth_noise_band(48000, 1.5, 4000, 2000, 68, 43);
    writer_f64(c, 'signals/synthetic/pa_calm_pink_1p5s_48k.f64', calm_s, ...
        struct('unit', 'Pa', 'description', 'PA short calm input: pink noise 60 dB SPL, 1.5 s, rng(42)'));
    writer_f64(c, 'signals/synthetic/pa_aggressive_am_noise_1p5s_48k.f64', aggr_s, ...
        struct('unit', 'Pa', 'description', 'PA short aggressive input: AM 70 Hz tone 72 dB + band noise 68 dB, 1.5 s'));
    ref_calm_s = struct('path', 'signals/synthetic/pa_calm_pink_1p5s_48k.f64');
    ref_aggr_s = struct('path', 'signals/synthetic/pa_aggressive_am_noise_1p5s_48k.f64');
    for k = 1:size(models, 1)
        tag = models{k, 1};
        fcn = models{k, 3};
        warns = strcmp(tag, 'di2016'); % Di raises warning(); the others only print
        run_metric_case(c, mkcase_('psychoacoustic_annoyance', ...
            sprintf('%s_short_calm_pink', tag), models{k, 2}, ...
            struct('fs', 48000, 'LoudnessField', 0, 'time_skip', 0), ...
            tol, false, warns, "", fcn, empty_plan_(), calm_s, ref_calm_s));
        run_metric_case(c, mkcase_('psychoacoustic_annoyance', ...
            sprintf('%s_short_aggressive_am_noise', tag), models{k, 2}, ...
            struct('fs', 48000, 'LoudnessField', 0, 'time_skip', 0), ...
            tol, false, warns, "", fcn, empty_plan_(), aggr_s, ref_aggr_s));
    end
catch err
    clear cleanup
    rethrow(err);
end
end

% ========================================================================
% Section: level3/do_slm (added 2026-10-07: Do_SLM had no level-3 golden; one case per
% frequency weighting and per time weighting the port implements, B and D excluded)
% =========================================================================

function sec_level3_slm(c)
mfile = 'sound_level_meter/Do_SLM.m';
if ~should_run(c, 'level3/do_slm'), return; end
tol = 'L abs 1e-9 dB';
burst = synth_tone(48000, 1, 4000, 80) .* ((0:47999)' / 48000 >= 0.2 & (0:47999)' / 48000 < 0.21);
cases = { ...
    'a_f_tone1k_70db', 'A', 'f', synth_tone(48000, 1, 1000, 70), '1 kHz tone 70 dB SPL, 1 s'; ...
    'c_s_pink_70db', 'C', 's', synth_pink(48000, 2, 70, 42), 'pink noise 70 dB SPL, 2 s, rng(42)'; ...
    'z_i_toneburst_4k', 'Z', 'i', burst, '10 ms 4 kHz burst at 0.2 s, 80 dB SPL, in 1 s of silence'};
for k = 1:size(cases, 1)
    x = cases{k, 4};
    wf = cases{k, 2};
    wt = cases{k, 3};
    run_metric_case(c, mkcase_('do_slm', cases{k, 1}, mfile, ...
        struct('fs', 48000, 'weight_freq', wf, 'weight_time', wt, 'dBFS', 94), tol, ...
        k == 1, false, "", @(xx) slm_out_(xx, 48000, wf, wt), empty_plan_(), x));
    writer_f64(c, sprintf('level3/do_slm/%s/input.f64', cases{k, 1}), x, ...
        struct('unit', 'Pa', 'description', cases{k, 5}));
end
end

function OUT = slm_out_(x, fs, wf, wt)
% Do_SLM returns [outsig_dB, dBFS]; run_metric_case writes the fields of a struct
[L, d] = Do_SLM(x, fs, wf, wt, 94);
OUT = struct('outsig_dB', L, 'dBFS', d);
end

function probes = pa_probes_(has_tonality)

probes = struct('anchor', {}, 'code', {});
if has_tonality
    probes(end+1) = struct('anchor', ...
        '    tonality=interp1(K.time,K.InstantaneousTonality,L.time,''spline''); % interpolation to have the same time vector as loudness metric', ...
        'code', {'export_probe(''pa2t'', struct(''tonality'', tonality));'});
else
end

probes(end+1) = struct('anchor', ...
    '    roughness=interp1(R.time,R.InstantaneousRoughness,L.time,''spline''); % interpolation to have the same time vector as loudness metric', ...
    'code', {'export_probe(''pa2r'', struct(''roughness'', roughness));'});
probes(end+1) = struct('anchor', ...
    '    fluctuation=interp1(FS.time,FS.InstantaneousFluctuationStrength,L.time,''spline''); % interpolation to have the same time vector as loudness metric', ...
    'code', {'export_probe(''pa2f'', struct(''fluctuation'', fluctuation));'});
probes(end+1) = struct('anchor', ...
    '    OUT.wfr = wfr;     % OUTPUT: fluctuation strength and sharpness weighting function (not squared)', ...
    'code', {'export_probe(''pa1wfr'', struct(''wfr'', wfr));'});
probes(end+1) = struct('anchor', ...
    '    OUT.ws = ws;       % OUTPUT: sharpness and loudness weighting function (not squared)', ...
    'code', {'export_probe(''pa1ws'', struct(''ws'', ws));'});
end

function plan = pa_plan_(has_tonality)
plan = [ ...
    plan1('pa2r', {pf(1, 'roughness', 'probe_pa2_interp_roughness.f64', 'asper', ...
        'spline-interpolated roughness on the loudness time base', ...
        'psychoacoustic_metrics/PsychoacousticAnnoyance_*/...', 'interp1 spline')}, ...
        struct('nodecimate', true)), ...
    plan1('pa2f', {pf(1, 'fluctuation', 'probe_pa2_interp_fluctuation.f64', 'vacil', ...
        'spline-interpolated fluctuation strength', ...
        'psychoacoustic_metrics/PsychoacousticAnnoyance_*/...', 'interp1 spline')}, ...
        struct('nodecimate', true)), ...
    plan1('pa1wfr', {pf(1, 'wfr', 'probe_pa1_wfr.f64', '', 'roughness/FS weight term', ...
        'psychoacoustic_metrics/PsychoacousticAnnoyance_*/...', 'wfr')}, ...
        struct('nodecimate', true)), ...
    plan1('pa1ws', {pf(1, 'ws', 'probe_pa1_ws.f64', '', 'sharpness weight term', ...
        'psychoacoustic_metrics/PsychoacousticAnnoyance_*/...', 'ws')}, ...
        struct('nodecimate', true))];
if has_tonality
    plan = [plan, ...
        plan1('pa2t', {pf(1, 'tonality', 'probe_pa2_interp_tonality.f64', 't.u.', ...
        'spline-interpolated tonality', ...
        'psychoacoustic_metrics/PsychoacousticAnnoyance_*/...', 'interp1 spline')}, ...
        struct('nodecimate', true))];
else
end

end

% ========================================================================
% Section: level3/modulation_bitwise (spec 5.9 / 8.1, curated gate cases)
% =========================================================================

function sec_level3_bitwise(c)
if ~should_run(c, 'level3/modulation_bitwise'), return; end
M_R = 'psychoacoustic_metrics/Roughness_Daniel1997/Roughness_Daniel1997.m';
M_FS = 'psychoacoustic_metrics/FluctuationStrength_Osses2016/FluctuationStrength_Osses2016.m';
tolR = 'rel 1e-9 with abs floor 1e-9 (spec section 10 bitwise row)';

% FS reference signal copy (44.1 kHz) reused as input
src_fs = fullfile(c.sqat_root, 'sound_files', 'reference_signals', ...
    'RefSignal_FluctuationStrength_Osses2016.wav');
writer_copy(c, string(src_fs), 'signals/reference/fs_ref_signal_44k1.wav');
[xfs, fs_fs] = audioread(src_fs);
xfs = double(xfs(:, 1));

[xref, fsr] = audioread(fullfile(c.sqat_root, 'sound_files', ...
    'reference_signals', 'RefSignal_Roughness_Daniel1997.wav'));
xref = double(xref(:, 1));

R = @(x, fs) Roughness_Daniel1997(x, fs, 0, false);
F = @(x, fs, m) FluctuationStrength_Osses2016(x, fs, m, 0, false);

% ---- Roughness cases ------------------------------------------------------
bw(c, 'r01_ref_48k', M_R, @(v) R(v, fsr), xref, fsr, false, "", tolR, ...
    struct('path', 'signals/reference/refsignal_daniel_5s.wav', 'channel', 1), ...
    'RefSignal_Roughness_Daniel1997, native 48 kHz');

S = load(fullfile(c.extras_root, 'sound_files', 'validation_SQAT_v1_0', ...
    'Roughness_Daniel1997', 'vary_modulation_freq_fmod_1khz.mat'));
if isfield(S, 'fs'), fsm1 = S.fs; else, fsm1 = 48000; end
xrow = S.(first_field_(S))(1, :).';
bw(c, 'r02_mat_vary_fmod_1khz_row1', M_R, @(v) R(v, fsm1), xrow, fsm1, false, "", tolR, ...
    struct('path', 'validation/roughness_daniel1997/row_vary_modulation_freq_fmod_1khz_row1.f64'), ...
    'row 1 of vary_modulation_freq_fmod_1khz.mat');

S = load(fullfile(c.extras_root, 'sound_files', 'validation_SQAT_v1_0', ...
    'Roughness_Daniel1997', 'FM_fmod_fc_1600hz.mat'));
xrow = S.(first_field_(S))(1, :).';
writer_f64(c, 'validation/roughness_daniel1997/row_fm_fmod_fc_1600hz_row1.f64', xrow, ...
    struct('unit', 'Pa', 'description', 'row 1 of FM_fmod_fc_1600hz.mat, fs 48 kHz'));
bw(c, 'r03_mat_fm_fmod_fc_1600hz_row1', M_R, @(v) R(v, 48000), xrow, 48000, false, "", ...
    tolR, struct('path', 'validation/roughness_daniel1997/row_fm_fmod_fc_1600hz_row1.f64'), ...
    'row 1 of FM_fmod_fc_1600hz.mat');

S = load(fullfile(c.extras_root, 'sound_files', 'validation_SQAT_v1_0', ...
    'Roughness_Daniel1997', 'FM_fmod70_fc1600hz_fdev800_SPL40-80.mat'));
xrow = S.(first_field_(S))(1, :).';
bw(c, 'r04_mat_fm_fmod70_spl4080_row1', M_R, @(v) R(v, 48000), xrow, 48000, false, "", ...
    tolR, struct('path', 'validation/roughness_daniel1997/row_fm_fmod70_fc1600hz_fdev800_row1.f64'), ...
    'row 1 of FM_fmod70_fc1600hz_fdev800_SPL40-80.mat');

ref_ts = struct('path', 'signals/reference/trainstation_10s_stereo.wav');
bw(c, 'r05_trainstation10s_ch1', M_R, @(v) R(v, 48000), ts10_(c, 1), 48000, ...
    false, "", tolR, setfield(ref_ts, 'channel', 1), ...
    'TrainStation 10 s channel 1'); %#ok<SFLD>
bw(c, 'r06_trainstation10s_ch2', M_R, @(v) R(v, 48000), ts10_(c, 2), 48000, ...
    false, "", tolR, setfield(ref_ts, 'channel', 2), ...
    'TrainStation 10 s channel 2'); %#ok<SFLD>

bw(c, 'r07_fsref_44k1_via_roughness', M_R, @(v) R(v, fs_fs), xfs, fs_fs, ...
    false, "", tolR, struct('path', 'signals/reference/fs_ref_signal_44k1.wav', 'channel', 1), ...
    'FS reference signal through Roughness (44.1 kHz native window 8820)');

x32 = resample(ts10_(c, 1), 2, 3);
bw(c, 'r08_trainstation10s_32k', M_R, @(v) R(v, 32000), x32, 32000, false, "", tolR, [], ...
    'TrainStation 10 s ch1 resampled 2/3 to 32 kHz (resample path)');
writer_f64(c, 'level3/modulation_bitwise/r08_trainstation10s_32k/input.f64', x32, ...
    struct('unit', 'Pa', 'description', 'TrainStation ch1 at 32 kHz via resample(x,2,3)'));

xsil = [zeros(48000, 1); xref(1:round(2*48000))];
bw(c, 'r09_silence_1s_plus_ref', M_R, @(v) R(v, 48000), xsil, 48000, false, "", tolR, [], ...
    '1 s silence + first 2 s of the Daniel ref (windows without component)');
writer_f64(c, 'level3/modulation_bitwise/r09_silence_1s_plus_ref/input.f64', xsil, ...
    struct('unit', 'Pa', 'description', 'silence + ref concatenation'));

xclamp = synth_tone(48000, 2, 1000, 130);
bw(c, 'r10_tone130db_clamp', M_R, @(v) R(v, 48000), xclamp, 48000, true, ...
    'SQAT:Roughness:TerhardtSlopeClamped', tolR, [], ...
    '1 kHz 130 dB SPL: Terhardt clamp warning');
writer_f64(c, 'level3/modulation_bitwise/r10_tone130db_clamp/input.f64', xclamp, ...
    struct('unit', 'Pa', 'description', 'clamp warning case'));

x16 = synth_am(48000, 2, 1000, 4, 100, 60) + synth_tone(48000, 2, 16000, 100);
bw(c, 'r11_16khz_100db_error', M_R, @(v) R(v, 48000), x16, 48000, true, "", tolR, [], ...
    'AM tone + 16 kHz 100 dB: baseline error (growing array)');
writer_f64(c, 'level3/modulation_bitwise/r11_16khz_100db_error/input.f64', x16, ...
    struct('unit', 'Pa', 'description', 'error case: component above the last band'));

x18 = synth_am(48000, 2, 1000, 4, 100, 60) + synth_tone(48000, 2, 18000, 115);
bw(c, 'r12_18khz_115db_runs', M_R, @(v) R(v, 48000), x18, 48000, false, "", tolR, [], ...
    'AM tone + 18 kHz 115 dB: runs (outside modeled range, no error)');
writer_f64(c, 'level3/modulation_bitwise/r12_18khz_115db_runs/input.f64', x18, ...
    struct('unit', 'Pa', 'description', 'above last channel, runs'));

% ---- Fluctuation Strength cases -------------------------------------------
bw(c, 'fs01_ref_44k1_m1', M_FS, @(v) F(v, fs_fs, 1), xfs, fs_fs, false, "", tolR, ...
    struct('path', 'signals/reference/fs_ref_signal_44k1.wav', 'channel', 1), ...
    'FS ref, method 1');
bw(c, 'fs02_ref_44k1_m0', M_FS, @(v) F(v, fs_fs, 0), xfs, fs_fs, false, "", tolR, ...
    struct('path', 'signals/reference/fs_ref_signal_44k1.wav', 'channel', 1), ...
    'FS ref, method 0');
bw(c, 'fs03_trainstation10s_ch1_m1', M_FS, @(v) F(v, 48000, 1), ts10_(c, 1), 48000, ...
    false, "", tolR, setfield(ref_ts, 'channel', 1), ...
    'TrainStation 10 s ch1, method 1'); %#ok<SFLD>

x16fs = synth_am(44100, 2, 1000, 4, 100, 60) + synth_tone(44100, 2, 16000, 100);
bw(c, 'fs04_16khz_100db', M_FS, @(v) F(v, 44100, 1), x16fs, 44100, false, "", tolR, [], ...
    'AM tone + 16 kHz 100 dB');
writer_f64(c, 'level3/modulation_bitwise/fs04_16khz_100db/input.f64', x16fs, ...
    struct('unit', 'Pa', 'description', '16 kHz component at 100 dB'));

x16fs2 = synth_am(44100, 2, 1000, 4, 100, 60) + synth_tone(44100, 2, 16000, 120);
bw(c, 'fs05_16khz_120db', M_FS, @(v) F(v, 44100, 1), x16fs2, 44100, false, "", tolR, [], ...
    'AM tone + 16 kHz 120 dB');
writer_f64(c, 'level3/modulation_bitwise/fs05_16khz_120db/input.f64', x16fs2, ...
    struct('unit', 'Pa', 'description', '16 kHz component at 120 dB'));

xclampfs = synth_tone(44100, 2, 1000, 130);
bw(c, 'fs06_tone130db_clamp', M_FS, @(v) F(v, 44100, 1), xclampfs, 44100, true, ...
    'SQAT:FluctuationStrength:TerhardtSlopeClamped', tolR, [], ...
    '1 kHz 130 dB SPL: FS clamp warning');
writer_f64(c, 'level3/modulation_bitwise/fs06_tone130db_clamp/input.f64', xclampfs, ...
    struct('unit', 'Pa', 'description', 'FS clamp warning case'));
end

function bw(c, name, mfile, fcn, x, fs, warn_case, wid, tol, input_ref, note)
cfg = struct('metric', 'modulation_bitwise', 'name', name, 'm_file', mfile, ...
    'params', struct('fs', fs, 'note', note), 'tol', tol, ...
    'anchor', true, 'warn_case', warn_case, 'expect_warn_id', wid, ...
    'make_fcn', @() fcn(x), 'probe_plan', empty_plan_);
if ~isempty(input_ref)
    cfg.input_ref = input_ref;
end
run_metric_case(c, cfg);
end

% ========================================================================
% Finalize: manifest, budget, self-verify (spec 3, 11, 12)
% =========================================================================

function finalize_export(c)
% the disk is the single source of truth: in real runs the manifest is
% built from a recursive scan of the tree (chunked appends keep their
% files); in dry-run the in-memory registry provides the estimate
if c.dryrun
    ppall = {c.reg.info.path};
    bb = [c.reg.info.bytes];
    fprintf('%s: dry-run plan: %d files, %.2f MB estimated (budget %g MB)\n', ...
        mfilename, numel(ppall), sum(bb)/1024/1024, c.budget_mb);
    if sum(bb) > c.budget_mb*1024^2
        fprintf('  WARNING: estimate exceeds the budget; top offenders:\n');
        [~, bidx] = sort(bb, 'descend');
        for k = 1:min(25, numel(bidx))
            fprintf('   %8.3f MB  %s\n', bb(bidx(k))/1024/1024, ppall{bidx(k)});
        end
    end
    return;
end
ppall = tree_files_(c.out_root);
ppall(strcmp(ppall, 'manifest.json')) = [];   % regenerated below, never listed
pc = strcat(pathsep, '.complete'); %#ok<NASGU>
ppall(endsWith(ppall, '/.complete') | strcmp(ppall, '.complete')) = [];
srt = sort(ppall);
dupmask = [false, strcmp(srt(2:end), srt(1:end-1)).'];
if any(dupmask)
    error('export_goldens:dup', 'duplicate files on disk: %s', srt(find(dupmask, 1)));
end
info = struct('path', {}, 'sha256', {}, 'bytes', {});
for i = 1:numel(srt)
    p = fullfile(c.out_root, srt{i});
    info(i) = struct('path', srt{i}, 'sha256', sha256_file(p), ...
        'bytes', dir(p).bytes); %#ok<AGROW>
end
v = ver('signal');
if isempty(v)
    error('export_goldens:spt', 'Signal Processing Toolbox is required by the baseline');
end
man = struct();
man.matlab_version = "R" + string(version('-release'));
man.signal_processing_toolbox_version = string(v(1).Version);
man.matlab_license = c.matlab_license;
man.sqat_commit = c.baseline_sha;
man.generated_at = string(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
for i = 1:numel(info)
    man.files(i) = struct('path', string(info(i).path), ...
        'sha256', string(info(i).sha256), 'bytes', uint64(info(i).bytes)); %#ok<AGROW>
end
abs_m = fullfile(c.out_root, 'manifest.json');
fid = fopen(abs_m, 'w');
fwrite(fid, uint8(jsonencode(man, 'PrettyPrint', true)));
fwrite(fid, uint8(newline));
fclose(fid);
% resume markers are internal: remove them so the committed tree is clean
mk_files = tree_files_(c.out_root);
for mi = 1:numel(mk_files)
    if endsWith(mk_files{mi}, '/.complete') || strcmp(mk_files{mi}, '.complete')
        delete(fullfile(c.out_root, mk_files{mi}));
    end
end
total = sum([info.bytes]);
fprintf('%s: %d data files, %.2f MB (budget %g MB)\n', mfilename, ...
    numel(info), total/1024/1024, c.budget_mb);
if total > c.budget_mb*1024^2
    error('export_goldens:budget', ...
        'fixture budget exceeded: %.2f MB > %g MB (spec section 11 relief valves)', ...
        total/1024/1024, c.budget_mb);
end
% self-verify (spec 12 item 12): re-read the manifest and re-checksum the
% tree; the scan above already excludes orphans by construction
mk = jsondecode(fileread(abs_m));
if numel(mk.files) ~= numel(info)
    error('export_goldens:selfverify', 'manifest file count mismatch');
end
for i = 1:numel(info)
    h = sha256_file(fullfile(c.out_root, info(i).path));
    if ~strcmp(h, mk.files(i).sha256)
        error('export_goldens:selfverify', 'checksum drift on %s', info(i).path);
    end
end
fprintf('%s: self-verify OK (%d files checksummed, no orphans)\n', ...
    mfilename, numel(info));
end

function rel = tree_files_(root)
d = dir(fullfile(root, '**', '*'));
d = d(~[d.isdir]);
n = numel(d);
rel = cell(n, 1);
r = char(root);
for i = 1:n
    p = fullfile(d(i).folder, d(i).name);
    rel{i} = strrep(p(1 + numel(r) + 1:end), filesep, '/');
end
end

% ========================================================================
% Determinism second pass (spec 12 item 10)
% =========================================================================

function determinism_pass2(opts, c) %#ok<INUSD>
tmp_out = string(fullfile(tempdir(), 'sqat_export_pass2'));
if isfolder(tmp_out)
    rmdir(tmp_out, 's');
end
fprintf('%s: determinism second pass into %s\n', mfilename, tmp_out);
o = opts;
o.out_dir = tmp_out;
o.internal_pass2 = true;
o.skip_pass2 = true;
o.dryrun = false;
o.budget_mb = c.budget_mb;
export_goldens(o);

A = tree_files_(c.out_root);
B = tree_files_(tmp_out);
if ~isequal(A, B)
    error('export_goldens:determinism', ...
        'file sets differ between passes: %d vs %d files', numel(A), numel(B));
end
for k = 1:numel(A)
    rel = A{k};
    if strcmp(rel, 'manifest.json')
        continue;
    end
    ha = sha256_file(fullfile(c.out_root, rel));
    hb = sha256_file(fullfile(tmp_out, rel));
    if ~strcmp(ha, hb)
        error('export_goldens:determinism', 'byte drift on %s', rel);
    end
end
% manifest: files[] (checksums) must match; generated_at differs by design
ma = jsondecode(fileread(fullfile(c.out_root, 'manifest.json')));
mb = jsondecode(fileread(fullfile(tmp_out, 'manifest.json')));
if ~isequal(ma.files, mb.files)
    error('export_goldens:determinism', 'manifest checksum tables differ');
end
rmdir(tmp_out, 's');
fprintf('%s: determinism OK (%d files byte-identical)\n', mfilename, numel(A));
end
