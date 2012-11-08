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

module interp.layout;

import std.stdio;
import std.string;
import std.array;
import std.conv;
import interp.interp;

alias ubyte*    rawptr;
alias ubyte*    refptr;

alias byte      int8;
alias short     int16;
alias int       int32;
alias long      int64;

alias ubyte     uint8;
alias ushort    uint16;
alias uint      uint32;
alias ulong     uint64;

alias double    float64;

/**
Layout field descriptor
*/
struct Field
{
    string name;

    string type;

    string szFieldName = "";

    Field* szField = null;

    bool isSzField = false;

    size_t size = 0;

    string sizeStr = "";
}

/**
Compile-time mixin function to generate code for object layouts
from a specification.

Generates:
- layout_comp_size(size1, ..., sizeN)
- layout_init(ptr)
- layout_sizeof(ptr)
- layout_ofs_field(ptr[,idx])
- layout_get_field(ptr[,idx])
- layout_set_field(ptr[,idx])
*/
string genLayout(string name, Field[] fields)
{
    auto output = appender!string();

    auto pref = name ~ "_";
    auto ofsPref = pref ~ "ofs_";
    auto getPref = pref ~ "get_";
    auto setPref = pref ~ "set_";

    // For each field
    for (size_t i = 0; i < fields.length; ++i)
    {
        auto field = &fields[i];

        // Get the field size
        if (field.type == "int8" || field.type == "uint8")
            field.size = 8;
        else if (field.type == "int16" || field.type == "uint16")
            field.size = 16;
        else if (field.type == "int32" || field.type == "uint32")
            field.size = 32;
        else if (field.type == "int64" || field.type == "uint64")
            field.size = 64;
        else if (field.type == "refptr" || field.type == "rawptr")
            field.size = 64;
        else
            assert (false, "unsupported field type");
        field.sizeStr = to!string(field.size);

        // Find the size field
        if (field.szFieldName != "")
        {
            for (size_t j = 0; j < i; ++j)
            {
                auto prev = &fields[j];

                if (prev.name == field.szFieldName)
                {
                    field.szField = prev;
                    prev.isSzField = true;
                }
            }

            assert (
                field.szField !is null, 
                "size field not found for " ~ field.name
            );
        }
    }

    // Generate offset methods
    foreach (i, field; fields)
    {
        output.put("size_t " ~ ofsPref ~ field.name ~ "(refptr o");
        if (field.szField)
            output.put(", size_t i");
        output.put(")\n");
        output.put("{\n");
        output.put("    return 0");

        for (size_t j = 0; j < i; ++j)
        {
            auto prev = fields[j];
            output.put(" + ");
            output.put(prev.sizeStr);
            if (prev.szField !is null)
                output.put(" * " ~ getPref ~ prev.szField.name ~ "(o)");
        }

        if (field.szField)
            output.put(" + " ~ field.sizeStr ~ " * i");

        output.put(";\n");
        output.put("}\n\n");
    }

    // Generate getter methods
    foreach (i, field; fields)
    {
        output.put(field.type ~ " " ~ getPref ~ field.name ~ "(refptr o");
        if (field.szField)
            output.put(", size_t i");
        output.put(")\n");
        output.put("{\n");
        output.put("    return *cast(" ~ field.type ~ "*)");
        output.put("(o + " ~ ofsPref ~ field.name ~ "(o");
        if (field.szField)
            output.put(", i");
        output.put("));\n");
        output.put("}\n\n");
    }

    // Generate setter methods
    foreach (i, field; fields)
    {
        output.put("void " ~ setPref ~ field.name ~ "(refptr o");
        if (field.szField)
            output.put(", size_t i");
        output.put(", " ~ field.type ~ " v)\n");
        output.put("{\n");
        output.put("    *cast(" ~ field.type ~ "*)");
        output.put("(o + " ~ ofsPref ~ field.name ~ "(o");
        if (field.szField)
            output.put(", i");
        output.put("))");
        output.put(" = v;\n");
        output.put("}\n\n");
    }

    // Generate the layout size computation function
    output.put("size_t " ~ name ~ "_comp_size(");
    Field[] szFields = [];
    foreach (field; fields)
        if (field.isSzField)
            szFields ~= field;
    foreach (i, field; szFields)
    {
        if (i > 0)
            output.put(", ");
        output.put(field.type ~ " " ~ field.name);
    }
    output.put(")\n");
    output.put("{\n");
    output.put("    return 0");
    foreach (i, field; fields)
    {
        output.put(" + ");
        output.put(field.sizeStr);
        if (field.szField)
            output.put(" * " ~ field.szField.name);
    }
    output.put(";\n");
    output.put("}\n\n");

    // Generate the sizeof method
    output.put("size_t " ~ name ~ "_sizeof(refptr o)\n");
    output.put("{\n");
    output.put("    return " ~ name ~ "_comp_size(");
    foreach (i, field; szFields)
    {
        if (i > 0)
            output.put(", ");
        output.put(getPref ~ field.name ~ "(o)");
    }
    output.put(");\n");
    output.put("}\n\n");

    // Generate the allocation function
    output.put("auto " ~ name ~ "_alloc(Interp interp");
    foreach (i, field; szFields)
    {
        output.put(", ");
        output.put(field.type ~ " " ~ field.name);
    }
    output.put(")\n");
    output.put("{\n");
    output.put("    auto obj = interp.alloc(" ~ name ~ "_comp_size(");
    foreach (i, field; szFields)
    {
        if (i > 0)
            output.put(", ");
        output.put(field.name);
    }
    output.put("));\n");
    foreach (i, field; szFields)
    {
        output.put("    " ~ name ~ "_set_" ~ field.name ~ "(obj," ~ field.name ~ ");\n");
    }
    output.put("    return obj;\n");
    output.put("}\n\n");

    // Return the generated code
    return output.data;
}

