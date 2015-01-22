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

Nr = 502;
Nc = 458;
Ne = Nr*Nc;

r1     = 0;											// top row index of ROI
r2     = Nr - 1;									// bottom row index of ROI
c1     = 0;											// left column index of ROI
c2     = Nc - 1;									// right column index of ROI

// ROI image size
NeROI = (r2-r1+1)*(c2-c1+1);						// number of elements in ROI, ROI size

// allocate variables for surrounding pixels
iN = new Int32Array(Nr);							// north surrounding element
iS = new Int32Array(Nr);							// south surrounding element
jW = new Int32Array(Nc);							// west surrounding element
jE = new Int32Array(Nc);							// east surrounding element

// allocate variables for directional derivatives
dN = new Float32Array(Ne);							// north direction derivative
dS = new Float32Array(Ne);							// south direction derivative
dW = new Float32Array(Ne);							// west direction derivative
dE = new Float32Array(Ne);							// east direction derivative

// allocate variable for diffusion coefficient
c  = new Float32Array(Ne);							// diffusion coefficient
// N/S/W/E indices of surrounding pixels (every element of IMAGE)
for (i=0; i<Nr; i++) {
    iN[i] = i-1;									// holds index of IMAGE row above
    iS[i] = i+1;									// holds index of IMAGE row below
}
for (j=0; j<Nc; j++) {
    jW[j] = j-1;									// holds index of IMAGE column on the left
    jE[j] = j+1;									// holds index of IMAGE column on the right
}
// N/S/W/E boundary conditions, fix surrounding indices outside boundary of IMAGE
iN[0]    = 0;										// changes IMAGE top row index from -1 to 0
iS[Nr-1] = Nr-1;									// changes IMAGE bottom row index from Nr to Nr-1
jW[0]    = 0;										// changes IMAGE leftmost column index from -1 to 0
jE[Nc-1] = Nc-1;									// changes IMAGE rightmost column index from Nc to Nc-1

/* Get image data */
// var img = document.getElementById("image");
// var canvas = document.getElementById("canvas");
// var ctx = canvas.getContext("2d");

var image, data, q0sqr;

var expectedOutput = 52608;

//write image
function writeImage() {
    for(i=0; i<Ne; i++) {
        data[i] = /*Math.round*/(Math.log(image[i])*255)|0;
    }
    /*ctx.clearRect(0, 0, Nc, Nr);
    ctx.putImageData(imageData, 0, 0);*/
}

function calculateSum() {
    var sum=0;
    var sum2=0;
    for (i=r1; i<=r2; i++) {                                // do for the range of rows in ROI
        for (j=c1; j<=c2; j++) {                            // do for the range of columns in ROI
            var tmp   = image[i + Nr*j];                        // get coresponding value in IMAGE
            sum  += tmp;                                    // take corresponding value and add to sum
            sum2 += tmp*tmp;                                // take square of corresponding value and add to sum2
        }
    }
    var meanROI = sum / NeROI;                                  // gets mean (average) value of element in ROI
    var varROI  = (sum2 / NeROI) - meanROI*meanROI;             // gets variance of ROI
    q0sqr   = varROI / (meanROI*meanROI);                   // gets standard deviation of ROI
}

function calculateDiffusion() {
    for (j=0; j<Nc; j++) {                                  // do for the range of columns in IMAGE
        for (i=0; i<Nr; i++) {                              // do for the range of rows in IMAGE
            // current index/pixel
            var k = i + Nr*j;                                   // get position of current element
            var Jc = image[k];                                  // get value of the current element
            // directional derivates (every element of IMAGE)
            dN[k] = image[iN[i] + Nr*j] - Jc;               // north direction derivative
            dS[k] = image[iS[i] + Nr*j] - Jc;               // south direction derivative
            dW[k] = image[i + Nr*jW[j]] - Jc;               // west direction derivative
            dE[k] = image[i + Nr*jE[j]] - Jc;               // east direction derivative

            // normalized discrete gradient mag squared (equ 52,53)
            var G2 = (dN[k]*dN[k] + dS[k]*dS[k] +               // gradient (based on derivatives)
                    dW[k]*dW[k] + dE[k]*dE[k]) / (Jc*Jc);
            // normalized discrete laplacian (equ 54)
            L = (dN[k] + dS[k] + dW[k] + dE[k]) / Jc;       // laplacian (based on derivatives)

            // ICOV (equ 31/35)
            var num  = (0.5*G2) - ((1.0/16.0)*(L*L)) ;          // num (based on gradient and laplacian)
            var den  = 1 + (0.25*L);                            // den (based on laplacian)
            var qsqr = num/(den*den);                           // qsqr (based on num and den)

            // diffusion coefficent (equ 33) (every element of IMAGE)
            den = (qsqr-q0sqr) / (q0sqr * (1+q0sqr));       // den (based on qsqr and q0sqr)
            c[k] = 1.0 / (1.0+den);                         // diffusion coefficient (based on den)

            // saturate diffusion coefficent to 0-1 range
            if (c[k] < 0)                                   // if diffusion coefficient < 0
                {c[k] = 0;}                                 // ... set to 0
            else if (c[k] > 1)                              // if diffusion coefficient > 1
                {c[k] = 1;}                                 // ... set to 1
        }
    }
}

function adjustValues(lambda) {
    lambda = 0.25*lambda;
    for (j=0; j<Nc; j++) {                                  // do for the range of columns in IMAGE
            // printf("NUMBER OF THREADS: %d\n", omp_get_num_threads());
        for (i=0; i<Nr; i++) {                              // do for the range of rows in IMAGE
            // current index
            var k = i + Nr*j;                                   // get position of current element
            // diffusion coefficent
            var cN = c[k];                                      // north diffusion coefficient
            var cS = c[iS[i] + Nr*j];                           // south diffusion coefficient
            var cW = c[k];                                      // west diffusion coefficient
            var cE = c[i + Nr*jE[j]];                           // east diffusion coefficient
            // divergence (equ 58)
            var D = cN*dN[k] + cS*dS[k] + cW*dW[k] + cE*dE[k];  // divergence
            // image update (equ 61) (every element of IMAGE)
            image[k] = image[k] + lambda*D;            // updates image (based on input time step and divergence)
        }
    }
}

function SRAD(niter,lambda) {
    for (iter=0; iter<niter; iter++) {
        
        calculateSum();
        // directional derivatives, ICOV, diffusion coefficent
        
        calculateDiffusion();
        // divergence & image update
        
        adjustValues(lambda);
    }
}

function runSRAD(niter,lambda) {
    var output = 0;
    image = new Float32Array(Ne);
    for(i=0; i<Ne; i++) {
        image[i] = Math.exp(data[i]/255);
    }
    time0 = performance.now();
    SRAD(niter,lambda);
    time1 = performance.now();
    writeImage();

    for (i=0; i<Nr; i++) {
        print(i);
        output = output + data[i];
    }

    if (niter === 500 & lambda === 1) {
        if (output !== expectedOutput) {
            console.log("ERROR: expected output of '"+expectedOutput+"' but received '"+output+"' instead");
        }
    } else {
        console.log("WARNING: No self-checking step for niter '" + niter + "' and lambda '" + lambda + "'");
    }

    console.log("Time: " + ((time1-time0)/1000) + " s");
    return { status: 1,
             options: "runSRAD(" + [niter, lambda].join(",") + ")",
             time: (time1 - time0) / 1000 };
}
