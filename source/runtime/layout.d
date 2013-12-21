//
// Code auto-generated from "runtime/layout.py". Do not modify.
//

module runtime.layout;

import runtime.interp;
import runtime.gc;

alias ubyte* funptr;
alias ubyte* mapptr;
alias ubyte* rawptr;
alias ubyte* refptr;
alias byte   int8;
alias short  int16;
alias int    int32;
alias long   int64;
alias ubyte  uint8;
alias ushort uint16;
alias uint   uint32;
alias ulong  uint64;
alias double float64;

const uint32 LAYOUT_STR = 0;

extern (C) uint32 str_ofs_next(refptr o)
{    
    return 0;
}

extern (C) uint32 str_ofs_header(refptr o)
{    
    return (0 + 8);
}

extern (C) uint32 str_ofs_len(refptr o)
{    
    return ((0 + 8) + 4);
}

extern (C) uint32 str_ofs_hash(refptr o)
{    
    return (((0 + 8) + 4) + 4);
}

extern (C) uint32 str_ofs_data(refptr o, uint32 i)
{    
    return (((((0 + 8) + 4) + 4) + 4) + (2 * i));
}

extern (C) refptr str_get_next(refptr o)
{    
    return *cast(refptr*)(o + str_ofs_next(o));
}

extern (C) uint32 str_get_header(refptr o)
{    
    return *cast(uint32*)(o + str_ofs_header(o));
}

extern (C) uint32 str_get_len(refptr o)
{    
    return *cast(uint32*)(o + str_ofs_len(o));
}

extern (C) uint32 str_get_hash(refptr o)
{    
    return *cast(uint32*)(o + str_ofs_hash(o));
}

extern (C) uint16 str_get_data(refptr o, uint32 i)
{    
    return *cast(uint16*)(o + str_ofs_data(o, i));
}

extern (C) void str_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + str_ofs_next(o)) = v;
}

extern (C) void str_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + str_ofs_header(o)) = v;
}

extern (C) void str_set_len(refptr o, uint32 v)
{    
    *cast(uint32*)(o + str_ofs_len(o)) = v;
}

extern (C) void str_set_hash(refptr o, uint32 v)
{    
    *cast(uint32*)(o + str_ofs_hash(o)) = v;
}

extern (C) void str_set_data(refptr o, uint32 i, uint16 v)
{    
    *cast(uint16*)(o + str_ofs_data(o, i)) = v;
}

extern (C) uint32 str_comp_size(uint32 len)
{    
    return (((((0 + 8) + 4) + 4) + 4) + (2 * len));
}

extern (C) uint32 str_sizeof(refptr o)
{    
    return str_comp_size(str_get_len(o));
}

extern (C) refptr str_alloc(Interp interp, uint32 len)
{    
    auto o = interp.heapAlloc(str_comp_size(len));
    str_set_len(o, len);
    str_set_next(o, null);
    str_set_header(o, 0);
    return o;
}

extern (C) void str_visit_gc(Interp interp, refptr o)
{    
    str_set_next(o, gcForward(interp, str_get_next(o)));
}

const uint32 LAYOUT_STRTBL = 1;

extern (C) uint32 strtbl_ofs_next(refptr o)
{    
    return 0;
}

extern (C) uint32 strtbl_ofs_header(refptr o)
{    
    return (0 + 8);
}

extern (C) uint32 strtbl_ofs_cap(refptr o)
{    
    return ((0 + 8) + 4);
}

extern (C) uint32 strtbl_ofs_num_strs(refptr o)
{    
    return (((0 + 8) + 4) + 4);
}

extern (C) uint32 strtbl_ofs_str(refptr o, uint32 i)
{    
    return ((((((0 + 8) + 4) + 4) + 4) + 4) + (8 * i));
}

extern (C) refptr strtbl_get_next(refptr o)
{    
    return *cast(refptr*)(o + strtbl_ofs_next(o));
}

extern (C) uint32 strtbl_get_header(refptr o)
{    
    return *cast(uint32*)(o + strtbl_ofs_header(o));
}

