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

var T =  1000;        /* Number of static observations */
var S = 2;           /* Number of static symbols */
var N = 60;          /* Number of static states */
var ITERATIONS = 1;           /* Number of iterations */
var EXIT_ERROR= 1;

function imax(x, y){ return (x > y) ? x: y;}

// /* Global variables for device */
var nstates;                        /* The number of states in the HMM */
var nsymbols;                       /* The number of possible symbols */
var obs;                           /* The observation sequence */
var length;                         /* The length of the observation sequence */
var scale;                       /* Scaling factor as determined by alpha */

var alpha;
var beta;
var ones_n;
var ones_s;
var gamma_sum;
var xi_sum;
var c;

/**
 * Calculates the dot product of two vectors.
 * Both vectors must be atleast of length n
 */
function dot_product(n, x, offsetx, y,  offsety){
    var result = 0.0;
    var i = 0;
    if(!x || !y || n ===0) return result;
    for(i = 0; i < n; ++i)
        result += x[i + offsetx]*y[i + offsety];
    return result;
}

function mat_vec_mul(trans, m, n, a, lda, x, offsetx, y, offsety){
    if((trans != 'n') && (trans != 't')){
        return;
    }

    var i,j, n_size, m_size;
    var sum;
    if(lda == m){
        n_size = n;
        m_size = m;
    }
    else{
        n_size = m;
        m_size = n;
    }
    if(trans=='n'){
        for(i=0; i<m_size; ++i){
            sum = 0.0;
            for(j=0; j<n_size; ++j){
                sum  += a[i*n_size + j]*x[offsetx + j];
            }
            y[i + offsety] = sum;
        }
    }
    else{
        for(i=0; i<m_size; ++i){
            sum = 0.0;
            for(j=0; j<n_size; ++j){
                sum += a[j*n_size + i]*x[offsetx + j];
            }
            y[i + offsety] = sum;
        }
    }
}

function init_ones_dev(ones, nsymbols){
    var i;
    for(i=0; i<nsymbols; ++i) ones[i] = 1.0;
}

/*******************************************************************************
 * Supporting functions
 */
function init_alpha(b_d, pi_d, nstates, alpha_d, ones_n_d, obs_t){
    i = 0;
    for(i = 0; i < nstates; ++i){
        alpha_d[i] = pi_d[i]*b_d[(obs_t*nstates)+i];
        ones_n_d[i] = 1.0;
    }
}


function scale_alpha_values( nstates, alpha_d, offset, scale){
    var i =0;
    for(i=0; i<nstates; ++i) alpha_d[offset + i] = alpha_d[offset + i]/scale;
}

function calc_alpha_dev(nstates, alpha_d, offset, b_d, obs_t){
    var i = 0;
    for(i=0; i<nstates; ++i){
        alpha_d[offset + i] = alpha_d[offset + i] * b_d[(obs_t * nstates) + i];
    }
}
function log10(val) { return Math.log(val) / Math.LN10;}

function printIM(aa,  m,  n){
    var i=0;
    var j=0;
    for(i=0; i<m;++i){
        for(j=0; j<n;++j){
            console.log(aa[i*n+j]);
        }
    }
}
function printM(aa,  m,  n){
    var i=0;
    var j=0;
    for(i=0; i<m;++i){
        for(j=0; j<n;++j){
            console.log(aa[i*n+j]);
        }
    }
}

