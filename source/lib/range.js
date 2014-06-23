/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2011, Maxime Chevalier-Boisvert. All rights reserved.
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

/**
Provides different types of ranges.
*/

(function()
{

    var EmptyValue = {};

    /**
    InputRange -
        a default implementation of an InputRange
    */
    function Input()
    {
        if (!(this instanceof Input))
            return new Input();
        this._empty = false;
        this._front = EmptyValue;
    }

    Input.prototype.empty = function()
    {
        return this._empty;
    };

    Input.prototype.front = function()
    {
        return this._front;
    };

    Input.prototype.popFront = function()
    {
        this._empty = true;
        return undefined;
    };

    Input.prototype.forEach = function(cb)
    {
        while(true)
        {
            this.popFront();
            if (!this.empty())
                cb(this.front());
            else
                break;
        }

        return this;
    };

    Input.prototype.toArray = function()
    {
        var arr = [];
        while(true)
        {
            this.popFront();
            if (!this.empty())
                arr.push(this.front());
            else
                break;
        }

        return arr;
    };

    Input.prototype.filter = function(predicate)
    {
        return new FilteredInput(this, predicate);
    }

    Input.prototype.map = function(mapper)
    {
        return new MappedInput(this, mapper);
    }

    /**
    ProxiedInput -
        a range that acts as a  proxy for an input range
    */
    function ProxiedInput(r)
    {
        if (!(this instanceof ProxiedInput))
            return new ProxiedInput(r);

        // TODO: error/arg checking
        this._r = r;
    }

    ProxiedInput.prototype = Input();

    ProxiedInput.prototype.empty = function()
    {
        return this._r.empty();
    }

    ProxiedInput.prototype.front = function()
    {
        return this._r.front();
    }

    ProxiedInput.prototype.popFront = function()
    {
        return this._r.popFront();
    }


    /**
    FilteredInput -
        An input range that filters out values that fail the predicate.
    */
    function FilteredInput(r, predicate)
    {
        if (!(this instanceof FilteredInput))
            return new FilteredInput(r, predicate);
        this._r = r;
        this._predicate = predicate;
    }

    FilteredInput.prototype = ProxiedInput();

    FilteredInput.prototype.popFront = function()
    {
        var next_val;
        var r = this._r;
        var predicate = this._predicate;

        while (true)
        {
            r.popFront();
            if (r.empty() === true)
                return  EmptyValue;

            next_val = r.front();
            if (predicate(next_val))
                return next_val;
        }
    }

    /**
    MappedInput -
        An input range that transforms all values with a mapper function.
    */
    function MappedInput(r, mapper)
    {
        if (!(this instanceof MappedInput))
            return new MappedInput(r, mapper);
        this._r = r;
        this._mapper = mapper;
    }

    MappedInput.prototype = ProxiedInput();

    MappedInput.prototype.front = function()
    {
        return this._mapper(this._r.front());
    }

    /**
    EXPORTS
    */
    exports = {
        EmptyValue : EmptyValue,
        Input : Input
    };
})()

