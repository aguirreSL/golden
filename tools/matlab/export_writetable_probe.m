function export_writetable_probe(out_dir)
% export_writetable_probe(out_dir)
%
%   How writetable of this MATLAB writes the tables of the GUI export: the
%   number format, NaN, Inf, -0 and denormals, the quoting of text and of
%   headers with commas and quotes, line ends and encoding. The calls are the
%   ones of SQAT_GUI_export_data (fork 6e0aa27): writetable(T, csv,
%   'WriteMode', 'overwrite') for a CSV file, writetable(T, xlsx, 'Sheet', name)
%   for a sheet. Reference for the CSV export of sqat-gui (the port writes CSV
%   only, decided 2026-10-08); the .xlsx is kept as a reference of structure.
%
%   Writes into out_dir: series.csv, values.csv, info.csv, quoting.csv, probe.xlsx, and
%   probe.json with the inputs (numbers as hex bits, texts) and what readcell reads back from
%   each CSV file and each sheet.
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

x = [pi; 1/3; 0.1; 0.1 + 0.2; 1e-20; 1e20; 1e21; 123456789.123456789; -0; 0; NaN; Inf; -Inf; ...
     1e-5; 1e-4; 1e5; 1e15; 1e16; 2^53 + 2; eps; realmin; realmax; 5e-324; 1.5; -2.5e-7; ...
     12345.6789; 3; 94; 0.32; 1/7e3; 65.4321; 1e-300; 100; 1234567; 0.000123456789; ...
     2/3*1e10; 1 - eps; 999999.5; 0.5; -1];
t = (0:numel(x) - 1)' * 0.002;
series = table(t, x, flipud(x), 'VariableNames', ...
    {'Time (s)', 'Loudness (sone), ch1', 'Value, "q", binaural'});

q = {'N'; 'Nmax'; 'with, comma'; 'with "quote"'; sprintf('two\nlines'); '  lead space'; ...
     ['a', char(231), char(227), 'o ', char(181), ' ', char(176), ' ', char(916)]; ''; ...
     'semi;colon'; sprintf('tab\there')};
units = {'sone'; 'sone'; '-'; 'dB(A)'; '-'; '-'; [char(181) 'Pa']; '-'; '-'; '-'};
V = [x(1:10), [x(11:15); NaN(5, 1)]];
values = [table(q, units, 'VariableNames', {'Quantity', 'Unit'}), ...
    array2table(V, 'VariableNames', strcat({'Value, '}, {'ch1', 'binaural'}))];

rows = {'Exported', '2026-10-08 12:00:00'
        'Path', ['/tmp/a b/a', char(231), char(227), 'o "x", y.wav']
        'Full scale (dB SPL)', '94.00, 94.00 (default)'
        'Parameters', 'Sound field: Free-frontal; Time skip: 0.32 s'
        'Empty', ''
        'Multi', sprintf('a\nb')
        'Number as text', '48000'};
info = cell2table(rows, 'VariableNames', {'Item', 'Value'});

% one special case per text column, to see which columns get quotes
c = {'a,b', 'a"b', sprintf('a\nb'), sprintf('a\rb'), sprintf('a\tb'), 'a;b', ' a', 'a ', '', ...
     char(231), 'a''b', 'plain'};
quoting = cell2table([c; repmat({'c'}, 1, numel(c))], 'VariableNames', {'comma', 'quote', 'newline', ...
    'cr', 'tab', 'semicolon', 'lead space', 'trail space', 'empty', 'unicode', 'apostrophe', 'plain'});
quoting.allempty = {''; ''};

tabs = struct('name', {'series', 'values', 'info', 'quoting'}, ...
    'sheet', {'Series', 'Single values', 'Info', 'Quoting'}, 'table', {series, values, info, quoting});
xlsx = fullfile(out_dir, 'probe.xlsx');
writetable(info, xlsx, 'Sheet', 'Info', 'WriteMode', 'replacefile');
for k = 1:numel(tabs)
    writetable(tabs(k).table, fullfile(out_dir, [tabs(k).name '.csv']), 'WriteMode', 'overwrite');
    if ~strcmp(tabs(k).sheet, 'Info')
        writetable(tabs(k).table, xlsx, 'Sheet', tabs(k).sheet);
    end
end

out = struct();
out.provenance = struct('matlab', version, 'computer', computer, 'generated', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss')), ...
    'calls', 'writetable(T, csv, ''WriteMode'', ''overwrite''); writetable(T, xlsx, ''Sheet'', name)');
out.x_hex = cellstr(num2hex(x));
out.t_hex = cellstr(num2hex(t));
out.text_inputs = struct('quantity', {q}, 'unit', {units}, 'info', {num2cell(rows, 2)}, 'quoting', {c});
for k = 1:numel(tabs)
    out.(tabs(k).name) = struct( ...
        'variable_names', {tabs(k).table.Properties.VariableNames}, ...
        'csv_readcell', {il_cells(readcell(fullfile(out_dir, [tabs(k).name '.csv'])))}, ...
        'xlsx_readcell', {il_cells(readcell(xlsx, 'Sheet', tabs(k).sheet))}, ...
        'xlsx_sheet', tabs(k).sheet);
end
fid = fopen(fullfile(out_dir, 'probe.json'), 'w');
fwrite(fid, jsonencode(out, 'PrettyPrint', true), 'char');
fclose(fid);
end

function r = il_cells(c)
% a cell array as rows of {missing}, {num, hex} or {text}
r = cell(size(c, 1), 1);
for i = 1:size(c, 1)
    row = cell(1, size(c, 2));
    for j = 1:size(c, 2)
        v = c{i, j};
        if isa(v, 'missing')
            row{j} = struct('missing', true);
        elseif isnumeric(v) || islogical(v)
            row{j} = struct('num', sprintf('%.17g', double(v)), 'hex', num2hex(double(v)));
        else
            row{j} = struct('text', char(v));
        end
    end
    r{i} = row;
end
end
