classdef egreg < handle
    %EGREG Shared export registry (handle semantics).
    % Sections and helpers receive copies of the context struct; the
    % registry must be shared so every writer call accumulates in one
    % place for the manifest, budget check and self-verification.
    properties
        info = struct('path', {}, 'sha256', {}, 'bytes', {})
        out_root = ""
        dryrun = false
    end
end