/* Calculates the forward variables (alpha) for an HMM and obs. sequence */
function calc_alpha(a, b, pi){
    var log_lik;
    var t;
    var offset_cur;
    var offset_prev;

    // initialize alpha variables
    init_alpha(b, pi, nstates, alpha, ones_n, obs[0]);

    /* Sum alpha values to get scaling factor */
    scale[0] = dot_product(nstates, alpha, 0, ones_n, 0);

    // Scale the alpha values
    scale_alpha_values(nstates, alpha,0,scale[0]);

    /* Initilialize log likelihood */
    log_lik = log10(scale[0]);

    /* Calculate the rest of the alpha variables */
    for (t = 1; t < length; t++) {

        /* Calculate offsets */
        offset_prev = (t - 1) * nstates;
        offset_cur = t * nstates;

        /* Multiply transposed A matrix by alpha(t-1) */
        /* Note: the matrix is auto-transposed by cublas reading column-major */
        // mat_vec_mul( 'N', nstates, nstates, 1.0f, a_d, nstates,
        //              alpha_d + offset_prev, 1, 0, alpha_d + offset_cur, 1 );
        mat_vec_mul( 'n', nstates, nstates, a, nstates,
                     alpha, offset_prev, alpha, offset_cur);

        calc_alpha_dev(nstates, alpha, offset_cur, b, obs[t]);

        /* Sum alpha values to get scaling factor */
        scale[t] = dot_product(nstates, alpha, offset_cur, ones_n, 0);

        // scale alpha values
        scale_alpha_values(nstates, alpha, offset_cur, scale[t]);

        log_lik += log10(scale[t]);
    }
    return log_lik;
}

function init_beta_dev(nstates, beta_d, offset, scale){
    var i = 0;
    for(i=0; i < nstates; ++i){
        beta_d[offset + i] = 1.0 / scale;
    }
}

function calc_beta_dev(beta_d, b_d, scale_t, nstates, obs_t, t){
    var i;
    for(i=0; i<nstates; ++i){
        beta_d[(t * nstates) + i] = beta_d[((t + 1) * nstates) + i] *
            b_d[(obs_t * nstates) + i] / scale_t;
    }
}

/* Calculates the backward variables (beta) */
function calc_beta(a, b){

    /* Initialize beta variables */
    var offset  = ((length - 1) * nstates);
    var t;
    init_beta_dev(nstates, beta, offset, scale[length-1]);
    /* Calculate the rest of the beta variables */
    for (t = length - 2; t >= 0; t--) {
        calc_beta_dev(beta, b, scale[t], nstates, obs[t+1],t);

        mat_vec_mul( 'n', nstates, nstates, a, nstates,
                     beta, t * nstates, beta, t * nstates);
    }
    return 0;
}

function calc_gamma_dev(gamma_sum_d, alpha_d, beta_d, nstates, t){
    var i;
    for(i=0; i< nstates; ++i){
        gamma_sum_d[i] += alpha_d[(t * nstates) + i] *
            beta_d[(t * nstates) + i];
    }
}

/* Calculates the gamma sum */
function calc_gamma_sum(){
    var size;
    var t;

    for(t=0; t<nstates; ++t) gamma_sum[t] = 0.0;
    /* Find sum of gamma variables */
    for (t = 0; t < length; t++) {
        calc_gamma_dev(gamma_sum, alpha, beta, nstates, t);
    }
}

function calc_xi_sum_dev(xi_sum_d, a_d, b_d, alpha_d,
                         beta_d, sum_ab, nstates, obs_t, t){
    var i,j;
    for(i=0; i<nstates; ++i){
        for(j=0;j<nstates; ++j){
            xi_sum_d[(j * nstates) + i] += alpha_d[(t * nstates) + j] *
                a_d[(j * nstates) + i] *
                b_d[(obs_t * nstates) + i] *
                beta_d[((t+1) * nstates) + i] /
                sum_ab;
        }
    }
}

/* Calculates the sum of xi variables */
function calc_xi_sum(a, b){
    var sum_ab;
    var t;

    for(t=0; t<nstates;++t)xi_sum[t]=0;
    /* Find the sum of xi variables */
    for (t = 0; t < length - 1; t++) {
        /* Calculate denominator */
        sum_ab = dot_product(nstates, alpha, t * nstates,
                             beta, t * nstates);
        calc_xi_sum_dev(xi_sum, a, b, alpha, beta, sum_ab, nstates,obs[t+1], t);
    }
    return 0;
}

