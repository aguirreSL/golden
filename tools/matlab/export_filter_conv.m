% Records MATLAB's filter(b, 1, x) for long FIR filters and the fluctuation-strength FIR design
% (calculate_a0), for crates/sqat/tests/filter_conv.rs. The inputs are computed, not stored:
% the test rebuilds them with the same operations, which are exact in IEEE double.
% Run from the repository root with the baseline worktree of SQAT_BASELINE:
%   matlab -singleCompThread -batch "addpath('tools/matlab'); export_filter_conv('<baseline>')"
function export_filter_conv(baseline)
addpath(fullfile(baseline, 'utilities'));
out = fullfile('crates', 'sqat', 'tests', 'data', 'filter_conv');
if ~exist(out, 'dir'), mkdir(out); end
% N, L, sampled: 300 x 4097 (the filter is the blocked operand), 5000 x 4097 (tiles of 2048),
% 40 x 9 and 300000 x 4097 (past 2^18 the shorter operand is blocked), the last one sampled
cases = [300 4097 0; 5000 4097 0; 40 9 0; 300000 4097 1];
for c = 1:size(cases, 1)
    N = cases(c, 1); L = cases(c, 2);
    y = filter(gen_b(L), 1, gen_x(N));
    if cases(c, 3)
        edges = 2048 * (1:floor((N - 1) / 2048));
        idx = unique([0:97:N-1, edges - 2, edges - 1, edges, edges + 1, N - 1]);
    else
        idx = 0:N-1;
    end
    wr(fullfile(out, sprintf('y_%d_%d.f64', N, L)), [idx; y(idx + 1)]);
end
for fs = [44100 48000]
    wr(fullfile(out, sprintf('a0_fir_%d.f64', fs)), calculate_a0(fs, 4096, 'fluctuationstrength_osses2016'));
end
end

function x = gen_x(n)
k = 1:n;
x = (mod(k * 0.6180339887498949, 1) - 0.5) .* 2 .^ (mod(k, 7) - 3);
end

function b = gen_b(n)
b = mod((1:n) * 0.7548776662466927, 1) - 0.5;
end

function wr(p, v)
fid = fopen(p, 'w');
fwrite(fid, v(:), 'double');
fclose(fid);
end