extern (C) uint32 strtbl_get_cap(refptr o)
{    
    return *cast(uint32*)(o + strtbl_ofs_cap(o));
}

extern (C) uint32 strtbl_get_num_strs(refptr o)
{    
    return *cast(uint32*)(o + strtbl_ofs_num_strs(o));
}

extern (C) refptr strtbl_get_str(refptr o, uint32 i)
{    
    return *cast(refptr*)(o + strtbl_ofs_str(o, i));
}

extern (C) void strtbl_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + strtbl_ofs_next(o)) = v;
}

extern (C) void strtbl_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + strtbl_ofs_header(o)) = v;
}

extern (C) void strtbl_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + strtbl_ofs_cap(o)) = v;
}

extern (C) void strtbl_set_num_strs(refptr o, uint32 v)
{    
    *cast(uint32*)(o + strtbl_ofs_num_strs(o)) = v;
}

extern (C) void strtbl_set_str(refptr o, uint32 i, refptr v)
{    
    *cast(refptr*)(o + strtbl_ofs_str(o, i)) = v;
}

extern (C) uint32 strtbl_comp_size(uint32 cap)
{    
    return ((((((0 + 8) + 4) + 4) + 4) + 4) + (8 * cap));
}

extern (C) uint32 strtbl_sizeof(refptr o)
{    
    return strtbl_comp_size(strtbl_get_cap(o));
}

extern (C) refptr strtbl_alloc(Interp interp, uint32 cap)
{    
    auto o = interp.heapAlloc(strtbl_comp_size(cap));
    strtbl_set_cap(o, cap);
    strtbl_set_next(o, null);
    strtbl_set_header(o, 1);
    strtbl_set_num_strs(o, 0);
    for (uint32 i = 0; i < cap; ++i)
    {    
        strtbl_set_str(o, i, null);
    }
    return o;
}

extern (C) void strtbl_visit_gc(Interp interp, refptr o)
{    
    strtbl_set_next(o, gcForward(interp, strtbl_get_next(o)));
    auto cap = strtbl_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        strtbl_set_str(o, i, gcForward(interp, strtbl_get_str(o, i)));
    }
}

const uint32 LAYOUT_OBJ = 2;

extern (C) uint32 obj_ofs_next(refptr o)
{    
    return 0;
}

extern (C) uint32 obj_ofs_header(refptr o)
{    
    return (0 + 8);
}

extern (C) uint32 obj_ofs_cap(refptr o)
{    
    return ((0 + 8) + 4);
}

extern (C) uint32 obj_ofs_map(refptr o)
{    
    return (((0 + 8) + 4) + 4);
}

extern (C) uint32 obj_ofs_proto(refptr o)
{    
    return ((((0 + 8) + 4) + 4) + 8);
}

extern (C) uint32 obj_ofs_word(refptr o, uint32 i)
{    
    return ((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * i));
}

extern (C) uint32 obj_ofs_type(refptr o, uint32 i)
{    
    return (((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * obj_get_cap(o))) + (1 * i));
}

extern (C) refptr obj_get_next(refptr o)
{    
    return *cast(refptr*)(o + obj_ofs_next(o));
}

extern (C) uint32 obj_get_header(refptr o)
{    
    return *cast(uint32*)(o + obj_ofs_header(o));
}

extern (C) uint32 obj_get_cap(refptr o)
{    
    return *cast(uint32*)(o + obj_ofs_cap(o));
}

extern (C) mapptr obj_get_map(refptr o)
{    
    return *cast(mapptr*)(o + obj_ofs_map(o));
}

extern (C) refptr obj_get_proto(refptr o)
{    
    return *cast(refptr*)(o + obj_ofs_proto(o));
}

extern (C) uint64 obj_get_word(refptr o, uint32 i)
{    
    return *cast(uint64*)(o + obj_ofs_word(o, i));
}

extern (C) uint8 obj_get_type(refptr o, uint32 i)
{    
    return *cast(uint8*)(o + obj_ofs_type(o, i));
}

extern (C) void obj_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + obj_ofs_next(o)) = v;
}

extern (C) void obj_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + obj_ofs_header(o)) = v;
}