function est_a_dev(a_d, alpha_d, beta_d,
                   xi_sum_d, gamma_sum_d, sum_ab, nstates, length){

    var i,j;
    for(i=0; i<nstates; ++i){
        for(j=0; j<nstates; ++j){
            a_d[(j * nstates) + i] = xi_sum_d[(j * nstates) + i] /
                (gamma_sum_d[j] -
                 alpha_d[(j * nstates) + i] *
                 beta_d[(j * nstates) + i] /
                 sum_ab);
        }
    }
}

function scale_a_dev(a_d, c_d, nstates){
    var i,j;
    for(i=0; i<nstates; ++i){
        for(j=0; j<nstates; ++j){
            a_d[(j * nstates) + i] = a_d[(j * nstates) + i] / c_d[j];
        }
    }
}
/* Re-estimates the state transition probabilities (A) */
function estimate_a(a)
{
    var sum_ab;

    /* Calculate denominator */
    sum_ab = dot_product(nstates, alpha, (length - 1) * nstates,
                         beta, (length - 1) * nstates);
    est_a_dev(a, alpha, beta, xi_sum, gamma_sum, sum_ab, nstates, length);

    /* Sum rows of A to get scaling values */
    // mat_vec_mul( 'T', nstates, nstates, 1.0f, a_d, nstates,
    // ones_n_d, 1, 0, c_d, 1 );
    mat_vec_mul( 't', nstates, nstates, a, nstates,
                 ones_n, 0, c, 0);

    /* Normalize A matrix */
    // scale_a_dev<<<grid, threads>>>( a_d,
    // c_d,
    // nstates);
    scale_a_dev(a, c, nstates);

    return 0;
}

/* Accumulate B values */
function acc_b_dev(b_d, alpha_d, beta_d, sum_ab, nstates, nsymbols, obs_t, t){
    var i,j;
    for(i=0; i<nstates; ++i){
        for(j=0; j<nsymbols; ++j){
            if(j==obs_t){
                b_d[(j * nstates) + i] += alpha_d[(t * nstates) + i] *
                    beta_d[(t * nstates) + i] / sum_ab;
            }
        }
    }
}

/* Re-estimate B values */
function est_b_dev(b_d, gamma_sum_d, nstates, nsymbols){
    var i,j;
    for(i=0; i<nstates; ++i){
        for(j=0; j<nsymbols; ++j){
            b_d[(j* nstates) + i] = b_d[(j * nstates) + i] /
                gamma_sum_d[i];
        }
    }
}

/* Normalize B matrix */
function scale_b_dev(b_d, c_d, nstates, nsymbols){
    var i,j;
    for(i=0; i<nstates; ++i){
        for(j=0; j<nsymbols; ++j){
            if (Math.abs(b_d[(i * nsymbols) + j]) <0.000001)
            {
                b_d[(i * nsymbols) + j] = 1e-10;
            }
            else
            {
                b_d[(i * nsymbols) + j] = b_d[(i * nsymbols) + j] / c_d[i];
            }
            // if (fabs(b_d[(j * nstates) + i]) <0.000001)
            // {
            //   b_d[(j * nstates) + i] = 1e-10;
            //   printf("something hits here\n");
            // }
            // else
            // {
            //   b_d[(j * nstates) + i] = b_d[(j * nstates) + i] / c_d[i];
            // }
        }
    }
}

