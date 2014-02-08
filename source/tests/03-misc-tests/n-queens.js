/* _________________________________________________________________________
 *
 *             Tachyon : A Self-Hosted JavaScript Virtual Machine
 *
 *
 *  This file is part of the Tachyon JavaScript project. Tachyon is
 *  distributed at:
 *  http://github.com/Tachyon-Team/Tachyon
 *
 *
 *  Copyright (c) 2011, Universite de Montreal
 *  All rights reserved.
 *
 *  This software is licensed under the following license (Modified BSD
 *  License):
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are
 *  met:
 *    * Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *    * Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *    * Neither the name of the Universite de Montreal nor the names of its
 *      contributors may be used to endorse or promote products derived
 *      from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 *  IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 *  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 *  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL UNIVERSITE DE
 *  MONTREAL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 *  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 *  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 *  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 *  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * _________________________________________________________________________
 */

/**
Recursive n-queens solver
unused is an array of yet unused col indices
board is an array of col indices, one for each row
*/
function nQueens(unused, board, row, n)
{
    //print('nQueens row=' + row + ', n=' + n);

    // If we are past the end of the board, we have found a solution
    if (row >= n)
        return 1;

    /*
    print('unused:');
    for (var i = 0; i < unused.length; ++i)
        print(unused[i]);
    */

    // Number of solutions found recursively
    var numSolns = 0;

    // For each unused column index
    for (var i = 0; i < unused.length; ++i)
    {
        var col = unused[i];

        var safe = true;

        // For each row before the current one
        for (var r = 0; r < row; ++r)
        {
            // If there is a queen in the diagonals
            if (col === board[r] + (row - r) || col === board[r] - (row - r))
            {
                safe = false; 
                break;
            }
        }

        // If we can place the queen at this position
        if (safe)
        {
            var newBoard = [];
            for (var j = 0; j < board.length; ++j)
                newBoard[j] = board[j];

            newBoard[row] = col;

            //print('placing queen at row ' + row + ' col ' + col);

            var newUnused = [];
            for (var j = 0; j < unused.length; ++j)
                if (unused[j] !== col)
                    newUnused[newUnused.length] = unused[j];

            numSolns += nQueens(newUnused, newBoard, row + 1, n);
        }
    }

    // Return the number of solutions found recursively
    return numSolns;
}

function countSolns(n)
{
    //print('in countSolns()');

    // All columns are initially unused
    var unused = [];
    for (var i = 0; i < n; ++i)
        unused[unused.length] = i;

    // The board is initially empty
    var board = [];

    var numSolns = nQueens(unused, board, 0, n);

    return numSolns;
}

function printBoard(board)
{
    for (var i = 0; i < board.length; ++i)
    {
        var rowStr = '';

        for (var j = 0; j < board.length; ++j)
        {
            if (board[i] === j)
                rowStr += 'X';
            else
                rowStr += ' ';

            if (j != board.length - 1)
                rowStr += ',';
        }

        print(rowStr);
    }
}

assert (countSolns(2) === 0);

assert (countSolns(3) === 0);

assert (countSolns(4) === 2);

