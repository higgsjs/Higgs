// The Great Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// contributed by Ian Osgood

function A(i,j) {
  return 1/((i+j)*(i+j+1)/2+i+1);
}

function Au(u,v) {
  for (var i=0; i<u.length; ++i) {
    var t = 0;
    for (var j=0; j<u.length; ++j)
      t += A(i,j) * u[j];
    v[i] = t;
  }
}

function Atu(u,v) {
  for (var i=0; i<u.length; ++i) {
    var t = 0;
    for (var j=0; j<u.length; ++j)
      t += A(j,i) * u[j];
    v[i] = t;
  }
}

function AtAu(u,v,w) {
  Au(u,w);
  Atu(w,v);
}

function spectralnorm(n) {
  var i, u=[], v=[], w=[], vv=0, vBv=0;
  for (i=0; i<n; ++i) {
    u[i] = 1; v[i] = w[i] = 0;
  }
  for (i=0; i<10; ++i) {
    AtAu(u,v,w);
    AtAu(v,u,w);
  }
  for (i=0; i<n; ++i) {
    vBv += u[i]*v[i];
    vv  += v[i]*v[i];
  }
  return Math.sqrt(vBv/vv);
}

function benchmarkFun()
{
    for (var i = 6; i <= 48; i *= 2) {
        spectralnorm(i);
    }
}


// By performing warmup runs, we abstract out compilation time, standard
// library and runtime initialization time, as well as part of the benchmark
// initialization time (global function definitions). We cannot remove garbage
// collection time from the final timing run, however.

function timeFun(fun, numItrs)
{
    var startTime = (new Date()).getTime();

    for (var i = 0; i < numItrs; ++i)
        fun();

    var endTime = (new Date()).getTime();

    return endTime - startTime;
}

if (typeof benchmarkFun != 'function')
    throw Error('benchmarkFun not defined!');

// Benchmarking time (to be measured)
var benchTime = 0.0;

// Number of timing iterations, minimum 10
var numItrs = 10;

// Warmup iterations
timeFun(benchmarkFun, 100);

// Compute the number of iterations needed to get
// at least 1000ms of execution time
while (timeFun(benchmarkFun, numItrs) < 1000)
    numItrs *= 2;

// Timing runs, several iterations
benchTime = timeFun(benchmarkFun, numItrs) / numItrs;

print('num itrs:', numItrs);
print('exec time (ms):', benchTime);

