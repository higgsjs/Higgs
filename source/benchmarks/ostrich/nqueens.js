/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2014, Erick Lavoie, Faiz Khan, Sujay Kathrotia, Vincent
 * Foley-Bourgon, Laurie Hendren
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */


var bit_mask1 = parseInt("0xaaaaaaaa", 16);
var bit_mask2 = parseInt("0xcccccccc", 16);
var bit_mask3 = parseInt("0xf0f0f0f0", 16);
var bit_mask4 = parseInt("0xff00ff00", 16);
var bit_mask5 = parseInt("0xffff0000", 16);

if (typeof performance === "undefined")
    performance = Date;

function bit_scan(x){
    var res = 0;
    res |= (x & bit_mask1 ) ? 1 : 0;
    res |= (x & bit_mask2 ) ? 2 : 0;
    res |= (x & bit_mask3 ) ? 4 : 0;
    res |= (x & bit_mask4 ) ? 8 : 0;
    res |= (x & bit_mask5 ) ? 16 : 0;
    return res;
}

function transform(ns_array, board_array, size)
{
    var i;
    for(i = 0; i < size; i++) {
	board_array[i] = bit_scan(ns_array[i]);
    }
}

function nqueen_solver1(size, idx)
{

    var masks = new Uint32Array(32);
    var left_masks = new Uint32Array(32);
    var right_masks = new Uint32Array(32);
    var ms = new Uint32Array(32);
    var ns = ns | 0;
    var solutions = 0;
    var i = 0;

    masks[0] = 1 | 1 << idx;
    left_masks[0] = (1 << 2) | (1 << (idx + 1));
    right_masks[0] = (1 << idx) >> 1;
    ms[0] = masks[0] | left_masks[0] | right_masks[0];
    var board_mask = (1 << size) - 1;

    while(i >= 0) {
	var m = ms[i] | ((i + 2) < idx ? 2 : 0);
	ns = (m + 1) & ~m;
	if((ns & board_mask) != 0) {
	    if(i == size - 3) {
		solutions++;
		i--;
	    }
	    else {
		ms[i] |= ns;
		masks[i+1] = masks[i] | ns;
		left_masks[i+1] = (left_masks[i] | ns) << 1;
		right_masks[i+1] = (right_masks[i] | ns) >> 1;
		ms[i+1] = masks[i+1] | left_masks[i+1] | right_masks[i + 1];
		i++;
	    }
	}
	else {
	    i--;
	}
    }
    return solutions;
}

