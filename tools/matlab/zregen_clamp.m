function zregen_clamp(out_root, full)
% zregen_clamp()                     committed tree, ei columns decimated x4
% zregen_clamp(out_root, true)      undecimated set (docs/regen-fixtures.md section 7)
if nargin < 1, out_root = fullfile('crates', 'sqat-fixtures', 'data'); end
if nargin < 2, full = false; end
% regenerate the terhardt clamp golden with a properly calibrated 130 dB
% spectrum (tester finding 2, F1c): the F0.7 export fed the raw window fft
addpath('tools/matlab');
SQ = getenv('SQAT_ROOT');
addpath(fullfile(SQ, 'utilities'));
fs = 48000;
x = sqrt(2) * 2e-5 * 10^(130/20) * sin(2*pi*1000*(0:9599)'/fs);
win = blackman(9600, 'periodic');
params = Terhardt_filterbank_params(9600, 48000);
% calibration chain of Roughness_Daniel1997.m L179-211 (AmpCal + a0)
L_cal = 20*log10(1/20e-6) - 20*log10(sqrt(2));
AmpCal = 10^(L_cal/20) * 2 / (9600 * mean(win));
[~, ~, a0_qb] = calculate_a0(48000, 9600, 'fastl2007');
a0spec = ones(1, 9600);
a0spec(params.qb) = a0_qb;
dataIn = x(1:9600) .* win;
FreqIn = a0spec .* fft(dataIn * AmpCal).';   % transpose to 1xN: avoid implicit broadcast to NxN
Lg = abs(FreqIn(params.qb));
LdB = 20*log10(Lg);
st = -24 - 230./params.freqs + 0.2*LdB;
[mx, im] = max(LdB);
fprintf('max LdB = %.2f dB @ %.0f Hz; clamped = %d\n', mx, params.freqs(im), nnz(st >= 0));
d = fullfile(out_root, 'level1', 'util');
fid = fopen(fullfile(d, 'terhardt_clamp_1khz_130db_input_spec_re.f64'), 'w', 'ieee-le');
fwrite(fid, real(FreqIn), 'double'); fclose(fid);
fid = fopen(fullfile(d, 'terhardt_clamp_1khz_130db_input_spec_im.f64'), 'w', 'ieee-le');
fwrite(fid, imag(FreqIn), 'double'); fclose(fid);
lastwarn('', '');
ei = Terhardt_filterbank(FreqIn, params);
[msg, wid] = lastwarn;
fprintf('warn id=[%s] msg=[%.60s]\n', wid, msg);
info = struct('n_components', nnz(LdB > params.MinExcdB), ...
    'clamp', struct('n', nnz(st >= 0), 'LdB', mx, 'freq', params.freqs(im)));
step = 4;
if full, step = 1; end
ei_dec = ei(:, 1:step:end);
if full
    m = struct('shape', size(ei_dec), 'dtype', "f64", 'order', "C", 'unit', "", ...
        'description', "Terhardt_filterbank excitation patterns ei [Chno x N]", 'source', struct('m_file', "", 'stage', ""));
    fid = fopen(fullfile(d, 'terhardt_clamp_1khz_130db_ei.f64.meta.json'), 'w');
    fwrite(fid, uint8(jsonencode(m, 'PrettyPrint', true))); fclose(fid);
end
fid = fopen(fullfile(d, 'terhardt_clamp_1khz_130db_ei.f64'), 'w', 'ieee-le');
fwrite(fid, reshape(permute(ei_dec, [2 1]), 1, []), 'double'); fclose(fid);
fid = fopen(fullfile(d, 'terhardt_clamp_1khz_130db_info.json'), 'w');
fwrite(fid, uint8(jsonencode(info, 'PrettyPrint', true)));
fwrite(fid, uint8(newline)); fclose(fid);
fid = fopen(fullfile(d, 'terhardt_clamp_1khz_130db_warnings.json'), 'w');
fwrite(fid, uint8(jsonencode(struct('warnings', {{struct('id', string(wid), 'message', string(msg))}}), 'PrettyPrint', true)));
fwrite(fid, uint8(newline)); fclose(fid);
% refresh the manifest for the 5 touched files (disk-scan rebuild)
export_goldens('sqat_root', SQ, ...
    'extras_root', getenv('SQAT_EXTRAS_ROOT'), ...
    'out_dir', out_root, 'budget_mb', 100000, 'skip_pass2', true, 'manifest_only', true);
disp('regen ok');
end