extern (C) void obj_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + obj_ofs_cap(o)) = v;
}

extern (C) void obj_set_map(refptr o, mapptr v)
{    
    *cast(mapptr*)(o + obj_ofs_map(o)) = v;
}

extern (C) void obj_set_proto(refptr o, refptr v)
{    
    *cast(refptr*)(o + obj_ofs_proto(o)) = v;
}

extern (C) void obj_set_word(refptr o, uint32 i, uint64 v)
{    
    *cast(uint64*)(o + obj_ofs_word(o, i)) = v;
}

extern (C) void obj_set_type(refptr o, uint32 i, uint8 v)
{    
    *cast(uint8*)(o + obj_ofs_type(o, i)) = v;
}

extern (C) uint32 obj_comp_size(uint32 cap)
{    
    return (((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * cap)) + (1 * cap));
}

extern (C) uint32 obj_sizeof(refptr o)
{    
    return obj_comp_size(obj_get_cap(o));
}

extern (C) refptr obj_alloc(Interp interp, uint32 cap)
{    
    auto o = interp.heapAlloc(obj_comp_size(cap));
    obj_set_cap(o, cap);
    obj_set_next(o, null);
    obj_set_header(o, 2);
    for (uint32 i = 0; i < cap; ++i)
    {    
        obj_set_word(o, i, MISSING.uint64Val);
    }
    for (uint32 i = 0; i < cap; ++i)
    {    
        obj_set_type(o, i, Type.CONST);
    }
    return o;
}

extern (C) void obj_visit_gc(Interp interp, refptr o)
{    
    obj_set_next(o, gcForward(interp, obj_get_next(o)));
    obj_set_proto(o, gcForward(interp, obj_get_proto(o)));
    auto cap = obj_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        obj_set_word(o, i, gcForward(interp, obj_get_word(o, i), obj_get_type(o, i)));
    }
}

const uint32 LAYOUT_CLOS = 3;

extern (C) uint32 clos_ofs_next(refptr o)
{    
    return 0;
}

extern (C) uint32 clos_ofs_header(refptr o)
{    
    return (0 + 8);
}

extern (C) uint32 clos_ofs_cap(refptr o)
{    
    return ((0 + 8) + 4);
}

extern (C) uint32 clos_ofs_map(refptr o)
{    
    return (((0 + 8) + 4) + 4);
}

extern (C) uint32 clos_ofs_proto(refptr o)
{    
    return ((((0 + 8) + 4) + 4) + 8);
}

extern (C) uint32 clos_ofs_word(refptr o, uint32 i)
{    
    return ((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * i));
}

extern (C) uint32 clos_ofs_type(refptr o, uint32 i)
{    
    return (((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * clos_get_cap(o))) + (1 * i));
}

extern (C) uint32 clos_ofs_ctor_map(refptr o)
{    
    return (((((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * clos_get_cap(o))) + (1 * clos_get_cap(o))) + 7) & -8);
}

extern (C) uint32 clos_ofs_num_cells(refptr o)
{    
    return ((((((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * clos_get_cap(o))) + (1 * clos_get_cap(o))) + 7) & -8) + 8);
}

extern (C) uint32 clos_ofs_cell(refptr o, uint32 i)
{    
    return (((((((((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * clos_get_cap(o))) + (1 * clos_get_cap(o))) + 7) & -8) + 8) + 4) + 4) + (8 * i));
}

extern (C) refptr clos_get_next(refptr o)
{    
    return *cast(refptr*)(o + clos_ofs_next(o));
}

extern (C) uint32 clos_get_header(refptr o)
{    
    return *cast(uint32*)(o + clos_ofs_header(o));
}

extern (C) uint32 clos_get_cap(refptr o)
{    
    return *cast(uint32*)(o + clos_ofs_cap(o));
}

extern (C) mapptr clos_get_map(refptr o)
{    
    return *cast(mapptr*)(o + clos_ofs_map(o));
}

extern (C) refptr clos_get_proto(refptr o)
{    
    return *cast(refptr*)(o + clos_ofs_proto(o));
}

