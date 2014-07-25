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

(function()
{
    /// Random number generator (RNG) used
    var rng;

    /**
    Set the random number generator (RNG) to be used
    */
    function setRNG(gen)
    {
        if (!gen.hasOwnProperty('randomUInt31') ||
            !gen.hasOwnProperty('setRandSeed'))
        {
            throw TypeError('RNG does not implement the required API');
        }

        rng = gen;
    }

    /**
    Set a random seed for the RNG
    */
    function setSeed(seed)
    {
        rng.setRandSeed(seed);
    }

    /**
    Generate a random integer within [a, b[
    */
    function randInt(a, b)
    {
        var range = b - a;

        if (range < 0 | range > 0x7FFFFFF)
            throw RangeError('invalid range');

        // Force convert the range to integer
        range |= 0;

        var rnd = a + rng.randomUInt31() % range;

        return rnd;
    }

    /**
    Generate a random index value within [0, len[
    */
    function randIndex(len)
    {
        if (len < 0 | len > 0x7FFFFFF)
            throw RangeError('invalid length');

        // Force convert the length to integer
        len |= 0;

        var rnd = rng.randomUInt31() % len;

        return rnd;
    }

    /**
    Generate a random floating-point number within [a, b]
    */
    function randFloat(a, b)
    {
        if (a === undefined)
            a = 0;
        if (b === undefined)
            b = 1;

        if (a >= b)
            throw TypeError('invalid parameters to randomFloat')

        var range = b - a;

        var rndInt = Math.randomUInt31();
        var rnd = a + (rndInt / 0x7FFFFFFF) * range;

        return rnd;
    }

    /**
    Generate a random value from a normal distribution
    TODO: min and max values?
    */
    function randNormal(mean, variance)
    {
	    // Declare variables for the points and radius
        var x1, x2, w;

        // Repeat until suitable points are found
        do
        {
        	x1 = 2.0 * randFloat() - 1.0;
        	x2 = 2.0 * randFloat() - 1.0;
        	w = x1 * x1 + x2 * x2;
        } while (w >= 1.0 || w == 0);

        // compute the multiplier
        w = Math.sqrt((-2.0 * Math.log(w)) / w);

        // compute the gaussian-distributed value
        var gaussian = x1 * w;

        // Shift the gaussian value according to the mean and variance
        return (gaussian * variance) + mean;
    }

    /**
    Select a random indexed element of an array or string
    */
    function randElem(arr)
    {
        var idx = randIndex(arr.length);

        return arr[idx];
    }

    /**
    Selects a random argument
    */
    function randArg()
    {
        if ($argc === 0)
            throw TypeError("no arguments passed");

        var idx = randIndex($argc);

        return $ir_get_arg(idx);
    }

    /// By default, use the RNG provided by stdlib/math
    setRNG(Math);

    // Exported namespace
    exports = {
        setRNG: setRNG,
        setSeed: setSeed,

        int: randInt,
        index: randIndex,

        float: randFloat,
        normal: randNormal,

        elem: randElem,
        arg: randArg
    };

})();