// String layout
mixin(
//pragma(msg,
genLayout(
    "str",
    [
        Field("type", "uint32"),
        Field("len" , "uint32"),
        Field("hash", "uint32"),
        Field("data", "uint16", "len")
    ]
));

// String table layout
mixin(
//pragma(msg, 
genLayout(
    "strtbl",
    [
        // Layout type
        Field("type", "uint32"),

        // Capacity
        Field("len" , "uint32"),

        // Number of strings
        Field("num_strs" , "uint32"),

        // Array of strings
        Field("str", "refptr", "len"),
    ]
));

// Object layout
mixin(
//pragma(msg, 
genLayout(
    "obj",
    [
        // Layout type
        Field("type", "uint32"),

        // Number of fields
        Field("len" , "uint32"),

        // Class reference
        Field("class", "refptr"),

        // Next object reference
        Field("next", "refptr"),

        // Prototype reference
        Field("proto", "refptr"),

        // Property words
        Field("word", "uint64", "len"),

        // Property types
        Field("type", "uint8", "len")
    ]
));

// Closure layout (extends object)
mixin(
//pragma(msg, 
genLayout(
    "clos",
    [
        // Layout type
        Field("type", "uint32"),

        // Number of fields
        Field("len" , "uint32"),

        // Class reference
        Field("class", "refptr"),

        // Next object reference
        Field("next", "refptr"),

        // Prototype reference
        Field("proto", "refptr"),

        // Property words
        Field("word", "uint64", "len"),

        // Property types
        Field("type", "uint8", "len"),

        // Function code pointer
        Field("fptr", "rawptr"),

        // Number of closure cells
        Field("num_cells" , "uint32"),

        // Closure cell pointers
        Field("cell", "refptr", "num_cells"),
    ]
));

// Class descriptor layout
mixin(
//pragma(msg, 
genLayout(
    "class",
    [
        // Layout type
        Field("type", "uint32"),

        // Class id / source origin location
        Field("id" , "uint32"),

        // Number of properties in class
        Field("num_props" , "uint32"),

        // Capacity, supported number of fields
        Field("len" , "uint32"),

        // Next class version reference
        // Used if class is reallocated
        Field("next", "refptr"),

        // TODO
        // array element type

        // Property names
        Field("prop_name", "refptr", "len"),

        // Property types
        Field("prop_type", "uint64", "len"),

        // Property indices
        Field("prop_idx", "uint32", "len"),
    ]
));

/*
Need layouts for:
- class desc
- array table
- closure cell

Objects:
- Allocation sites correspond to equivalence classes
- Can have multiple layouts for objects of a given class
  - Preferred layout used on allocation

How will we modify objects? Only to add fields?
- If so, objects only need a numFields value, next pointer
  - Next points to reallocated layout, if any
- Class descriptor can provide list of fields w/ types, offsets ***
- If object has no slot for field, reallocate object, set next pointer

Arrays, functions as objects?
- Different header bits?
- Could have extended separate payload section

Class Descriptor Layout:
-------------------------
Type id (32 bits)
-------------------------
Num fields (32 bits)
-------------------------
Class id / origin location (64 bits)
-------------------------
array type | woffset | toffset (4+ words)
-------------------------
* Field name | type desc | woffset | toffset (4+ words)

Object prototype (__proto__) can be slot 0
- Has associated type info in class desc

Functions can use object slots for fn ptr, closure vars as well?
- fn ptr slot (raw ptr)
- fixed number of closure vars (can be named)

Arrays?
- ISSUE: layout needs to be able to compute its own size
- ISSUE: need length, capacity values
- ISSUE: need many array slots
- Class desc needs:
  array type
  array offset
- Array needs custom layout
*/

