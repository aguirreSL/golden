function w = export_warn_frame(op)
%EXPORT_WARN_FRAME Warnings of the recorded calls in flight (export_goldens.m, run_metric_case).
%
%   'push' opens a frame when a wrapped call starts; 'pop' closes it and returns the warnings
%   raised during the call, oldest first, as a struct array (id, message, enabled). The shadow
%   warn_shadow/warning.m appends every warning raised through warning() to every open frame, so an
%   outer call also lists the warnings of the calls it makes. A warning raised inside builtin
%   code does not pass through warning.m; 'pop' adds the last one of those from lastwarn.
%   The stack lives in the root appdata.
st = getappdata(0, 'sqat_warn_stack');
if isempty(st), st = {}; end
w = [];
switch op
    case 'push'
        st{end+1} = struct('id', {}, 'message', {}, 'enabled', {});
        lastwarn('', '');
    case 'pop'
        [m, id] = lastwarn;
        top = st{end};
        if ~isempty(m) && (isempty(top) || ~strcmp(top(end).message, m) || ~strcmp(top(end).id, id))
            x = struct('id', string(id), 'message', string(m), 'enabled', export_warn_on(id));
            for k = 1:numel(st), st{k}(end+1) = x; end
            top = st{end};
        end
        w = top;
        st(end) = [];
end
setappdata(0, 'sqat_warn_stack', st);
end