/* Re-estimates the output symbol probabilities (B) */
function estimate_b(b)
{
    var sum_ab;
    var t;
    var offset;

    for(t=0; t<nstates*nsymbols; ++t) b[t] = 0.0;

    for (t = 0; t < length; t++) {

        /* Calculate denominator */
        sum_ab = dot_product(nstates, alpha, t * nstates,
                             beta, t * nstates);
        acc_b_dev(b, alpha, beta, sum_ab, nstates, nsymbols, obs[t+1], t);
    }

    /* Re-estimate B values */
    est_b_dev(b, gamma_sum, nstates, nsymbols);

    /* Sum rows of B to get scaling values */
    // mat_vec_mul( 'N', nstates, nsymbols, 1.0f, b_d, nstates,
    // ones_s_d, 1, 0, c_d, 1 );
    for(t=0; t<nstates; ++t) c[t] = 0.0;
    mat_vec_mul( 'n', nstates, nsymbols, b, nstates,
                 ones_s, 0, c, 0);
    /* Normalize B matrix */
    scale_b_dev(b, c, nstates, nsymbols);
    return 0;
}
function est_pi_dev(pi_d, alpha_d, beta_d, sum_ab, nstates){
    var i;
    for(i=0; i<nstates; ++i){
        pi_d[i] = alpha_d[i] * beta_d[i] / sum_ab;
    }
}

/* Re-estimates the initial state probabilities (Pi) */
function estimate_pi(pi){

    var sum_ab;
    /* Calculate denominator */
    sum_ab = dot_product(nstates, alpha, 0, beta, 0);

    /* Estimate Pi values */
    est_pi_dev(pi, alpha, beta, sum_ab,nstates);

    return 0;
}

// /*******************************************************************************
//  * BWA function
//  */

// /* Runs the Baum-Welch Algorithm on the supplied HMM and observation sequence */
function run_hmm_bwa(hmm, in_obs, iterations, threshold){

    /* Host-side variables */
    var a;
    var b;
    var pi;
    var new_log_lik;
    var old_log_lik = 0;
    var iter;

    /* Initialize HMM values */
    a = hmm.a;
    b = hmm.b;
    pi = hmm.pi;
    nsymbols = hmm.nsymbols;
    nstates = hmm.nstates;
    obs = in_obs.data;
    length = in_obs.length;

    /* Allocate host memory */
    scale = new Float32Array(length);

    alpha = new Float32Array(nstates*length);
    beta = new Float32Array(nstates*length);
    gamma_sum =  new Float32Array(nstates);
    xi_sum =  new Float32Array(nstates*nstates);
    c = new Float32Array(nstates);
    ones_n = new Float32Array(nstates);
    ones_s = new Float32Array(nsymbols);

    init_ones_dev(ones_s, nsymbols);

    //   /**
    //    * a_d => a
    //    * b_d => b
    //    * pi_d => pi
    //    */

    /* Run BWA for either max iterations or until threshold is reached */
    for (iter = 0; iter < iterations; iter++) {
        new_log_lik = calc_alpha(a, b, pi);
        if (new_log_lik == EXIT_ERROR) {
            return EXIT_ERROR;
        }
        if (calc_beta(a, b) == EXIT_ERROR) {
            return EXIT_ERROR;
        }

        calc_gamma_sum();

        if (calc_xi_sum(a, b) == EXIT_ERROR) {
            return EXIT_ERROR;
        }

        if (estimate_a(a) == EXIT_ERROR) {
            return EXIT_ERROR;
        }

        if (estimate_b(b) == EXIT_ERROR) {
            return EXIT_ERROR;
        }

        if (estimate_pi(pi) == EXIT_ERROR) {
            return EXIT_ERROR;
        }

        /* check log_lik vs. threshold */
        if (threshold > 0 && iter > 0) {
            if (fabs(pow(10,new_log_lik) - pow(10,old_log_lik)) < threshold) {
                break;
            }
        }

        old_log_lik = new_log_lik;
    }
    return new_log_lik;
}

