assert (typeof Date === 'function');

assert (typeof (new Date()).getTime() === 'number');

// Ensure that the time value increases
var startTime = (new Date()).getTime();
for (;;)
{
    var curTime = (new Date()).getTime();
    if (curTime > startTime)
        break;
}

