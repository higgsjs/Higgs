// The Great Computer Language Shootout
// http://shootout.alioth.debian.org/
//
// contributed by David Hedbor
// modified by Sjoerd Visscher


function Toggle(start_state) {
   this.state = start_state;
}

Toggle.prototype.value = function() {
   return this.state;
}

Toggle.prototype.activate = function() {
   this.state = !this.state;
   return this;
}


function NthToggle (start_state, max_counter) {
   Toggle.call(this, start_state);
   this.count_max = max_counter;
   this.count = 0;
}

NthToggle.prototype = new Toggle;

NthToggle.prototype.activate = function() {
   if (++this.count >= this.count_max) {
     this.state = !this.state;
     this.count = 0;
   }
   return this;
}

var n = arguments[0];
var i;
var val = true;
var toggle = new Toggle(val);
for (i=0; i<n; i++) {
  val = toggle.activate().value();
}
print(toggle.value() ? "true" : "false");

val = true;
var ntoggle = new NthToggle(val, 3);
for (i=0; i<n; i++) {
  val = ntoggle.activate().value();
}
print(ntoggle.value() ? "true" : "false");