/* Time the forward algorithm and vary the number of states */
function bwa_hmm(v_, n_, s_, t_)
{
    /* Initialize variables */
    hmm = {};                /* Initial HMM */
    obs = {};                /* Observation sequence */
    var a;
    var b;
    var pi;
    var obs_seq;
    var log_lik;           /* Output likelihood of FO */
    var mul;
    var m;
    var s = s_ || S, t = t_ || T;
    var n = n_ || N;
    var v_model= v_;
    var i;

    if(!v_model){
        console.log("invalid arguments, must specify varying model");
        return 1;
    }

    if(v_model == 'n')
    {
        /* Create observation sequence */
        obs.length = T;
        obs_seq = new Int32Array(T);
        for (i = 0; i < T; i++) {
            obs_seq[i] = 0;
        }
        obs.data = obs_seq;

        /* Run timed tests from 1*mul to 9*mul states */
        if (n >= 8000) {
            return 0;
        }
        // n = 7000;
        /* Assign HMM parameters */
        hmm.nstates = n;
        hmm.nsymbols = S;

        a = new Float32Array(n*n);
        for (i = 0; i < (n * n); i++) {
            a[i] = 1.0/n;
        }
        hmm.a = a;

        b = new Float32Array(n*s);
        for (i = 0; i < (n * S); i++) {
            b[i] = 1.0/S;
        }
        hmm.b = b;

        pi = new Float32Array(n);
        for (i = 0; i < n; i++) {
            pi[i] = 1.0/n;
        }
        hmm.pi = pi;


        /* Run the BWA on the observation sequence */
        var t1 = performance.now();
        log_lik = run_hmm_bwa(hmm, obs, ITERATIONS, 0);
        var t2 = performance.now();

        console.log("The time is " + (t2-t1)/1000 + " seconds");
        console.log("Observations\tLog_likelihood\n");
        console.log(n + "\t");
        console.log(log_lik + "\n");

    } else if(v_model == 's'){
        /* Create observation sequence */
        obs.length = T;
        obs_seq = new Int32Array(T);
        for (i = 0; i < T; i++) {
            obs_seq[i] = 0;
        }
        obs.data = obs_seq;

        if (s >= 8000) {
            return 0;
        }

        /* Assign HMM parameters */
        hmm.nstates = N;
        hmm.nsymbols = s;
        a = new Float32ARray(N*N);
        for (i = 0; i < (N * N); i++) {
            a[i] = 1.0/N;
        }
        hmm.a = a;
        b = new Float32Array(N*s);
        for (i = 0; i < (N * s); i++) {
            b[i] = 1.0/s;
        }
        hmm.b = b;
        pi = new Float32Array(N);
        for (i = 0; i < N; i++) {
            pi[i] = 1.0/N;
        }
        hmm.pi = pi;

        /* Run the BWA on the observation sequence */
        var t1 = performance.now();
        log_lik = run_hmm_bwa(hmm, obs, ITERATIONS, 0);
        var t2 = performance.now();

        console.log("The time is " + (t2-t1)/1000 + " seconds");
        console.log("Observations\tLog_likelihood\n");
        console.log(s +"\t");
        console.log(log_lik + "\n");

    } else if(v_model == 't')
    {
        if (t >= 10000) {
            return 0;
        }
        /* Create HMM */
        hmm.nstates = N;
        hmm.nsymbols = S;
        a = new Float32Array(N*N);
        for (i = 0; i < (N * N); i++) {
            a[i] = 1.0/N;
        }
        hmm.a = a;
        b = new Float32Array(N*S);
        for (i = 0; i < (N * S); i++) {
            b[i] = 1.0/S;
        }
        hmm.b = b;
        pi = new Float32Array(N);
        for (i = 0; i < N; i++) {
            pi[i] = 1.0/N;
        }
        hmm.pi = pi;

        /* Create observation sequence */
        obs.length = t;
        obs_seq = new Int32Array(t);
        for (i = 0; i < t; i++) {
            obs_seq[i] = 0;
        }
        obs.data = obs_seq;

        /* Run the BWA on the observation sequence */
        var t1 = performance.now();
        log_lik = run_hmm_bwa(hmm, obs, ITERATIONS, 0);
        var t2 = performance.now();

        console.log("The time is " + (t2-t1)/1000 + " seconds");
        console.log("Observations\tLog_likelihood\n");
        console.log(t + "\t");
        console.log(log_lik + "\n");
    }
    return { status: 1,
             options: "bwa_hmm(" + [v_, n_, s_, t_].join(",") + ")",
             time: (t2-t1)/1000 };
}
