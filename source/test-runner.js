/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2014, Maxime Chevalier-Boisvert. All rights reserved.
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

/*
Test-runner runs all js files in the specified dir in a forked instance of higgs.
If any tests fail the program exist abnormally (i.e. exit(1);)
*/

(function()
{
    var console = require("lib/console");
    var ffi = require("lib/ffi");
    var std = require("lib/stdlib");
    var fs = require("lib/dir");

    var test = require("lib/test");

    var tests_dir = "./tests";

    // Don't run tests in tests_dir/core
    // and don't run any files/dirs the user provides as arguments
    var ignores  = Object.create(null)
    ignores["core"] = true;
    global.arguments.forEach(
        function(n) { ignores[n] = true; }
    );

    // Stats for the tests
    var tests_run = 0;
    var tests_passed = 0;
    var tests_failed = 0;

    // Track which directory we're in
    var current = "";

    // Space for the exit status of the forked vm
    var child_status = std.malloc(4);

    function runTest(file)
    {
        file = current + "/" + file;
        console.log("Running: " + file + "...");

        // fork before running test
        var pid = ffi.c.fork();

        if (pid < 0)
        {
            console.log("FORK FAILED!");
            std.exit(1);
        }
        else if (pid === 0)
        {
            // run the test in this child process
            try
            {
                load(file);
            }
            catch (e)
            {
                if (typeof e === "object")
                    console.log(e.toString());
                else if (typeof e === "string")
                    console.log(e);

                std.exit(1);
            }

            std.exit(0);
        }
        else
        {
            // parent, wait for test to finish
            ffi.c.waitpid(pid, child_status, 0);
            tests_run +=1;

            // pull out return code and check for pass/fail
            var status = $ir_load_u32(child_status, 0);
            if (status !== 0)
            {
                console.log("***** FAILED! *****");
                tests_failed += 1;
            }
            else
            {
                tests_passed += 1;
            }
        }
    }

    function runTests(dir_name)
    {
        var dir = fs.dir(dir_name);

        // update where we are
        current = dir_name;

        // first run tests in this dir
        dir.getFileNames().sort().forEach(
            function(file)
            {
                if (!ignores[file] && file.split('.').pop() === "js")
                    runTest(file);
            }
        );

        // run tests in any subdirectories
        dir.getDirNames().sort().forEach(
            function(next_dir)
            {
                if (!ignores[next_dir])
                    runTests(dir_name + "/" + next_dir);
            }
        );
    }

    console.log("Starting test-runner.js...");
    console.log(" --- ");

    var startTime = new Date().getTime();

    // run tests
    runTests(tests_dir);

    var endTime = new Date().getTime();
    var totalTime = (endTime - startTime) / 1000;

    if (tests_run === 0)
    {
        console.log("NO TESTS RUN");
        std.exit(1);
    }

    console.log("test-runner.js results:");
    console.log(" --- ");
    console.log("Tests run:", tests_run);
    if (tests_run !== tests_passed)
        console.log("Tests passed:", tests_passed);
    console.log("Tests failed:", tests_failed);
    console.log("Total time: ", totalTime.toFixed(1) + " s");

    if (tests_failed > 0)
    {
        std.exit(1);
    }

})();

