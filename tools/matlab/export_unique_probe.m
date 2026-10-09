function export_unique_probe(out)
% export_unique_probe(out)
%
%   matlab.lang.makeUniqueStrings and the CSV name rule of SQAT_GUI_export_data
%   (regexprep(name, '[^\w.-]+', '_')) of this MATLAB, for the sheet, column and
%   file names of the CSV export of sqat-gui. Writes the cases and their results
%   to the JSON file out (crates/sqat-gui/tests/fixtures/g36_unique.json).
c = {};
c{end+1} = struct('in', {{'a','b','a','c','a'}}, 'excl', {{}}, 'max', 63);
c{end+1} = struct('in', {{'a','a','a_1'}}, 'excl', {{}}, 'max', 63);
c{end+1} = struct('in', {{'Info','x'}}, 'excl', {{'Info'}}, 'max', 31);
c{end+1} = struct('in', {{repmat('x',1,35), repmat('x',1,35), repmat('x',1,31)}}, 'excl', {{'Info'}}, 'max', 31);
c{end+1} = struct('in', {{'Sound level','Sound level','Info'}}, 'excl', {{'Info'}}, 'max', 31);
c{end+1} = struct('in', {{'a_1','a','a'}}, 'excl', {{}}, 'max', 63);
for k = 1:numel(c)
    c{k}.out = matlab.lang.makeUniqueStrings(c{k}.in, c{k}.excl, c{k}.max);
end
r = struct('cases', {c}, 'namelengthmax', namelengthmax, ...
    'regexprep_in', ['a', char(231), char(227), 'o ', char(181), ' ', char(176), ' ', char(916), '/x:y.z-w'], ...
    'matlab', version);
r.regexprep_out = regexprep(r.regexprep_in, '[^\w.-]+', '_');
fid = fopen(out, 'w'); fwrite(fid, jsonencode(r, 'PrettyPrint', true), 'char'); fclose(fid);
end
