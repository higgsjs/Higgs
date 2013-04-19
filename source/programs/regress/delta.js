Object.prototype.inheritsFrom = function (parent) 
{
  function Inheriter() {}

  Inheriter.prototype = parent.prototype;

  this.prototype = new Inheriter();
}

function Constraint() 
{
}
Constraint.prototype.x = true;

function UnaryConstraint() 
{
}
UnaryConstraint.inheritsFrom(Constraint);
UnaryConstraint.prototype.y = 1337;

function EditConstraint(v, str) 
{
}
EditConstraint.inheritsFrom(UnaryConstraint);
EditConstraint.prototype.x = 777;             // <===== Corrupting statement

if (UnaryConstraint.prototype.x !== true)
    throw Error('UnaryConstraint.prototype.isInput was changed');

