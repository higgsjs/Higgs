// The Great Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// contributed by David Hedbor
// modified by  Isaac Gouy

var SIZE = 10000;

function test_lists()
{
  var Li1, Li2, Li3;
  var tmp;
  // create a list of integers from 1 to SIZE.
  Li1 = new Array();
  for(tmp = 1; tmp <= SIZE; tmp++) Li1.push(tmp);
  // copy the list to Li2.
  Li2 = Li1.concat();

  // remove each element from left side of Li2 and append to
  // the right side of Li3 (preserving order)
  Li3 = new Array();

  while( (tmp = Li2.shift()) ) {
    Li3.push(tmp);
  }

  // Li2 is now empty.
  // Remove each element from right side of Li3 and append to right
  // side of Li2
  while( (tmp = Li3.pop()) ) {
    Li2.push(tmp);
  }

  // Li2 is now reversed, and Li3 empty.
  // Reverse Li1 in place.
  Li1.reverse();
  if( Li1[0] != SIZE ) return 0;
  // compare Li1 and Li2 for equality, and return the length of the list.
  for(tmp = 0; tmp < SIZE; tmp++)
    if( Li1[tmp] != Li2[tmp] ) return 0;
  return Li1.length;
}

var n = arguments[0];
var resultl

while( n-- )
  result = test_lists();

print(result );
