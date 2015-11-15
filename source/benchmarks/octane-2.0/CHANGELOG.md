#History

##11/6/2013 - Octane 2.0

This update adds latency and asm.js-like tests to the Octane benchmark suite.

Octane 2.0 brings focus on new aspects of JS performance: latency and asm.js-like code. By instrumenting Splay and Mandreel, it is now possible to calculate scores for compiler and garbage collection latencies. the [zlib](https://github.com/kripken/emscripten/tree/master/tests/zlib) benchmark from the [Emscripten](https://github.com/kripken/emscripten) test suite is also included to keep track of this new technology. Finally, the [Typescript](http://www.typescriptlang.org/) compiler from Microsoft, which is run exactly once, measures startup and execution of a very complex javascript application.

##8/21/2012 - Octane v.1

Welcome to the first release of Octane!

Octane builds upon the V8 Benchmark Suite and adds five new tests, taken without modification (beside glue / boilerplate logic) from well known, existing Web and JS applications: Mozilla's pdf.js, Mandreel, GB Emulator, CodeLoad, Box2DWeb.

Have a look at the official Chromium [blog post](http://blog.chromium.org/2012/08/octane-javascript-benchmark-suite-for.html) for more details or check the [benchmark page](https://developers.google.com/octane/benchmark) for a detailed explanation of each test. If you are still looking for answers, the [FAQ page](https://developers.google.com/octane/faq) might help you.