extern (C) uint64 clos_get_word(refptr o, uint32 i)
{    
    return *cast(uint64*)(o + clos_ofs_word(o, i));
}

extern (C) uint8 clos_get_type(refptr o, uint32 i)
{    
    return *cast(uint8*)(o + clos_ofs_type(o, i));
}

extern (C) mapptr clos_get_ctor_map(refptr o)
{    
    return *cast(mapptr*)(o + clos_ofs_ctor_map(o));
}

extern (C) uint32 clos_get_num_cells(refptr o)
{    
    return *cast(uint32*)(o + clos_ofs_num_cells(o));
}

extern (C) refptr clos_get_cell(refptr o, uint32 i)
{    
    return *cast(refptr*)(o + clos_ofs_cell(o, i));
}

extern (C) void clos_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + clos_ofs_next(o)) = v;
}

extern (C) void clos_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + clos_ofs_header(o)) = v;
}

extern (C) void clos_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + clos_ofs_cap(o)) = v;
}

extern (C) void clos_set_map(refptr o, mapptr v)
{    
    *cast(mapptr*)(o + clos_ofs_map(o)) = v;
}

extern (C) void clos_set_proto(refptr o, refptr v)
{    
    *cast(refptr*)(o + clos_ofs_proto(o)) = v;
}

extern (C) void clos_set_word(refptr o, uint32 i, uint64 v)
{    
    *cast(uint64*)(o + clos_ofs_word(o, i)) = v;
}

extern (C) void clos_set_type(refptr o, uint32 i, uint8 v)
{    
    *cast(uint8*)(o + clos_ofs_type(o, i)) = v;
}

extern (C) void clos_set_ctor_map(refptr o, mapptr v)
{    
    *cast(mapptr*)(o + clos_ofs_ctor_map(o)) = v;
}

extern (C) void clos_set_num_cells(refptr o, uint32 v)
{    
    *cast(uint32*)(o + clos_ofs_num_cells(o)) = v;
}

extern (C) void clos_set_cell(refptr o, uint32 i, refptr v)
{    
    *cast(refptr*)(o + clos_ofs_cell(o, i)) = v;
}

extern (C) uint32 clos_comp_size(uint32 cap, uint32 num_cells)
{    
    return (((((((((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * cap)) + (1 * cap)) + 7) & -8) + 8) + 4) + 4) + (8 * num_cells));
}

extern (C) uint32 clos_sizeof(refptr o)
{    
    return clos_comp_size(clos_get_cap(o), clos_get_num_cells(o));
}

extern (C) refptr clos_alloc(Interp interp, uint32 cap, uint32 num_cells)
{    
    auto o = interp.heapAlloc(clos_comp_size(cap, num_cells));
    clos_set_cap(o, cap);
    clos_set_num_cells(o, num_cells);
    clos_set_next(o, null);
    clos_set_header(o, 3);
    for (uint32 i = 0; i < cap; ++i)
    {    
        clos_set_word(o, i, MISSING.uint64Val);
    }
    for (uint32 i = 0; i < cap; ++i)
    {    
        clos_set_type(o, i, Type.CONST);
    }
    clos_set_ctor_map(o, null);
    for (uint32 i = 0; i < num_cells; ++i)
    {    
        clos_set_cell(o, i, null);
    }
    return o;
}

extern (C) void clos_visit_gc(Interp interp, refptr o)
{    
    clos_set_next(o, gcForward(interp, clos_get_next(o)));
    clos_set_proto(o, gcForward(interp, clos_get_proto(o)));
    auto cap = clos_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        clos_set_word(o, i, gcForward(interp, clos_get_word(o, i), clos_get_type(o, i)));
    }
    auto num_cells = clos_get_num_cells(o);
    for (uint32 i = 0; i < num_cells; ++i)
    {    
        clos_set_cell(o, i, gcForward(interp, clos_get_cell(o, i)));
    }
}

const uint32 LAYOUT_CELL = 4;

extern (C) uint32 cell_ofs_next(refptr o)
{    
    return 0;
}

extern (C) uint32 cell_ofs_header(refptr o)
{    
    return (0 + 8);
}

