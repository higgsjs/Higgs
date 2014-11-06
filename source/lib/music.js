/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2013-2014, Maxime Chevalier-Boisvert. All rights reserved.
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

(function(exports)
{
    //============================================================================
    // Note representation
    //============================================================================

    /**
    Number of MIDI notes
    */
    var NUM_NOTES = 128;

    /**
    Number of notes per octave
    */
    var NOTES_PER_OCTAVE = 12;

    /**
    Number of cents per octave
    */
    var CENTS_PER_OCTAVE = 1200;

    /**
    Frequency of the A4 note
    */
    var A4_NOTE_FREQ = 440;

    /**
    Note number of the A4 note
    */
    var A4_NOTE_NO = 69;

    /**
    Note number of the C4 note
    */
    var C4_NOTE_NO = 71;

    /**
    Mapping from note names to pitch classes
    */
    var NOTE_NAME_PC = {
        'C' : 0,
        'C#': 1,
        'D' : 2,
        'D#': 3,
        'E' : 4,
        'F' : 5,
        'F#': 6,
        'G' : 7,
        'G#': 8,
        'A' : 9,
        'A#': 10,
        'B' : 11
    };

    /**
    Mapping from pitch classes to note names
    */
    var PC_NOTE_NAME = {
        0   : 'C',
        1   : 'C#',
        2   : 'D',
        3   : 'D#',
        4   : 'E',
        5   : 'F',
        6   : 'F#',
        7   : 'G',
        8   : 'G#',
        9   : 'A',
        10  : 'A#',
        11  : 'B'
    };

    /**
    @class Represents note values.

    Midi note numbers go from 0 to 127.

    A4 is tuned to 440Hz, and corresponds to midi note 69.

    F(n) = 440 * (2^(1/12))^(n - 69)
         = 440 * 2 ^ ((n-69)/12)
    */
    function Note(val)
    {
        // If we got a note name, convert it to a note number
        if (typeof val === 'string')
            val = Note.nameToNo(val);

        assert (
            typeof val === 'number',
            'invalid note number'
        );

        if (Note.notesByNo[val] !== undefined)
            return Note.notesByNo[val];

        // Create a note object
        var note = Object.create(Note.prototype);
        note.noteNo = val;

        // Store the note object in the note table
        Note.notesByNo[val] = note;

        return note;
    }

    /**
    Array of note numbers to note objects
    */
    Note.notesByNo = [];

    /**
    Get the note number for a note name
    */
    Note.nameToNo = function (name)
    {
        // Use a regular expression to parse the name
        var matches = name.match(/([A-G]#?)([0-9])/i);

        assert (
            matches !== null,
            'invalid note name: "' + name + '"'
        );

        var namePart = matches[1];
        var numPart = matches[2];

        var pc = NOTE_NAME_PC[namePart];

        assert (
            typeof pc === 'number',
            'invalid note name: ' + namePart
        );

        var octNo = parseInt(numPart);

        // Compute the note number
        var noteNo = (octNo + 1) * NOTES_PER_OCTAVE + pc;

        assert (
            noteNo >= 0 || noteNo < NUM_NOTES,
            'note parsing failed'
        );

        return noteNo;
    }

    /**
    Sorting function for note objects
    */
    Note.sortFn = function (n1, n2)
    {
        return n1.noteNo - n2.noteNo;
    }

    /**
    Get the pitch class
    */
    Note.prototype.getPC = function ()
    {
        return this.noteNo % NOTES_PER_OCTAVE;
    }

    /**
    Get the octave number
    */
    Note.prototype.getOctNo = function ()
    {
        return Math.floor(this.noteNo / NOTES_PER_OCTAVE) - 1;
    }

    /**
    Get the name for a note
    */
    Note.prototype.getName = function ()
    {
        // Compute the octave number of the note
        var octNo = this.getOctNo();

        // Get the pitch class for this note
        var pc = this.getPC();

        var name = PC_NOTE_NAME[pc];

        // Add the octave number to the note name
        name += String(octNo);

        return name;
    }

    /**
    The string representation of a note is its name
    */
    Note.prototype.toString = Note.prototype.getName;

    /**
    Get the frequency for a note
    @param offset detuning offset in cents
    */
    Note.prototype.getFreq = function (offset)
    {
        if (offset === undefined)
            offset = 0;

        // F(n) = 440 * 2 ^ ((n-69)/12)
        var noteExp = (this.noteNo - A4_NOTE_NO) / NOTES_PER_OCTAVE;

        // b = a * 2 ^ (o / 1200)
        var offsetExp = offset / CENTS_PER_OCTAVE;

        // Compute the note frequency
        return A4_NOTE_FREQ * Math.pow(
            2, 
            noteExp + offsetExp
        );
    }

    /**
    Offset a note by a number of semitones
    */
    Note.prototype.offset = function (numSemis)
    {
        var offNo = this.noteNo + numSemis;

        assert (
            offNo >= 0 && offNo < NUM_NOTES,
            'invalid note number after offset'
        );

        return new Note(offNo);
    }

    /**
    Shift a note to higher or lower octaves
    */
    Note.prototype.shift = function (numOcts)
    {
        return this.offset(numOcts * NOTES_PER_OCTAVE);
    }

    //============================================================================
    // Intervals, scales and chords
    //============================================================================

    /**
    Name the interval between two notes
    */
    function nameInterv(n1, n2)
    {
        // TODO

        // Count all the pitch names present, including the notes themselves (ignore sharps and flats at this point).

        // Find out (had it been missing a flat or sharp) what type of interval it would be, depending on whether it is perfect (a 1,4,5,8) or major (2,6,7). 

        // If there are no sharps or flats, you are done. If there are, figure out if the flat or sharp decreases or increases the distance between the two pitches. 
        // If it increases the distance, the interval is augmented. 
        // If it decreases the distance, and the interval would otherwise be perfect, it is diminished. 
        // If it decreases the distance and the interval would otherwise be major, it is minor.
    }

    /**
    Interval consonance table
    */
    var intervCons = {
        0 :  3, // Unison
        1 : -3, // Minor second
        2 : -1, // Major second

        3 :  3, // Minor third
        4 :  3, // Major third
        5 :  1, // Perfect fourth

        6 : -1, // Tritone
        7 :  3, // Perfect fifth
        8 :  1, // Minor sixth

        9 :  2, // Major sixth
        10: -1, // Minor seventh
        11: -2  // Major seventh
    };

    /**
    Consonance rating function for two notes
    */
    function consonance(n1, n2)
    {
        var no1 = n1.noteNo;
        var no2 = n2.noteNo;

        var diff = Math.max(no1 - no2, no2 - no1);

        // Compute the simple interval between the two notes
        var interv = diff % 12;

        return intervCons[interv];
    }

    /**
    Semitone intervals for different scales
    */
    var scaleIntervs = {

        // Major scale
        'major': [2, 2, 1, 2, 2, 2],

        // Natural minor scale
        'natural minor': [2, 1, 2, 2, 1, 2],

        // Major pentatonic scale
        'major pentatonic': [2, 2, 3, 2],

        // Minor pentatonic scale
        'minor pentatonic': [3, 2, 2, 3],

        // Blues scale
        'blues': [3, 2, 1, 1, 3],

        // Chromatic scale
        'chromatic': [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    };

    /**
    Generate the notes of a scale based on a root note
    */
    function genScale(rootNote, scale, numOctaves)
    {
        if ((rootNote instanceof Note) === false)
            rootNote = new Note(rootNote);

        if (numOctaves === undefined)
            numOctaves = 1;

        // Get the intervals for this type of chord
        var intervs = scaleIntervs[scale];

        assert (
            intervs instanceof Array,
            'invalid scale name: ' + scale
        );

        // List of generated notes
        var notes = [];

        // For each octave
        for (var octNo = 0; octNo < numOctaves; ++octNo)
        {
            var octRoot = rootNote.shift(octNo);

            // Add the root note to the scale
            notes.push(octRoot);

            // Add the scale notes
            for (var i = 0; i < intervs.length; ++i)
            {
                var prevNote = notes[notes.length-1];

                var interv = intervs[i];

                notes.push(prevNote.offset(interv));
            }
        }

        // Add the note closing the last octave
        notes.push(rootNote.shift(numOctaves));

        return notes;
    }

    /**
    Semitone intervals for different kinds of chords
    */
    var chordIntervs = {

        // Major chord
        'maj':  [0, 4, 7],

        // Minor chord
        'min':  [0, 3, 7],

        // Diminished chord
        'dim':  [0, 3, 6],

        // Major 7th
        'maj7': [0, 4, 7, 11],

        // Minor 7th
        'min7': [0, 3, 7, 10],

        // Diminished 7th chord
        'dim7': [0, 3, 6, 9],

        // Dominant 7th
        '7':    [0, 4, 7, 10],     

        // Suspended 4th
        'sus4': [0, 5, 7],

        // Suspended second
        'sus2': [0, 2, 7]
    };

    /**
    Generate a list of notes for a chord
    */
    function genChord(rootNote, type)
    {
        if ((rootNote instanceof Note) === false)
            rootNote = new Note(rootNote);

        // Get the intervals for this type of chord
        var intervs = chordIntervs[type];

        assert (
            intervs instanceof Array,
            'invalid chord type: ' + type
        );

        // Get the root note number
        var rootNo = rootNote.noteNo;

        // Compute the note numbers for the notes
        var notes = intervs.map(function (i) { return new Note(rootNo + i); });

        return notes;
    }

    // Exported namespace
    exports.Note = Note;
    exports.consonance = consonance;
    exports.genScale = genScale;
    exports.genChord = genChord;

})(exports)

