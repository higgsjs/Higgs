/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013, Maxime Chevalier-Boisvert. All rights reserved.
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

module ir.inlining;

import std.stdio;
import std.string;
import ir.ir;

/**
Inline a callee function at a call site
*/
void inlineCall(IRInstr callSite, IRFunction callee)
{
    assert (callSite.opcode is &CALL);
    assert (callSite.excTarget is null);

    assert (callee.ast.usesArguments == false);

    auto caller = callSite.block.fun;
    assert (caller !is null);

    // Don't support new, avoids complicated return logic

    // Don't inline if exception target set


    // TODO: should copy caller blocks?





    // TODO: extend caller frame to store all callee locals
    // - rename caller locals (make offset higher)
    // ISSUE: inlining multiple functions, don't want to add more locals each time
    // Can we pre-extend the caller frame? Not very convenient
    // Could extend at each inlining, compact frame in separate pass
    // - compute liveness, perform allocation/coloring
    // Can do many inlinings, extend stack frame a lot, compact at the end?


    // ISSUE: stack frame inflation/spilling
    // Probably want to keep track of callers, depth of inlining
    // Don't want wildly different layout from separate frames w/o inlining





    // TODO: test for callee before jumping
    // Need to test that the IRFunction matches
    // clos_get_fptr? Don't want to add another function call, dude
    // - need to load it directly from the closure, need fixed offset
    // eq_rawptr




    // TODO: translate the return slot
    auto retSlot = callSite.outSlot;


    // TODO: copy callee code into caller
    // - move args into locals
    // - write undef into missing args
    // - move return value into ret slot





    /*
    TODO:

    If we optimize an inlined function and remove temps/vars, need to somehow
    know what temps map to which original function temps
    - could use special pseudo-instr to manage this
    - place pseudo-instr before possible bailout points: function calls, throw
    */






}

