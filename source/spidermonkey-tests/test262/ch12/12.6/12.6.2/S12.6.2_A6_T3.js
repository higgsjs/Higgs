// Copyright 2009 the Sputnik authors.  All rights reserved.
// This code is governed by the BSD license found in the LICENSE file.

/**
 * Expression in "while" IterationStatement is bracketed with braces
 *
 * @path ch12/12.6/12.6.2/S12.6.2_A6_T3.js
 * @description Checking if execution of "while true break" fails
 * @negative
 */

//////////////////////////////////////////////////////////////////////////////
//CHECK#1
while true break;
//
//////////////////////////////////////////////////////////////////////////////