extern (C) uint32 cell_ofs_word(refptr o)
{    
    return (((0 + 8) + 4) + 4);
}

extern (C) uint32 cell_ofs_type(refptr o)
{    
    return ((((0 + 8) + 4) + 4) + 8);
}

extern (C) refptr cell_get_next(refptr o)
{    
    return *cast(refptr*)(o + cell_ofs_next(o));
}

extern (C) uint32 cell_get_header(refptr o)
{    
    return *cast(uint32*)(o + cell_ofs_header(o));
}

extern (C) uint64 cell_get_word(refptr o)
{    
    return *cast(uint64*)(o + cell_ofs_word(o));
}

extern (C) uint8 cell_get_type(refptr o)
{    
    return *cast(uint8*)(o + cell_ofs_type(o));
}

extern (C) void cell_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + cell_ofs_next(o)) = v;
}

extern (C) void cell_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + cell_ofs_header(o)) = v;
}

extern (C) void cell_set_word(refptr o, uint64 v)
{    
    *cast(uint64*)(o + cell_ofs_word(o)) = v;
}

extern (C) void cell_set_type(refptr o, uint8 v)
{    
    *cast(uint8*)(o + cell_ofs_type(o)) = v;
}

extern (C) uint32 cell_comp_size()
{    
    return (((((0 + 8) + 4) + 4) + 8) + 1);
}

extern (C) uint32 cell_sizeof(refptr o)
{    
    return cell_comp_size();
}

extern (C) refptr cell_alloc(Interp interp)
{    
    auto o = interp.heapAlloc(cell_comp_size());
    cell_set_next(o, null);
    cell_set_header(o, 4);
    cell_set_word(o, UNDEF.uint64Val);
    cell_set_type(o, Type.CONST);
    return o;
}

extern (C) void cell_visit_gc(Interp interp, refptr o)
{    
    cell_set_next(o, gcForward(interp, cell_get_next(o)));
    cell_set_word(o, gcForward(interp, cell_get_word(o), cell_get_type(o)));
}

const uint32 LAYOUT_ARR = 5;

extern (C) uint32 arr_ofs_next(refptr o)
{    
    return 0;
}

extern (C) uint32 arr_ofs_header(refptr o)
{    
    return (0 + 8);
}

extern (C) uint32 arr_ofs_cap(refptr o)
{    
    return ((0 + 8) + 4);
}

extern (C) uint32 arr_ofs_map(refptr o)
{    
    return (((0 + 8) + 4) + 4);
}

extern (C) uint32 arr_ofs_proto(refptr o)
{    
    return ((((0 + 8) + 4) + 4) + 8);
}

extern (C) uint32 arr_ofs_word(refptr o, uint32 i)
{    
    return ((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * i));
}

extern (C) uint32 arr_ofs_type(refptr o, uint32 i)
{    
    return (((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * arr_get_cap(o))) + (1 * i));
}

extern (C) uint32 arr_ofs_tbl(refptr o)
{    
    return (((((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * arr_get_cap(o))) + (1 * arr_get_cap(o))) + 7) & -8);
}

extern (C) uint32 arr_ofs_len(refptr o)
{    
    return ((((((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * arr_get_cap(o))) + (1 * arr_get_cap(o))) + 7) & -8) + 8);
}

extern (C) refptr arr_get_next(refptr o)
{    
    return *cast(refptr*)(o + arr_ofs_next(o));
}

extern (C) uint32 arr_get_header(refptr o)
{    
    return *cast(uint32*)(o + arr_ofs_header(o));
}

extern (C) uint32 arr_get_cap(refptr o)
{    
    return *cast(uint32*)(o + arr_ofs_cap(o));
}

extern (C) mapptr arr_get_map(refptr o)
{    
    return *cast(mapptr*)(o + arr_ofs_map(o));
}

extern (C) refptr arr_get_proto(refptr o)
{    
    return *cast(refptr*)(o + arr_ofs_proto(o));
}

extern (C) uint64 arr_get_word(refptr o, uint32 i)
{    
    return *cast(uint64*)(o + arr_ofs_word(o, i));
}

