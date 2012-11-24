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
import util.string;

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
Layout type id
*/
alias uint32 LayoutType;

/**
Layout field descriptor
*/
struct Field
{
    string name;

    string type;

    string szFieldName = "";

    string initVal = "";

    Field* szField = null;

    bool isSzField = false;

    size_t size = 0;

    string sizeStr = "";
}

/**
Layout descriptor
*/
struct Layout
{
    string name;

    string baseName;

    Field[] fields;

    LayoutType type;
}

/**
Compile-time mixin function to generate code for all layouts at once
*/
string genLayouts(Layout[] layouts)
{
    // Find the base of a given layout
    Layout findBase(Layout* layout, size_t curIdx)
    {
        for (size_t j = 0; j < curIdx; ++j)
        {
            if (layouts[j].name == layout.baseName)
                return layouts[j];
        }

        assert (
            false, 
            "base layout not found: \"" ~ layout.baseName ~ "\""
        );
    }

    // Next layout id to be allocated
    LayoutType nextLayoutId = 1;

    auto outD = appender!string();
    auto outJS = appender!string();

    // For each layout to generate
    for (size_t i = 0; i < layouts.length; ++i)
    {
        Layout* layout = &layouts[i];

        // If this layout has a base
        if (layout.baseName !is null)
        {
            auto baseLayout = findBase(layout, i);

            // Copy the base layout fields, except the type field
            Field[] baseFields = [];
            for (size_t j = 1; j < baseLayout.fields.length; ++j)
            {
                auto field = baseLayout.fields[j];
                baseFields ~= Field(
                    field.name, 
                    field.type, 
                    field.szFieldName,
                    field.initVal
                );
            }

            // Prepend the base fields to this layout's fields
            layout.fields = baseFields ~ layout.fields;
        }

        // Assign a type id to the layout
        layout.type = nextLayoutId++;

        // Add the type as the first field
        auto typeField = Field(
            "type",
            "LayoutType",
            "",
            to!string(layout.type)
        );
        layout.fields = typeField ~ layout.fields;

        // Generate code for this layout
        genLayout(*layout, outD, outJS);
    }

    // Define a global constant for the JS layout code string
    outD.put(
        "immutable string JS_LAYOUT_CODE = \"" ~ 
        escapeDString(outJS.data)~ "\";\n"
    );

    return outD.data;
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
void genLayout(Layout layout, ref Appender!string outD, ref Appender!string outJS)
{
    auto name = layout.name;
    auto fields = layout.fields;

    auto pref = name ~ "_";
    auto ofsPref = pref ~ "ofs_";
    auto getPref = pref ~ "get_";
    auto setPref = pref ~ "set_";

    // Define the layout type constant
    outD.put(
        "const LayoutType LAYOUT_" ~ toUpper(name) ~ " = " ~ 
        to!string(layout.type) ~ ";\n\n"
    );

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
        else if (field.type == "LayoutType")
            field.size = LayoutType.sizeof;
        else
            assert (false, "unsupported field type " ~ field.type);
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

                    // Ensure the size field has no init value
                    assert (
                        prev.initVal == "",
                        "cannot specify init val for size fields"
                    );
                }
            }

            assert (
                field.szField !is null, 
                "size field \"" ~ field.szFieldName ~ "\" not found for \"" ~ 
                field.name ~ "\""
            );
        }
    }

    // Generate offset methods
    foreach (i, field; fields)
    {
        // D function
        outD.put("size_t " ~ ofsPref ~ field.name ~ "(refptr o");
        if (field.szField)
            outD.put(", size_t i");
        outD.put(")\n");
        outD.put("{\n");
        outD.put("    return 0");

        for (size_t j = 0; j < i; ++j)
        {
            auto prev = fields[j];
            outD.put(" + ");
            outD.put(prev.sizeStr);
            if (prev.szField !is null)
                outD.put(" * " ~ getPref ~ prev.szField.name ~ "(o)");
        }

        if (field.szField)
            outD.put(" + " ~ field.sizeStr ~ " * i");

        outD.put(";\n");
        outD.put("}\n\n");
    }

    // Generate getter methods
    foreach (i, field; fields)
    {
        outD.put(field.type ~ " " ~ getPref ~ field.name ~ "(refptr o");
        if (field.szField)
            outD.put(", size_t i");
        outD.put(")\n");
        outD.put("{\n");
        outD.put("    return *cast(" ~ field.type ~ "*)");
        outD.put("(o + " ~ ofsPref ~ field.name ~ "(o");
        if (field.szField)
            outD.put(", i");
        outD.put("));\n");
        outD.put("}\n\n");
    }

    // Generate setter methods
    foreach (i, field; fields)
    {
        outD.put("void " ~ setPref ~ field.name ~ "(refptr o");
        if (field.szField)
            outD.put(", size_t i");
        outD.put(", " ~ field.type ~ " v)\n");
        outD.put("{\n");
        outD.put("    *cast(" ~ field.type ~ "*)");
        outD.put("(o + " ~ ofsPref ~ field.name ~ "(o");
        if (field.szField)
            outD.put(", i");
        outD.put("))");
        outD.put(" = v;\n");
        outD.put("}\n\n");
    }

    // Generate the layout size computation function
    outD.put("size_t " ~ name ~ "_comp_size(");
    Field[] szFields = [];
    foreach (field; fields)
        if (field.isSzField)
            szFields ~= field;
    foreach (i, field; szFields)
    {
        if (i > 0)
            outD.put(", ");
        outD.put(field.type ~ " " ~ field.name);
    }
    outD.put(")\n");
    outD.put("{\n");
    outD.put("    return 0");
    foreach (i, field; fields)
    {
        outD.put(" + ");
        outD.put(field.sizeStr);
        if (field.szField)
            outD.put(" * " ~ field.szField.name);
    }
    outD.put(";\n");
    outD.put("}\n\n");

    // Generate the sizeof method
    outD.put("size_t " ~ name ~ "_sizeof(refptr o)\n");
    outD.put("{\n");
    outD.put("    return " ~ name ~ "_comp_size(");
    foreach (i, field; szFields)
    {
        if (i > 0)
            outD.put(", ");
        outD.put(getPref ~ field.name ~ "(o)");
    }
    outD.put(");\n");
    outD.put("}\n\n");

    // Generate the allocation function
    outD.put("auto " ~ name ~ "_alloc(Interp interp");
    foreach (i, field; szFields)
    {
        outD.put(", ");
        outD.put(field.type ~ " " ~ field.name);
    }
    outD.put(")\n");
    outD.put("{\n");
    outD.put("    auto obj = interp.alloc(" ~ name ~ "_comp_size(");
    foreach (i, field; szFields)
    {
        if (i > 0)
            outD.put(", ");
        outD.put(field.name);
    }
    outD.put("));\n");
    foreach (i, field; szFields)
    {
        outD.put("    " ~ name ~ "_set_" ~ field.name ~ "(obj," ~ field.name ~ ");\n");
    }
    foreach (i, field; fields)
    {
        if (field.initVal == "")
            continue;

        if (field.szField)
        {
            outD.put("    for (size_t i = 0; i < " ~ field.szFieldName ~ "; ++i)\n");
            outD.put("        " ~ name ~ "_set_" ~ field.name ~ "(obj, i," ~ field.initVal ~");\n");
        }
        else
        {
            outD.put("    " ~ name ~ "_set_" ~ field.name ~ "(obj, " ~ field.initVal ~");\n");
        }
    }
    outD.put("    return obj;\n");
    outD.put("}\n\n");
}

