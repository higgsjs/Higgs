function test(iter)
{
    //var result = -1;;
    var obj1;

    for (var i=iter|0; i>0; i--) 
    {
        //result = i;
        obj1 = {field1:i+1, field2:i+2, field3:i+3};
    }

    //return [result, obj1];
}

var iter = 1000000;

var startTime = (new Date()).getTime();
test(iter);
var endTime = (new Date()).getTime();

var totalTime = endTime - startTime;

print('total time: ', totalTime);

print('gc count: ', $ir_get_gc_count());


