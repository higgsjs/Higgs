a = { x:1 };
b = Object.create(a);
b.x = 2;

ka = [];
for (k in a) 
    ka.push(k);

kb = [];
for (k in b)
    kb.push(k);

//print('ka: ' + ka);
//print('kb: ' + kb);

assert (ka.length === kb.length);