mixin(
//pragma(msg,
genLayouts([

    // String layout
    Layout(
        "str",
        null,
        [
            // String length
            Field("len" , "uint32"),

            // Hash code
            Field("hash", "uint32"),

            // UTF-16 character data
            Field("data", "uint16", "len")
        ]
    ),

    // String table layout (for hash consing)
    Layout(
        "strtbl",
        null,
        [
            // Capacity, total number of slots
            Field("cap" , "uint32"),

            // Number of strings
            Field("num_strs" , "uint32", "", "0"),

            // Array of strings
            Field("str", "refptr", "cap", "null"),
        ]
    ),

    // Object layout
    Layout(
        "obj",
        null,
        [
            // Capacity, number of property slots
            Field("cap" , "uint32"),

            // Class reference
            Field("class", "refptr"),

            // Next object reference
            Field("next", "refptr", "", "null"),

            // Prototype reference
            Field("proto", "refptr"),

            // Property words
            Field("word", "uint64", "cap"),

            // Property types
            Field("type", "uint8", "cap")
        ]
    ),

    // Function/closure layout (extends object)
    Layout(
        "clos",
        "obj",
        [
            // Function code pointer
            Field("fptr", "rawptr"),

            // Number of closure cells
            Field("num_cells" , "uint32"),

            // Closure cell pointers
            Field("cell", "refptr", "num_cells"),
        ]
    ),

    // Array layout (extends object)
    Layout(
        "arr",
        "obj",
        [
            // Array table reference
            Field("tbl" , "refptr"),

            // Number of elements contained
            Field("len" , "uint32"),
        ]
    ),

    // Array table layout (contains array elements)
    Layout(
        "arrtbl",
        null,
        [
            // Array capacity
            Field("cap" , "uint32"),

            // Element words
            Field("word", "uint64", "cap"),

            // Element types
            Field("type", "uint8", "cap")
        ]
    ),

    // Class layout
    Layout(
        "class",
        null,
        [
            // Class id / source origin location
            Field("id" , "uint32"),

            // Capacity, total number of property slots
            Field("cap" , "uint32"),

            // Number of properties in class
            Field("num_props" , "uint32", "", "0"),

            // Next class version reference
            // Used if class is reallocated
            Field("next", "refptr", "", "null"),

            // Array element type
            Field("arr_type", "rawptr", "", "null"),

            // Property names
            Field("prop_name", "refptr", "cap", "null"),

            // Property types
            // Pointers to host type descriptor objects
            Field("prop_type", "rawptr", "cap", "null"),

            // Property indices
            Field("prop_idx", "uint32", "cap"),
        ]
    ),

]));

