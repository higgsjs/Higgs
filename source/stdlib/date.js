/* _________________________________________________________________________
 *
 *             Tachyon : A Self-Hosted JavaScript Virtual Machine
 *
 *
 *  This file is part of the Tachyon JavaScript project. Tachyon is
 *  distributed at:
 *  http://github.com/Tachyon-Team/Tachyon
 *
 *
 *  Copyright (c) 2011-2014, Universite de Montreal
 *  All rights reserved.
 *
 *  This software is licensed under the following license (Modified BSD
 *  License):
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are
 *  met:
 *    * Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *    * Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *    * Neither the name of the Universite de Montreal nor the names of its
 *      contributors may be used to endorse or promote products derived
 *      from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 *  IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 *  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 *  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL UNIVERSITE DE
 *  MONTREAL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 *  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 *  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 *  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 *  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * _________________________________________________________________________
 */

/**
@fileOverview
Implementation of ECMAScript 5 Date methods and prototype.

@author
Maxime Chevalier-Boisvert, Olivier Matz

@copyright
Copyright (c) 2011 Tachyon Javascript Engine, All Rights Reserved
*/

Date = (function () {

/**
   Time constants.
*/
var DAYS_PER_4YEARS = 3 * 365 + 366;
var DAYS_PER_100YEARS = 25 * DAYS_PER_4YEARS - 1;
var DAYS_PER_400YEARS = 4 * DAYS_PER_100YEARS + 1;
var MS_PER_DAY = 86400000;
var MS_PER_HOUR = 3600000;
var MS_PER_MINUTE = 60000;
var MS_PER_SECOND = 1000;
var TIME_YEAR_2000 = 946684800000;

var WEEK_DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/**
   15.9.1.3 DaysInYear(y)
   Returns the numbers of day in a year.
*/
function DaysInYear (
    y
)
{
    if (y % 4 !== 0)
        return 365;
    if (y % 100 !== 0)
        return 366;
    if (y % 400 !== 0)
        return 365;
    return 366;
}

/**
   15.9.1.3 DayFromYear(y)
   Returns the day number of the first day of a year.
*/
function DayFromYear (
    y
)
{
    return 365 * (y - 1970) +
        Math.floor(((y - 1969) / 4)) -
        Math.floor(((y - 1901)/100)) +
        Math.floor(((y - 1601)/400));
}

/**
   DayFromMonth(m, inLeapYear)
   Returns the day number of the first day of a month within a year.
*/
function DayFromMonth (
    m,
    inLeapYear
)
{
    switch (m)
    {
    case 0:
        return 0;

    case 1:
        return 31;

    case 2:
        return 59 + inLeapYear;

    case 3:
        return 90 + inLeapYear;

    case 4:
        return 120 + inLeapYear;

    case 5:
        return 151 + inLeapYear;

    case 6:
        return 181 + inLeapYear;

    case 7:
        return 212 + inLeapYear;

    case 8:
        return 243 + inLeapYear;

    case 9:
        return 273 + inLeapYear;

    case 10:
        return 304 + inLeapYear;

    case 11:
        return 334 + inLeapYear;
    }
}

/**
   15.9.1.3 TimeFromYear(y)
   Returns the time value of the start of a year.
*/
function TimeFromYear (
    y
)
{
    return DayFromYear(y) * MS_PER_DAY;
}

/**
   15.9.1.9 InLeapYear(y)
   Returns 1 if the year is a leap year, 0 otherwise.
*/
function InLeapYear (
    y
)
{
    return DaysInYear(y) - 365;
}

/**
   yearFromTime(t)
   Set the year property of the current this object from a time value.
   Returns the time offset within the year of the given time value.
*/
function yearFromTime (
    t
)
{
    var year = 2000;
    var side, offset, step;

    // Compute the offset between the time value and the first day of 2000.
    if (t < TIME_YEAR_2000)
    {
        side = -1;
        offset = TIME_YEAR_2000 - t;
    }
    else
    {
        side = 1;
        offset = t - TIME_YEAR_2000;
    }

    // Step of 400 years chunk.
    step = Math.floor(offset / (DAYS_PER_400YEARS * MS_PER_DAY));
    year += side * 400 * step;
    offset -= step * DAYS_PER_400YEARS * MS_PER_DAY;

    // Step of 100 years chunk.
    step = Math.floor(offset / (DAYS_PER_100YEARS * MS_PER_DAY));
    year += side * 100 * step;
    offset -= step * DAYS_PER_100YEARS * MS_PER_DAY;

    // Step of 4 years chunk.
    step = Math.floor(offset / (DAYS_PER_4YEARS * MS_PER_DAY));
    year += side * 4 * step;
    offset -= step * DAYS_PER_4YEARS * MS_PER_DAY;

    // Compute the year within the 4 years chunk.
    if (offset > 0)
    {
        if (side > 0)
        {
            if ((offset - 366 * MS_PER_DAY) < 0)
            {
                this.__yr__ = year;
                return offset;
            }
            else
            {
                offset -= 366 * MS_PER_DAY;
                step = Math.floor(offset / (365 * MS_PER_DAY));
                offset -= step * 365 * MS_PER_DAY;
                this.__yr__ = year + step + 1;
                return offset;
            }
        }
        else
        {
            step = Math.floor(offset / (365 * MS_PER_DAY));
            offset -= step * 365 * MS_PER_DAY;
            this.__yr__ = year - (step > 3 ? 3 : step) - (offset > 0 ? 1 : 0);
            return offset;
        }
    }
    this.__yr__ = year;

    return offset;
}

/**
   monthFromTime(t, inLeapYear)
   Set the month property of the current this object from a relative
   time value within the year. Returns the time offset within the day
   of the given time value.
*/
function monthAndDayFromTime (
    t,
    inLeapYear
)
{
    var day = Math.floor(t / MS_PER_DAY);
    var dayInMonth;
    var month;

    if (0 <= day && day < 31)
    {
        month = 0;
        dayInMonth = day;
    }
    else if (31 <= day && day < 59 + inLeapYear)
    {
        month = 1;
        dayInMonth = day - 31;
    }
    else if (59 + inLeapYear <= day && day < 90 + inLeapYear)
    {
        month = 2;
        dayInMonth = day - 59 + inLeapYear;
    }
    else if (90 + inLeapYear <= day && day < 120 + inLeapYear)
    {
        month = 3;
        dayInMonth = day - 90 + inLeapYear;
    }
    else if (120 + inLeapYear <= day && day < 151 + inLeapYear)
    {
        month = 4;
        dayInMonth = day - 120 + inLeapYear;
    }
    else if (151 + inLeapYear <= day && day < 181 + inLeapYear)
    {
        month = 5;
        dayInMonth = day - 151 + inLeapYear;
    }
    else if (181 + inLeapYear <= day && day < 212 + inLeapYear)
    {
        month = 6;
        dayInMonth = day - 181 + inLeapYear;
    }
    else if (212 + inLeapYear <= day && day < 243 + inLeapYear)
    {
        month = 7;
        dayInMonth = day - 212 + inLeapYear;
    }
    else if (243 + inLeapYear <= day && day < 273 + inLeapYear)
    {
        month = 8;
        dayInMonth = day - 243 + inLeapYear;
    }
    else if (273 + inLeapYear <= day && day < 304 + inLeapYear)
    {
        month = 9;
        dayInMonth = day - 273 + inLeapYear;
    }
    else if (304 + inLeapYear <= day && day < 334 + inLeapYear)
    {
        month = 10;
        dayInMonth = day - 304 + inLeapYear;
    }
    else if (334 + inLeapYear <= day && day < 365 + inLeapYear)
    {
        month = 11;
        dayInMonth = day - 334 + inLeapYear;
    }

    this.__dt__ = dayInMonth + 1;
    this.__m__ = month;

    return t - (day * MS_PER_DAY);
}

/**
   15.9.1.11 MakeTime(hour, min, sec, ms)
*/
function MakeTime (
    hour,
    min,
    sec,
    ms
)
{
    return hour * MS_PER_HOUR + min * MS_PER_MINUTE + sec * MS_PER_SECOND + ms;
}

/**
   15.9.1.12 MakeDay(hour, min, sec, ms)
*/
function MakeDay (
    year,
    month,
    date
)
{
    return DayFromYear(year) + DayFromMonth(month, InLeapYear(year)) + date - 1;
}

/**
   computeDate()
   Set each date property of the current this object from its time value.
*/
function computeDate ()
{
    var value = this.__value__;

    this.__wd__ = ((Math.floor(value / MS_PER_DAY)) + 3) % 7;

    value = yearFromTime.call(this, value);

    value = monthAndDayFromTime.call(this, value, InLeapYear(this.__yr__));

    this.__h__ = Math.floor(value / MS_PER_HOUR);
    value -= this.__h__ * MS_PER_HOUR;

    this.__min__ = Math.floor(value / MS_PER_MINUTE);
    value -= this.__min__ * MS_PER_MINUTE;

    this.__s__ = Math.floor(value / MS_PER_SECOND);
    value -= this.__s__ * MS_PER_SECOND;

    this.__milli__ = value;
}

/**
   computeTimeValue()
   Set the time value property of the current this object from its date properties.
*/
function computeTimeValue ()
{
    this.__value__ = MakeDay(this.__yr__, this.__m__, this.__dt__) * MS_PER_DAY +
        MakeTime(this.__h__, this.__min__, this.__s__, this.__milli__);
}

function parseDate (
    date
)
{
    var index = 0;
    var positive = true;

    this.__yr__ = 0;
    this.__m__ = 0;
    this.__h__ = 0;
    this.__min__ = 0;
    this.__s__ = 0;
    this.__milli__ = 0;

    function current ()
    {
        if (index < date.length)
            return date.charCodeAt(index);
        else
            return null;
    }

    function numberClass (
        c
    )
    {
        return (c >= 48 && c <= 57); // 0-9
    }

    function parseNumber ()
    {
        var c, n = 0;

        for (c = current(); c !== null && numberClass(c); index++, c = current())
            n = n * 10 + (c - 48);
        return n;
    }

    if (current() === 43) // '+'
    {
        index++;
    }
    else if (current() === 45) // '-'
    {
        index++;
        positive = false;
    }

    this.__yr__ = (positive ? parseNumber() : -parseNumber());

    if (current() !== 45) // '-'
        return;
    index++;
    
    if (!numberClass(current()))
        return;
    this.__m__ = parseNumber();

    if (current() !== 45) // '-'
        return;
    index++;

    if (!numberClass(current()))
        return;

    this.__dt__ = parseNumber();

    if (current() !== 84) // 'T'
        return;
    index++;

    if (!numberClass(current()))
        return;
    this.__h__ = parseNumber();

    if (current() !== 58) // ':'
        return;
    index++;

    if (!numberClass(current()))
        return;
    this.__min__ = parseNumber();

    if (current() !== 58) // ':'
        return;
    index++;

    if (!numberClass(current()))
        return;
    this.__s__ = parseNumber();

    if (current() !== 46) // '.'
        return;
    index++;

    if (!numberClass(current()))
        return;
    this.__milli__ = parseNumber();

    computeTimeValue.call(this);
}

/**
   15.9.3 The Date function/constructor
   new Date ([year [, month [, date [, hours [, minutes [, seconds [, ms]]]]]]])
   new Date ()
   Date ([year [, month [, date [, hours [, minutes [, seconds [, ms]]]]]]])
   Date()
*/
function Date (
    year,
    month,
    date,
    hours,
    minutes,
    seconds,
    ms
)
{
    if (arguments.length < 2)
    {
        if (typeof year === "string" || year instanceof String)
        {
            parseDate.call(this, year.valueOf());
        }
        else
        {
            if (year === undefined)
                // No arguments given : build the Date object with current time.
                this.__value__ = $ir_get_time_ms();
            else if (typeof year === "number" || year instanceof Number)
                this.__value__ = year.valueOf();
            else
                this.__value__ = 0;

            computeDate.call(this);
        }
    }
    else if (arguments.length > 1)
    {
        // Date ([year [, month [, date [, hours [, minutes [, seconds [, ms]]]]]]])
        // Get arguments value : set default value for undefined arguments and
        // parse for integer for non-number arguments.
        var y = (typeof year === "number" ? year : parseInt(year.toString()));
        this.__yr__ = (y !== NaN && y >= 0 && y <= 99 ? y + 1900 : y);
        this.__m__ = (typeof month === "number" ? month : parseInt(month.toString()));
        this.__dt__ = (date === undefined ? 1 : (typeof date === "number" ? date : parseInt(date.toString())));
        this.__h__ = (hours === undefined ? 0 : (typeof hours === "number" ? hours : parseInt(hours.toString())));
        this.__min__ = (minutes === undefined ? 0 : (typeof minutes === "number" ? minutes : parseInt(minutes.toString())));
        this.__s__ = (seconds === undefined ? 0 : (typeof seconds === "number" ? seconds : parseInt(seconds.toString())));
        this.__milli__ = (ms === undefined ? 0 : (typeof seconds === "number" ? seconds : parseInt(seconds.toString())));

        computeTimeValue.call(this);

        this.__wd__ = ((Math.floor(this.__value__ / MS_PER_DAY)) + 3) % 7;
    }
}

/**
   15.9.5.1 Date.prototype.constructor
*/
Date.prototype.constructor = Date;

/**
   15.9.4.2 Date.parse (string)
*/
Date.parse = function (string)
{
    return new Date(string).valueOf();
}

/**
   15.9.4.3 Date.UTC(year, month [, date [, hours [, minutes [, seconds [, ms]]]]])
*/
Date.UTC = function (year, month, date, hours, minutes, seconds, ms)
{
    return new Date(year, month, date, hours, minutes, seconds, ms).valueOf();
}

/**
   15.9.4.4 Date.now()
*/
Date.now = function ()
{
    return new Date().valueOf();
}

/**
   15.9.5.3 Date.prototype.toDateString()
*/
Date.prototype.toDateString = function ()
{
    // TODO
}

/**
   15.9.5.4 Date.prototype.toTimeString()
*/
Date.prototype.toTimeString = function ()
{
    // TODO
}

/**
   15.9.5.5 Date.prototype.toLocaleString()
*/
Date.prototype.toLocaleString = function ()
{
    return this.toString();
}   

/**
   15.9.5.6 Date.prototype.toLocaleDateString()
*/
Date.prototype.toLocaleDateString = function ()
{
    return this.toDateString();
}

/**
   15.9.5.7 Date.prototype.toLocaleTimeString()
*/
Date.prototype.toLocaleTimeString = function ()
{
    return this.toTimeString();
}

/**
   15.9.5.8 Date.prototype.valueOf()
*/
Date.prototype.valueOf = function ()
{
    return this.__value__;
}

/**
   15.9.5.9 Date.prototype.getTime()
*/
Date.prototype.getTime = function ()
{
    return this.__value__;
};

/**
   15.9.5.10 Date.prototype.getFullYear()
*/
Date.prototype.getFullYear = function ()
{
    return this.__yr__;
}

/**
   15.9.5.11 Date.prototype.getUTCFullYear()
*/
Date.prototype.getUTCFullYear = function ()
{
    return this.getFullYear();
}

/**
   15.9.5.12 Date.prototype.getMonth()
*/
Date.prototype.getMonth = function ()
{
    return this.__m__;
}

/**
   15.9.5.13 Date.prototype.getUTCMonth()
*/
Date.prototype.getUTCMonth = function ()
{
    return this.getMonth();
}

/**
   15.9.5.14 Date.prototype.getDate()
*/
Date.prototype.getDate = function ()
{
    return this.__dt__;
}

/**
   15.9.5.15 Date.prototype.getUTDate()
*/
Date.prototype.getUTDate = function ()
{
    return this.getDate();
}

/**
   15.9.5.16 Date.prototype.getDay()
*/
Date.prototype.getDay = function ()
{
    return this.__dt__;
}

/**
   15.9.5.17 Date.prototype.getUTCDay()
*/
Date.prototype.getUTCDay = function ()
{
    return this.getDay();
}

/**
   15.9.5.18 Date.prototype.getHours()
*/
Date.prototype.getHours = function ()
{
    return this.__h__;
}

/**
   15.9.5.19 Date.prototype.getUTCHours()
*/
Date.prototype.getUTCHours = function ()
{
    return this.getHours();
}

/**
   15.9.5.20 Date.prototype.getMinutes()
*/
Date.prototype.getMinutes = function ()
{
    return this.__min__;
}

/**
   15.9.5.21 Date.prototype.getUTCMinutes()
*/
Date.prototype.getUTCMinutes = function ()
{
    return this.getMinutes();
}

/**
   15.9.5.22 Date.prototype.getSeconds()
*/
Date.prototype.getSeconds = function ()
{
    return this.__s__;
}

/**
   15.9.5.23 Date.prototype.getUTCSeconds()
*/
Date.prototype.getUTCSeconds = function ()
{
    return this.getSeconds();
}

/**
   15.9.5.24 Date.prototype.getMilliseconds()
*/
Date.prototype.getMilliseconds = function ()
{
    return this.__milli__;
}

/**
   15.9.5.25 Date.prototype.getUTCMilliseconds()
*/
Date.prototype.getUTCMilliseconds = function ()
{
    return this.getMilliseconds();
}

/**
   15.9.5.26 Date.prototype.getTimezoneOffset()
*/
Date.prototype.getTimezoneOffset = function ()
{
}

/**
   15.9.5.27 Date.prototype.setTime (time)
*/
Date.prototype.setTime = function (
    time
)
{
    this.__value__ = time;
    computeDate.call(this);
}

/**
   15.9.5.28 Date.prototype.setMilliseconds (ms)
*/
Date.prototype.setMilliseconds = function (
    ms
)
{
    this.__milli__ = ms;
    computeTimeValue.call(this);
}

/**
   15.9.5.29 Date.prototype.setUTCMilliseconds (ms)
*/
Date.prototype.setUTCMilliseconds = function (
    ms
)
{
    this.setMilliseconds(ms);
    computeTimeValue.call(this);
}

/**
   15.9.5.30 Date.prototype.setSeconds (sec [, ms])
*/
Date.prototype.setSeconds = function (
    sec,
    ms
)
{
    this.__s__ = sec;
    if (ms !== undefined)
        this.__milli__ = ms;
    computeTimeValue.call(this);
}

/**
   15.9.5.31 Date.prototype.setUTCSeconds (sec [, ms])
*/
Date.prototype.setUTCSeconds = function (
    sec,
    ms
)
{
    this.setSeconds(sec, ms);
}

/**
   15.9.5.32 Date.prototype.setMinutes (min [, sec [, ms]])
*/
Date.prototype.setMinutes = function (
    min,
    sec,
    ms
)
{
    this.__min__ = min;
    if (sec !== undefined)
        this.__s__ = sec;
    if (ms !== undefined)
        this.__ms__ = ms;
    computeTimeValue.call(this);
}

/**
   15.9.5.33 Date.prototype.setUTCMinutes (min [, sec [, ms]])
*/
Date.prototype.setUTCMinutes = function (
    min,
    sec,
    ms
)
{
    this.setMinutes(min, sec, ms);
}

/**
   15.9.5.34 Date.prototype.setHours (hour [, min [, sec [, ms]]])
*/
Date.prototype.setHours = function (
    hour,
    min,
    sec,
    ms
)
{
    this.__h__ = hour;
    if (min !== undefined)
        this.__min__ = min;
    if (sec !== undefined)
        this.__s__ = sec;
    if (ms !== undefined)
        this.__ms__ = ms;
    computeTimeValue.call(this);
}

/**
   15.9.5.35 Date.prototype.setUTCHours (hour [, min [, sec [, ms]]])
*/
Date.prototype.setUTCHours = function (
    hour,
    min,
    sec,
    ms
)
{
    this.setHours(hour, min, sec, ms);
}

/**
   15.9.5.36 Date.prototype.setDate (date)
*/
Date.prototype.setDate = function (
    date
)
{
    this.__dt__ = date;
    computeTimeValue.call(this);
}

/**
   15.9.5.37 Date.prototype.setUTCDate (date)
*/
Date.prototype.setUTCDate = function (
    date
)
{
    this.setDate(date);
}

/**
   15.9.5.38 Date.prototype.setMonth (month [, date])
*/
Date.prototype.setMonth = function (
    month,
    date
)
{
    this.__m__ = month;
    if (date !== undefined)
        this.__dt__ = date;
    computeTimeValue.call(this);
}

/**
   15.9.5.39 Date.prototype.setUTCMonth (month [, date])
*/
Date.prototype.setUTCMonth = function (
    month,
    date
)
{
    this.setMonth(month, date);
}

/**
   15.9.5.40 Date.prototype.setFullYear (year [, month [, date]])
*/
Date.prototype.setFullYear = function (
    year,
    month,
    date
)
{
    this.__yr__ = year;
    if (month !== undefined)
        this.__m__ = month;
    if (date !== undefined)
        this.__dt__ = date;
    computeTimeValue.call(this);
}

/**
   15.9.5.41 Date.prototype.setUTCFullYear (year [, month [, date]])
*/
Date.prototype.setUTCFullYear = function (
    year,
    month,
    date
)
{
    this.setFullYear(year, month, date);
}

/**
   15.9.5.42 Date.prototype.toUTCString()
*/
Date.prototype.toUTCString = function ()
{
    return this.toISOString();
}

/**
   15.9.5.43 Date.prototype.toISOString()
*/
Date.prototype.toISOString = function ()
{
    var s, parts = [];

    parts.push(this.__yr__.toString());

    parts.push("-");

    s = (this.__m__ + 1).toString();
    if (s.length < 2)
        s = "0" + s;
    parts.push(s);

    parts.push("-");

    s = this.__dt__.toString();
    if (s.length < 2)
        s = "0" + s;
    parts.push(s);

    parts.push("T");

    s = this.__h__.toString();
    if (s.length < 2)
        s = "0" + s;
    parts.push(s);

    parts.push(":");

    s = this.__min__.toString();
    if (s.length < 2)
        s = "0" + s;
    parts.push(s);

    parts.push(":");

    s = this.__s__.toString();
    if (s.length < 2)
        s = "0" + s;
    parts.push(s);

    parts.push(".");

    s = this.__milli__.toString();
    if (s.length === 1)
        s = "00" + s;
    else if (s.length === 2)
        s = "0" + s;
    parts.push(s);

    parts.push("Z");

    return parts.join("");
}

/**
   15.9.5.2 Date.prototype.toString()
*/
Date.prototype.toString = function ()
{
    var parts = [], s;

    parts.push(WEEK_DAYS[this.__wd__]);
    
    parts.push(" ");
    
    parts.push(MONTHS[this.__m__]);
    
    parts.push(" ");

    s = this.__dt__.toString();
    if (s.length < 2)
        s = "0" + s;
    parts.push(s);

    parts.push(" ");

    parts.push(this.__yr__.toString());

    parts.push(" ");

    s = this.__h__.toString();
    if (s.length < 2)
        s = "0" + s;
    parts.push(s);

    parts.push(":");

    s = this.__min__.toString();
    if (s.length < 2)
        s = "0" + s;
    parts.push(s);

    parts.push(":");

    s = this.__s__.toString();
    if (s.length < 2)
        s = "0" + s;
    parts.push(s);

    return parts.join("");
}

/**
   15.9.5.44 Date.prototype.toJSON(key)
*/
Date.prototype.toJSON = function ()
{
    return this.toISOString();
}

return Date;

})();
