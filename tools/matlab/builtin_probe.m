function builtin_probe(out)
%BUILTIN_PROBE SHA-256 of MATLAB builtins on fixed inputs, with the identity of the machine.
%   builtin_probe('probe.json') runs fft, ifft, log10, power, exp, abs, sqrt, sum, matrix
%   products and filter on inputs fixed by rng, and writes one hash per operation. Two runs
%   on one machine, or on two machines, are compared hash by hash.
rng(1, 'twister');
H = struct();
x = randn(240000, 1);
for n = [1024 4096 8192 9600 44100 48000 88200 96000 240000]
    v = x(1:n);
    H.(sprintf('fft_%d', n)) = h(fft(v));
    H.(sprintf('ifft_%d', n)) = h(ifft(fft(v)));
    H.(sprintf('real_ifft_%d', n)) = h(real(ifft(complex(v, flipud(v)))));
end
a = abs(x) * 100 + 1e-3;
H.log10 = h(log10(a));
H.pow10 = h(10.^(x / 20));
H.pow_scalar = h(arrayfun(@(t) 10^(t/20), x(1:20000)));
H.exp = h(exp(x));
H.abs_complex = h(abs(complex(x, flipud(x))));
H.sqrt = h(sqrt(a));
H.sum_vec = h(sum(x));
A = reshape(x(1:240000), 400, 600);
H.sum_dim1 = h(sum(A, 1));
H.sum_dim2 = h(sum(A, 2));
H.mtimes_mm = h(A(:, 1:400) * A(:, 201:600));
H.mtimes_mv = h(A * x(1:600));
H.dot = h(x(1:100000)' * x(100001:200000));
b = x(1:4097) / 100;
H.filter_fir_4097 = h(filter(b, 1, x));
H.filter_fir_9 = h(filter(b(1:9), 1, x));
H.filter_iir = h(filter([0.2 0.3 0.2], [1 -0.5 0.25], x));
% the operations of the inputs and stages that differed between machines
[bb, ab] = butter(2, [3000 5000]/24000, 'bandpass');
H.butter = h([bb ab]);
H.filter_butter = h(filter(bb, ab, x));
y = circshift(x, 7);
for n = [47 256 1024 88200]
    H.(sprintf('cov_%d', n)) = h(cov(x(1:n), y(1:n)));
    X = [x(1:n) y(1:n)];
    H.(sprintf('xtx_%d', n)) = h(X' * X);
    H.(sprintf('dot_%d', n)) = h(x(1:n)' * y(1:n));
end
H.mean_sq = h(mean(x.^2));
M = machine_();
M.mkl_cbwr = getenv('MKL_CBWR');
M.hashes = H;
fid = fopen(out, 'w');
fwrite(fid, uint8(jsonencode(M, 'PrettyPrint', true)));
fclose(fid);
end

function s = h(v)
v = double(v(:));
if ~isreal(v), v = [real(v); imag(v)]; end
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(v, 'uint8'));
s = sprintf('%02x', typecast(md.digest, 'uint8'));
end

function M = machine_()
M = struct('matlab', version, 'computer', computer, 'blas', version('-blas'), ...
    'lapack', version('-lapack'), 'fftw', version('-fftw'), 'threads', maxNumCompThreads, ...
    'numcores', feature('numcores'));
if ismac
    M.cpu = sh_('sysctl -n machdep.cpu.brand_string');
    M.cores = sh_('sysctl -n hw.physicalcpu hw.logicalcpu');
    M.os = sh_('sw_vers -productVersion; sw_vers -buildVersion');
elseif isunix
    M.cpu = sh_('grep -m1 "model name" /proc/cpuinfo');
    M.cores = sh_('nproc; grep -c ^processor /proc/cpuinfo');
    M.flags = sh_('grep -m1 -o -w "avx512f\|avx2\|fma" /proc/cpuinfo | sort -u | tr "\n" " "');
    M.os = sh_('uname -r');
else
    M.cpu = sh_('powershell -NoProfile -Command "(Get-CimInstance Win32_Processor).Name"');
    M.cores = sh_('powershell -NoProfile -Command "$p = Get-CimInstance Win32_Processor; \"$($p.NumberOfCores) $($p.NumberOfLogicalProcessors)\""');
    M.os = sh_('ver');
end
end

function t = sh_(cmd)
[st, out] = system(cmd);
t = '';
if st == 0, t = strtrim(out); end
end
