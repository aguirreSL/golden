function export_call(fname, args, outs, warns, err)
%EXPORT_CALL Record one call of a wrapped SQAT function (export_validation_goldens).
%
%   Writes <root>/<tag>/call_<NNNN>_<fname>/ with call.json (the arguments:
%   small numeric values and text inline, large numeric arrays as references
%   to <root>/inputs/<sha256>.f64, stored once) and out<k>[_<field>].f64 for
%   every numeric output, fixture format (raw little-endian f64, C order, and
%   a .meta.json sidecar). No decimation. Root and tag come from the env vars
%   SQAT_CALLS_ROOT and SQAT_CALLS_TAG; the counter lives in a file, because
%   the validation scripts run `clear all`.
%
%   warns (optional): the warnings raised during the call (export_warn_frame.m), written to
%   call.json as a list of {id, message, enabled}. err (optional): the MException of a call
%   that ended in error, written as {identifier, message}; such a call has no outputs.
root = getenv('SQAT_CALLS_ROOT');
tag = getenv('SQAT_CALLS_TAG');
if isempty(root) || isempty(tag)
    return;
end
dir_tag = fullfile(root, tag);
if ~isfolder(dir_tag), mkdir(dir_tag); end
cnt_file = fullfile(dir_tag, '.count');
n = 0;
if isfile(cnt_file), n = str2double(fileread(cnt_file)); end
n = n + 1;
fid = fopen(cnt_file, 'w'); fprintf(fid, '%d', n); fclose(fid);
d = fullfile(dir_tag, sprintf('call_%04d_%s', n, fname));
mkdir(d);

J = struct();
J.function = fname;
J.args = cell(1, numel(args));
for k = 1:numel(args)
    J.args{k} = arg_json_(root, args{k});
end
J.warnings = {};
if nargin >= 4 && ~isempty(warns), J.warnings = num2cell(warns(:)'); end
if nargin >= 5 && ~isempty(err)
    J.error = struct('identifier', string(err.identifier), 'message', string(err.message));
end
J.outputs = {};
for k = 1:numel(outs)
    v = outs{k};
    if isstruct(v) && isscalar(v)
        fn = fieldnames(v);
        for i = 1:numel(fn)
            x = v.(fn{i});
            if (isnumeric(x) || islogical(x)) && ~isempty(x)
                rel = sprintf('out%d_%s.f64', k, fn{i});
                write_f64_(fullfile(d, rel), double(x));
                J.outputs{end+1} = struct('k', k, 'field', fn{i}, 'file', rel); %#ok<AGROW>
            elseif ischar(x) || isstring(x)
                J.outputs{end+1} = struct('k', k, 'field', fn{i}, 'text', string(x)); %#ok<AGROW>
            end
        end
    elseif (isnumeric(v) || islogical(v)) && ~isempty(v)
        rel = sprintf('out%d.f64', k);
        write_f64_(fullfile(d, rel), double(v));
        J.outputs{end+1} = struct('k', k, 'field', '', 'file', rel); %#ok<AGROW>
    end
end
fid = fopen(fullfile(d, 'call.json'), 'w');
fwrite(fid, uint8(jsonencode(J, 'PrettyPrint', true)));
fclose(fid);
end

function a = arg_json_(root, v)
if (isnumeric(v) || islogical(v)) && numel(v) > 64
    x = double(v);
    flat = reshape(permute(x, ndims(x):-1:1), 1, []);
    h = lower(reshape(dec2hex(typecast(java.security.MessageDigest.getInstance('SHA-256') ...
        .digest(typecast(flat, 'uint8')), 'uint8'))', 1, []));
    p = fullfile(root, 'inputs', [h '.f64']);
    if ~isfile(p)
        write_f64_(p, x);
    end
    a = struct('kind', 'array', 'input', ['inputs/' h '.f64'], 'shape', size(v));
elseif isnumeric(v) || islogical(v)
    a = struct('kind', 'numeric', 'value', double(v), 'shape', size(v));
elseif ischar(v) || isstring(v)
    a = struct('kind', 'text', 'value', string(v));
elseif isstruct(v) && isscalar(v)   % each field recorded as an argument of its own
    f = struct();
    fn = fieldnames(v);
    for i = 1:numel(fn)
        f.(fn{i}) = arg_json_(root, v.(fn{i}));
    end
    a = struct('kind', 'struct', 'fields', f);
else
    a = struct('kind', class(v));
end
end

function write_f64_(p, x)
d = fileparts(p);
if ~isfolder(d), mkdir(d); end
fid = fopen(p, 'w', 'ieee-le');
if ~isempty(x)
    fwrite(fid, reshape(permute(x, ndims(x):-1:1), 1, []), 'double');
end
fclose(fid);
m = struct('shape', size(x), 'dtype', "f64", 'order', "C", 'unit', "", ...
    'description', "", 'source', struct('m_file', "", 'stage', ""));
fid = fopen([p '.meta.json'], 'w');
fwrite(fid, uint8(jsonencode(m, 'PrettyPrint', true)));
fclose(fid);
end
