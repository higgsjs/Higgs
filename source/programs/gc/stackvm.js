function run(code, printStack)
{
    var stack = [];

    var pc = 0;

    stack.peek = function (idx)
    {
        if (idx === undefined)
            idx = 0;

        if (stack.length <= idx)
            print('warning: peeking at missing element');

        return stack[stack.length - 1 - idx];
    };

    stack.print = function ()
    {
        print('stack size: ' + stack.length);
        for (var i = 0; i < stack.length; ++i)
            print(i + ': ' + stack[i]);
    };

    while (pc < code.length)
    {
        //print('pc: ' + pc);

        var instr = code[pc];
        var op = instr[0];
        var args = instr.slice(1);

        //print(instr);
        //stack.print();

        ++pc;

        switch (op)
        {
            case 'push':
            stack.push(args[0]);
            break;
            
            case 'pop':
            stack.pop();
            break;

            case 'dup':
            var v = stack.peek();
            stack.push(v);
            break;

            case 'swap':
            var v0 = stack.pop();
            var v1 = stack.pop();
            stack.push(v0);
            stack.push(v1);
            break;

            case 'add':
            var v0 = stack.pop();
            var v1 = stack.pop();
            stack.push(v1 + v0);
            break;

            case 'sub':
            var v0 = stack.pop();
            var v1 = stack.pop();
            stack.push(v1 - v0);
            break;

            case 'jlt':
            var v0 = stack.pop();
            var v1 = stack.pop();
            if (v1 < v0)
                pc = args[0];
            break;

            case 'call':
            stack.push(pc);
            pc = args[0];
            break;

            case 'ret':
            var ra = stack.pop();
            pc = ra;
            break;

            case 'exit':
            pc = code.length;
            break;
        }
    }

    if (printStack === true)
        stack.print();

    return stack.peek();
}

function vmTest()
{
    var r = run(
        [
            ['push', 1]
        ], 
        false
    );
    if (r !== 1)
        return 1;

    var r = run(
        [
            ['push', 'foo'],
            ['push', 1],
            ['add']
        ], 
        false
    );
    if (r !== 'foo1')
        return 2;

    var r = run(
        [
            ['push', 'foo'],
            ['push', 1],
            ['swap']
        ], 
        false
    );
    if (r !== 'foo')
        return 3;

    var r = run(
        [
            ['push', 0],
            ['dup'],
            ['push', 1],
            ['jlt', 500],
            ['push', 5]
        ], 
        false
    );
    if (r !== 0)
        return 4;

    var r = run(
        [
            // n = 3
            ['push', 3],

            // Call f(3)
            ['call', 3],

            // Stop execution
            ['exit'],

            // Entry point for f(n)
            ['swap'],

            ['push', 1],
            ['add'],

            ['swap'],
            ['ret']
        ], 
        false
    );
    if (r !== 4)
        return 5;

    // Fibonacci
    var r = run(
        [
            // n = 8
            ['push', 8],

            // Call fib(n)
            ['call', 3],

            // Stop execution
            ['exit'],

            // stack:
            // n
            // ra

            //
            // fib(n) entry point
            //
            ['swap'],

            // stack:
            // ra
            // n

            // if (n < 2) goto ret
            ['dup'],
            ['push', 2],
            ['jlt', 16],

            // stack:
            // ra
            // n

            // Compute n - 1
            ['dup'],
            ['push', 1],
            ['sub'],

            // stack:
            // ra
            // n
            // n - 1

            // Compute fib(n-1)
            ['call', 3],

            // stack:
            // ra
            // n
            // fib(n-1)

            // Compute n - 2
            ['swap'],
            ['push', 2],
            ['sub'],

            // stack:
            // ra
            // fib(n-1)
            // n-2

            // Compute fib(n-2)
            ['call', 3],

            // stack:
            // ra
            // fib(n-1)
            // fib(n-2)

            // Compute fib(n-1) + fib(n-2)
            ['add'],

            // stack:
            // ra
            // fib(n-1) + fib(n-2)

            // Return to caller
            ['swap'],
            ['ret']
        ], 
        false
    );
    if (r !== 21)
        return 3;

    return 0;
}

function test()
{
    // Shrink the heap for testing
    $rt_shrinkHeap(500000);

    var gcCount = $ir_get_gc_count();

    while ($ir_get_gc_count() < gcCount + 2)
    {
        var r = vmTest();

        if (r !== 0)
            return r;
    }

    return 0;
}

