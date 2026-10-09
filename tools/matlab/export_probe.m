function export_probe(name, value)
%EXPORT_PROBE Capture hook called from sandboxed (instrumented) metric
% copies; must live on the MATLAB path (own file) so that sandbox copies of
% the baseline metrics can call it. Pure observation: never mutates caller
% variables. Repeated calls auto-number <name>_0001.mat, <name>_0002.mat,
% ... in call order inside the current probe session directory. The counter
% lives in the root appdata (not persistent) so probe_begin resets it
% reliably between cases.
d = getappdata(0, 'sqat_export_probe_dir');
if isempty(d)
    return;
end
name = char(name);
seq = getappdata(0, 'sqat_export_probe_seq');
if isempty(seq)
    seq = struct();
end
key = matlab.lang.makeValidName(['x' name]);
if ~isfield(seq, key)
    seq.(key) = 0;
end
seq.(key) = seq.(key) + 1;
setappdata(0, 'sqat_export_probe_seq', seq);
S = value;   % saved as the variable S (works for struct arrays too)
save(fullfile(d, sprintf('%s_%04d.mat', name, seq.(key))), 'S');
end

function export_probe_reset()
% clears the auto-numbering counters (called at the start of each case)
setappdata(0, 'sqat_export_probe_seq', struct());
end