extern (C) uint8 arr_get_type(refptr o, uint32 i)
{    
    return *cast(uint8*)(o + arr_ofs_type(o, i));
}

extern (C) refptr arr_get_tbl(refptr o)
{    
    return *cast(refptr*)(o + arr_ofs_tbl(o));
}

extern (C) uint32 arr_get_len(refptr o)
{    
    return *cast(uint32*)(o + arr_ofs_len(o));
}

extern (C) void arr_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + arr_ofs_next(o)) = v;
}

extern (C) void arr_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arr_ofs_header(o)) = v;
}

extern (C) void arr_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arr_ofs_cap(o)) = v;
}

extern (C) void arr_set_map(refptr o, mapptr v)
{    
    *cast(mapptr*)(o + arr_ofs_map(o)) = v;
}

extern (C) void arr_set_proto(refptr o, refptr v)
{    
    *cast(refptr*)(o + arr_ofs_proto(o)) = v;
}

extern (C) void arr_set_word(refptr o, uint32 i, uint64 v)
{    
    *cast(uint64*)(o + arr_ofs_word(o, i)) = v;
}

extern (C) void arr_set_type(refptr o, uint32 i, uint8 v)
{    
    *cast(uint8*)(o + arr_ofs_type(o, i)) = v;
}

extern (C) void arr_set_tbl(refptr o, refptr v)
{    
    *cast(refptr*)(o + arr_ofs_tbl(o)) = v;
}

extern (C) void arr_set_len(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arr_ofs_len(o)) = v;
}

extern (C) uint32 arr_comp_size(uint32 cap)
{    
    return (((((((((((0 + 8) + 4) + 4) + 8) + 8) + (8 * cap)) + (1 * cap)) + 7) & -8) + 8) + 4);
}

extern (C) uint32 arr_sizeof(refptr o)
{    
    return arr_comp_size(arr_get_cap(o));
}

extern (C) refptr arr_alloc(Interp interp, uint32 cap)
{    
    auto o = interp.heapAlloc(arr_comp_size(cap));
    arr_set_cap(o, cap);
    arr_set_next(o, null);
    arr_set_header(o, 5);
    for (uint32 i = 0; i < cap; ++i)
    {    
        arr_set_word(o, i, MISSING.uint64Val);
    }
    for (uint32 i = 0; i < cap; ++i)
    {    
        arr_set_type(o, i, Type.CONST);
    }
    return o;
}

extern (C) void arr_visit_gc(Interp interp, refptr o)
{    
    arr_set_next(o, gcForward(interp, arr_get_next(o)));
    arr_set_proto(o, gcForward(interp, arr_get_proto(o)));
    auto cap = arr_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        arr_set_word(o, i, gcForward(interp, arr_get_word(o, i), arr_get_type(o, i)));
    }
    arr_set_tbl(o, gcForward(interp, arr_get_tbl(o)));
}

const uint32 LAYOUT_ARRTBL = 6;

extern (C) uint32 arrtbl_ofs_next(refptr o)
{    
    return 0;
}

extern (C) uint32 arrtbl_ofs_header(refptr o)
{    
    return (0 + 8);
}

extern (C) uint32 arrtbl_ofs_cap(refptr o)
{    
    return ((0 + 8) + 4);
}

extern (C) uint32 arrtbl_ofs_word(refptr o, uint32 i)
{    
    return ((((0 + 8) + 4) + 4) + (8 * i));
}

extern (C) uint32 arrtbl_ofs_type(refptr o, uint32 i)
{    
    return (((((0 + 8) + 4) + 4) + (8 * arrtbl_get_cap(o))) + (1 * i));
}

extern (C) refptr arrtbl_get_next(refptr o)
{    
    return *cast(refptr*)(o + arrtbl_ofs_next(o));
}

extern (C) uint32 arrtbl_get_header(refptr o)
{    
    return *cast(uint32*)(o + arrtbl_ofs_header(o));
}

extern (C) uint32 arrtbl_get_cap(refptr o)
{    
    return *cast(uint32*)(o + arrtbl_ofs_cap(o));
}

