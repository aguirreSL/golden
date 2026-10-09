function varargout = warning(varargin)
%WARNING Builtin warning plus a record of every warning raised during a recorded call.
%
%   On the path only while export_validation_goldens.m runs. Behaves as the builtin; when the
%   call raised a warning (lastwarn moved off the sentinel), it is appended to every open frame
%   of export_warn_frame.m, with its identifier, its formatted message and whether its state
%   lets it show. When nothing was raised, lastwarn gets its previous value back.
[m0, i0] = lastwarn;
lastwarn('sqat-parity:none', 'sqatparity:none');
if nargout > 0
    [varargout{1:nargout}] = builtin('warning', varargin{:});
else
    builtin('warning', varargin{:});
end
[m, id] = lastwarn;
if strcmp(id, 'sqatparity:none') && strcmp(m, 'sqat-parity:none')
    lastwarn(m0, i0);
    return
end
st = getappdata(0, 'sqat_warn_stack');
if isempty(st), return; end
x = struct('id', string(id), 'message', string(m), 'enabled', export_warn_on(id));
for k = 1:numel(st), st{k}(end+1) = x; end
setappdata(0, 'sqat_warn_stack', st);
end
