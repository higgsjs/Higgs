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


if (typeof performance === "undefined") {
    performance = Date;
}

function complexPolar(r, t){
    return { "r": r*Math.cos(t), "i": r*Math.sin(t)};
}

function fftSimple(r, i){
    var N = r.length;
    var R = new Float64Array(N);
    var I = new Float64Array(N);

    if(N===1){
        R[0] = r[0];
        I[0] = i[0];
        return { "r" : R, "i": I};
    }

    var er = new Float64Array(N/2);
    var ei = new Float64Array(N/2);
    var dr = new Float64Array(N/2);
    var di = new Float64Array(N/2);

    for(var k=0; k < N/2; ++k){
        er[k] = r[2*k];
        ei[k] = i[2*k];
        dr[k] = r[2*k + 1];
        di[k] = i[2*k + 1];
    }


    var E = fftSimple(er, ei);
    var D = fftSimple(dr, di);
    var ER = E.r;
    var EI = E.i;
    var DR = D.r;
    var DI = D.i;

    for(var k = 0; k < r.length/2; ++k){
        var c = complexPolar(1, -2.0*Math.PI*k/N);
        var t = DR[k];
        DR[k] = t*c.r - DI[k]*c.i;
        DI[k] = t*c.i + DI[k]*c.r;
    }



    for(k = 0; k<N/2; ++k){
        R[k] = ER[k] + DR[k];
        I[k] = EI[k] + DI[k];

        R[k + N/2] = ER[k] - DR[k];
        I[k + N/2] = EI[k] - DI[k];
    }
    return {"r":R, "i":I};
}

function transpose(m){
    var tempr, tempi;
    var N = m.length;
    for(var i = 0; i < N; ++i){
        for(var j = 0; j < i; ++j){
            tempr = m[i]["r"][j];
            tempi = m[i]["i"][j];

            m[i]["r"][j] =  m[j]["r"][i];
            m[i]["i"][j] =  m[j]["i"][i];

            m[j]["r"][i] = tempr;
            m[j]["i"][i] = tempi;
        }
    }
}

function fft2D(m){
    var M = [];
    for(var i =0; i < m.length; ++i){
        M[i]  = fftSimple(m[i]["r"], m[i]["i"]);
    }
    transpose(M);
    for(var i =0; i < m.length; ++i){
        M[i]  = fftSimple(M[i]["r"], M[i]["i"]);
    }
    transpose(M);
    return M;
}

function randomComplexArray(n){ // TA
    var r = new Float64Array(n);
    var i = new Float64Array(n);

    for(var j = 0; j < n; ++j){
        r[j] = Math.commonRandomJS()*2 - 1;
        i[j] = Math.commonRandomJS()*2 - 1;
    }
    return {"r": r, "i": i};
}

function randomComplexMatrix(n){
    var M = [];
    for(var i = 0; i < n; ++i) M[i] = randomComplexArray(n); // TA
    return M;
}


function printComplexArray(r, i) { // TA
    var a = [];
    for(var j=0; j < r.length; ++j) a[j] = r[j].toFixed(6) + " + " + i[j].toFixed(6) + "i";
    console.log(a.join("\n"));
}

function printComplexMatrix(m){
    for(var i = 0; i < m.length; ++i)
        printComplexArray(m[i]["r"], m[i]["i"]);
}


function runFFT(twoExp){
    if (twoExp === undefined) {
        twoExp = 10;
    }

    if (twoExp < 0 || twoExp > 30) {
        throw new Error("ERROR: invalid exponent of '" + twoExp + "' for input size");
    }
    var n = 1 << twoExp;
    var data1D = randomComplexArray(n);
    var data2D = randomComplexMatrix(n);
    var t1, t2;

    /*
    t1 = performance.now();
    var results = fftSimple(data1D.r,data1D.i);
    t2 = performance.now();
    console.log("The total 1D FFT time for " + n + " size was " + (t2-t1)/1000 + " s");
    */

    t1 = performance.now();
    var results2D = fft2D(data2D);
    t2 = performance.now();
    console.log("The total 2D FFT time for " + n + " x " + n + " was " + (t2-t1)/1000 + " s");
    return { status: 1,
             options: "runFFT(" + twoExp + ")",
             time: (t2 - t1) / 1000 };
}