extern (C) uint64 arrtbl_get_word(refptr o, uint32 i)
{    
    return *cast(uint64*)(o + arrtbl_ofs_word(o, i));
}

extern (C) uint8 arrtbl_get_type(refptr o, uint32 i)
{    
    return *cast(uint8*)(o + arrtbl_ofs_type(o, i));
}

extern (C) void arrtbl_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + arrtbl_ofs_next(o)) = v;
}

extern (C) void arrtbl_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arrtbl_ofs_header(o)) = v;
}

extern (C) void arrtbl_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arrtbl_ofs_cap(o)) = v;
}

extern (C) void arrtbl_set_word(refptr o, uint32 i, uint64 v)
{    
    *cast(uint64*)(o + arrtbl_ofs_word(o, i)) = v;
}

extern (C) void arrtbl_set_type(refptr o, uint32 i, uint8 v)
{    
    *cast(uint8*)(o + arrtbl_ofs_type(o, i)) = v;
}

extern (C) uint32 arrtbl_comp_size(uint32 cap)
{    
    return (((((0 + 8) + 4) + 4) + (8 * cap)) + (1 * cap));
}

extern (C) uint32 arrtbl_sizeof(refptr o)
{    
    return arrtbl_comp_size(arrtbl_get_cap(o));
}

extern (C) refptr arrtbl_alloc(Interp interp, uint32 cap)
{    
    auto o = interp.heapAlloc(arrtbl_comp_size(cap));
    arrtbl_set_cap(o, cap);
    arrtbl_set_next(o, null);
    arrtbl_set_header(o, 6);
    for (uint32 i = 0; i < cap; ++i)
    {    
        arrtbl_set_word(o, i, UNDEF.uint64Val);
    }
    for (uint32 i = 0; i < cap; ++i)
    {    
        arrtbl_set_type(o, i, Type.CONST);
    }
    return o;
}

extern (C) void arrtbl_visit_gc(Interp interp, refptr o)
{    
    arrtbl_set_next(o, gcForward(interp, arrtbl_get_next(o)));
    auto cap = arrtbl_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        arrtbl_set_word(o, i, gcForward(interp, arrtbl_get_word(o, i), arrtbl_get_type(o, i)));
    }
}

extern (C) uint32 layout_sizeof(refptr o)
{    
    auto t = obj_get_header(o);
    if ((t == LAYOUT_STR))
    {    
        return str_sizeof(o);
    }
    if ((t == LAYOUT_STRTBL))
    {    
        return strtbl_sizeof(o);
    }
    if ((t == LAYOUT_OBJ))
    {    
        return obj_sizeof(o);
    }
    if ((t == LAYOUT_CLOS))
    {    
        return clos_sizeof(o);
    }
    if ((t == LAYOUT_CELL))
    {    
        return cell_sizeof(o);
    }
    if ((t == LAYOUT_ARR))
    {    
        return arr_sizeof(o);
    }
    if ((t == LAYOUT_ARRTBL))
    {    
        return arrtbl_sizeof(o);
    }
    assert(false, "invalid layout in layout_sizeof");
}

extern (C) void layout_visit_gc(Interp interp, refptr o)
{    
    auto t = obj_get_header(o);
    if ((t == LAYOUT_STR))
    {    
        str_visit_gc(interp, o);
        return;
    }
    if ((t == LAYOUT_STRTBL))
    {    
        strtbl_visit_gc(interp, o);
        return;
    }
    if ((t == LAYOUT_OBJ))
    {    
        obj_visit_gc(interp, o);
        return;
    }
    if ((t == LAYOUT_CLOS))
    {    
        clos_visit_gc(interp, o);
        return;
    }
    if ((t == LAYOUT_CELL))
    {    
        cell_visit_gc(interp, o);
        return;
    }
    if ((t == LAYOUT_ARR))
    {    
        arr_visit_gc(interp, o);
        return;
    }
    if ((t == LAYOUT_ARRTBL))
    {    
        arrtbl_visit_gc(interp, o);
        return;
    }
    assert(false, "invalid layout in layout_visit_gc");
}