function nqueen_solver(size, board_mask, mask, left_mask, right_mask, unique_solutions)
{
    var masks= new Uint32Array(32);
    var left_masks= new Uint32Array(32);
    var right_masks= new Uint32Array(32);
    var ms= new Uint32Array(32);
    var ns;
    var ns_array= new Uint32Array(32);
    var t_array= new Uint32Array(32);
    var board_array = new Int32Array(32);
    var solutions = 0;
    var total_solutions = 0;
    var i = 0;
    var j, k;
    var border_mask = 0;
    var index;

    forbidden = new Uint32Array(32);

    masks[0] = mask;
    left_masks[0] = left_mask;
    right_masks[0] = right_mask;
    ms[0] = mask | left_mask | right_mask;
    ns_array[0] = mask;

    index = bit_scan(mask);
    for(j = 0; j < index; j++) {
	border_mask |= (1 << j);
	border_mask |= (1 << (size - j - 1));
    }

    for(k = 0; k < size; k++) {
	if(k == size - 2) {
	    forbidden[k] = border_mask;
	}
	else if((k + 1) < index || (k + 1) > size - index - 1) {
	    forbidden[k] = 1 | (1 << (size - 1));
	}
	else {
	    forbidden[k] = 0;
	}
    }

    while(i >= 0) {
	var m = ms[i] | forbidden[i];
	ns = (m + 1) & ~m;

	if((ns & board_mask) != 0) {
	    ns_array[i+1] = ns;
	    if(i == size - 2) {
		var repeat_times = 8;
		var rotate1 = false;
		var rotate2 = false;
		var rotate3 = false;

		if(ns_array[index] == (1 << (size - 1))) rotate1 = true;
		if(ns_array[size - index - 1] == 1) rotate2 = true;
		if(ns_array[size - 1] == (1 << (size - index - 1))) rotate3 = true;

		if(rotate1 || rotate2 || rotate3) {
		    transform(ns_array, board_array, size);
		    var repeat_times = 8;
		    var equal = true;
		    var min_pos = size;
		    var relation = 0;
		    var j;

		    // rotate cw
		    if(rotate1) {
			equal = true;
			relation = 0;
			for(j = 0; j < size; j++) {
			    if(board_array[size - board_array[j] - 1] != j) {
				equal = false;
				if(min_pos > size - board_array[j] - 1) {
				    relation = board_array[size - board_array[j] - 1] - j;
				    min_pos = size - board_array[j] - 1;
				}
			    }
			}

			repeat_times = equal ? 2 : repeat_times;
		    }

		    if(relation >= 0 && rotate2) {
			// rotate ccw
			equal = true;
			min_pos = size;
			relation = 0;
			for(j = 0; j < size; j++) {
			    if(board_array[board_array[j]] != size - j - 1) {
				equal = false;
				if(min_pos > board_array[j]) {
				    relation = board_array[board_array[j]] - (size - j - 1);
				    min_pos = board_array[j];
				}
			    }
			}

			repeat_times = equal ? 2 : repeat_times;
		    }

		    if(relation >= 0 && repeat_times == 8 && rotate3) {
			// rotate 180
			equal = true;
			min_pos = size;
			relation = 0;
			for(j = size - 1; j >= size / 2; j--) {
			    if(board_array[size - j - 1] != size - board_array[j] - 1) {
				equal = false;
				relation = board_array[size - j - 1] - (size - board_array[j] - 1);
				break;
			    }
			}

			repeat_times = equal ? 4 : repeat_times;
		    }

		    total_solutions += (relation >= 0) ? repeat_times : 0;
		    solutions += (relation >= 0) ? 1 : 0;
		}
		else {
		    total_solutions += 8;
		    solutions++;
		}

		i--;
	    }
	    else {
		ms[i] |= ns;
		masks[i+1] = masks[i] | ns;
		left_masks[i+1] = (left_masks[i] | ns) << 1;
		right_masks[i+1] = (right_masks[i] | ns) >> 1;
		ms[i+1] = masks[i+1] | left_masks[i+1] | right_masks[i + 1];
		i++;
	    }
	}
	else {
	    i--;
	}
    }

    unique_solutions["solutions"] = solutions;
    return total_solutions;
}

function nqueenJS(size, unique_solutions)
{
    var solutions = 0;
    var u_solutions = {};
    var i;

    // get initial set of solutions
    for(i = 2; i < size; i++) {
	solutions += nqueen_solver1(size, i);
    }

    unique_solutions["solutions"] = solutions;
    solutions *= 8;

    // accound for symmetries
    for(i = 1; i < size / 2; i++) {
	solutions += nqueen_solver(size, (1 << size) - 1, 1 << i, 1 << (i + 1), (1 << i) >> 1, u_solutions);
	unique_solutions["solutions"] += u_solutions["solutions"];
    }

    timing = size;
    return solutions;
}


function runNQueens(size){
    var us = {};
    var t1, t2;

    var solutions;

    t1 = performance.now();
    solutions = nqueenJS(size, us);
    t2 = performance.now();


    console.log("Size: " + size + " Time: " + (t2-t1)/1000 + " s Solutions: " +
                solutions + " Unique Solutions: " + us["solutions"]);
    return { status: 1,
             options: 'runNQueens(' + size + ')',
             time: (t2-t1)/1000 };
}
