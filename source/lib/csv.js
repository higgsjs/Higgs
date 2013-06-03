/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013, Maxime Chevalier-Boisvert. All rights reserved.
*
*  This software is licensed under the following license (Modified BSD
*  License):
*
*  Redistribution and use in source and binary forms, with or without
*  modification, are permitted provided that the following conditions are
*  met:
*   1. Redistributions of source code must retain the above copyright
*      notice, this list of conditions and the following disclaimer.
*   2. Redistributions in binary form must reproduce the above copyright
*      notice, this list of conditions and the following disclaimer in the
*      documentation and/or other materials provided with the distribution.
*   3. The name of the author may not be used to endorse or promote
*      products derived from this software without specific prior written
*      permission.
*
*  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED
*  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
*  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
*  NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
*  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
*  NOT LIMITED TO PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
*  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
*  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
*  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
*  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
*****************************************************************************/

(function()
{
    var io = require('lib/stdio');

    /**
    @class Comma-Separated Values (CSV) spreadsheet
    */
    function CSV()
    {
        this.rows = [];
    }

    CSV.prototype.fromString = function (str)
    {
        var state = 'PRE-QUOTE';

        var curRow = [];

        var curCell = '';

        var lineNo = 1;

        var that = this;

        function parseError(errorText)
        {
            error('line ' + lineNo + ': ' + errorText);
        }

        function pushCell()
        {
            curRow.push(curCell);
            curCell = '';

            state = 'PRE-QUOTE';
        }

        function pushRow()
        {
            if (curCell.length > 0)
                pushCell();

            that.rows.push(curRow);
            curRow = [];

            state = 'PRE-QUOTE';
        }

        // For each character
        for (chIdx = 0; chIdx < str.length; ++chIdx)
        {
            var ch = str[chIdx];

            if (ch === '\r')
                continue;

            if (ch === '\n')
                lineNo++;

            switch (state)
            {
                case 'PRE-QUOTE':
                {
                    if (ch === '"')
                        state = 'IN-QUOTE';
                    else if (ch === ' ')
                        continue;
                    else if (ch === ',')
                        pushCell();
                    else if (ch === '\n')
                        pushRow();
                    else
                    {
                        state = 'NO-QUOTE';
                        chIdx--;
                    }
                }
                break;

                case 'IN-QUOTE':
                {
                    if (ch === '"')
                        state = 'POST-QUOTE';
                    else
                        curCell += ch;
                }
                break;

                case 'NO-QUOTE':
                {
                    if (ch === '"')
                        parseError('quote in cell data');
                    else if (ch === ' ')
                        continue;
                    else if (ch === ',')
                        pushCell();
                    else if (ch === '\n')
                        pushRow();
                    else
                        curCell += ch;
                }
                break;

                case 'POST-QUOTE':
                {
                    if (ch === '"')
                        parseError('superfluous quote');
                    else if (ch === ' ')
                        continue;
                    else if (ch === ',')
                        pushCell();
                    else if (ch === '\n')
                        pushRow();
                    else
                        parseError('data after closing quote');
                }
                break;
            }
        }

        if (curRow.length > 0)
            pushRow();
    }

    CSV.prototype.toString = function ()
    {
        var str = '';

        for (var y = 0; y < this.rows.length; ++y)
        {
            var row = this.rows[y];

            for (var x = 0; x < row.length; ++x)
            {
                var cell = row[x];

                if (cell.indexOf(',') !== -1)
                    str += '"' + cell + '"';
                else
                    str += cell;

                if (x < row.length - 1)
                    str += ',';
            }

            if (y < this.rows.length - 1)
                str += '\n';
        }

        return str;
    }

    CSV.prototype.loadFile = function (fileName)
    {
        var str = io.fopen(fileName, "r").read();
        return this.fromString(str);
    }

    CSV.prototype.writeFile = function (fileName)
    {
        var str = this.toString();
        io.fopen(fileName, "w").write(str);
    }

    CSV.prototype.getNumRows = function ()
    {
        return this.rows.length;
    }

    CSV.prototype.getNumCols = function (rowIdx)
    {
        assert(
            rowIdx < this.rows.length,
            'invalid row index: ' + rowIdx
        );

        return this.rows[rowIdx].length;
    }

    CSV.prototype.getCell = function (rowIdx, colIdx)
    {
        assert(
            rowIdx < this.rows.length,
            'invalid row index: ' + rowIdx
        );

        assert (
            colIdx < this.rows[rowIdx].length,
            'invalid column index: ' + colIdx
        );

        return this.rows[rowIdx][colIdx];
    }

    CSV.prototype.setCell = function (rowIdx, colIdx, val)
    {
        // TODO
    }

    CSV.prototype.getColIdx = function (colName)
    {
        var numCols = this.rows[0].length;

        for (var i = 0; i < numCols; ++i)
        {
            if (this.rows[0][i] === colName)
                return i;
        }

        return undefined;
    }

    function loadFile(fileName)
    {
        var csv = new CSV();
        csv.loadFile(fileName);
        return csv;
    }

    // Exported namespace
    exports = {
        CSV: CSV,
        loadFile: loadFile
    };

})()

