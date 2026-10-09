function on = export_warn_on(id)
%EXPORT_WARN_ON True when a warning with this identifier is displayed (state not 'off').
if isempty(id), id = 'all'; end
q = builtin('warning', 'query', id);
on = ~strcmp(q(1).state, 'off');
end
