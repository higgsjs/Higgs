//
// Code auto-generated from "interp/layout.py". Do not modify.
//

module interp.layout;
import interp.interp;
import interp.gc;

alias ubyte* funptr;
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

uint32 str_ofs_header(refptr o)
{    
    return 0;
}

uint32 str_ofs_len(refptr o)
{    
    return (0 + 4);
}

uint32 str_ofs_hash(refptr o)
{    
    return ((0 + 4) + 4);
}

uint32 str_ofs_data(refptr o, uint32 i)
{    
    return ((((0 + 4) + 4) + 4) + (2 * i));
}

uint32 str_get_header(refptr o)
{    
    return *cast(uint32*)(o + str_ofs_header(o));
}

uint32 str_get_len(refptr o)
{    
    return *cast(uint32*)(o + str_ofs_len(o));
}

uint32 str_get_hash(refptr o)
{    
    return *cast(uint32*)(o + str_ofs_hash(o));
}

uint16 str_get_data(refptr o, uint32 i)
{    
    return *cast(uint16*)(o + str_ofs_data(o, i));
}

void str_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + str_ofs_header(o)) = v;
}

void str_set_len(refptr o, uint32 v)
{    
    *cast(uint32*)(o + str_ofs_len(o)) = v;
}

void str_set_hash(refptr o, uint32 v)
{    
    *cast(uint32*)(o + str_ofs_hash(o)) = v;
}

void str_set_data(refptr o, uint32 i, uint16 v)
{    
    *cast(uint16*)(o + str_ofs_data(o, i)) = v;
}

uint32 str_comp_size(uint32 len)
{    
    return ((((0 + 4) + 4) + 4) + (2 * len));
}

uint32 str_sizeof(refptr o)
{    
    return str_comp_size(str_get_len(o));
}

refptr str_alloc(Interp interp, uint32 len)
{    
    auto o = interp.alloc(str_comp_size(len));
    str_set_len(o, len);
    str_set_header(o, 0);
    return o;
}

void str_visit_gc(Interp interp, refptr o)
{
}

const uint32 LAYOUT_STRTBL = 1;

uint32 strtbl_ofs_header(refptr o)
{    
    return 0;
}

uint32 strtbl_ofs_cap(refptr o)
{    
    return (0 + 4);
}

uint32 strtbl_ofs_num_strs(refptr o)
{    
    return ((0 + 4) + 4);
}

uint32 strtbl_ofs_str(refptr o, uint32 i)
{    
    return (((((0 + 4) + 4) + 4) + 4) + (8 * i));
}

uint32 strtbl_get_header(refptr o)
{    
    return *cast(uint32*)(o + strtbl_ofs_header(o));
}

uint32 strtbl_get_cap(refptr o)
{    
    return *cast(uint32*)(o + strtbl_ofs_cap(o));
}

uint32 strtbl_get_num_strs(refptr o)
{    
    return *cast(uint32*)(o + strtbl_ofs_num_strs(o));
}

refptr strtbl_get_str(refptr o, uint32 i)
{    
    return *cast(refptr*)(o + strtbl_ofs_str(o, i));
}

void strtbl_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + strtbl_ofs_header(o)) = v;
}

void strtbl_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + strtbl_ofs_cap(o)) = v;
}

void strtbl_set_num_strs(refptr o, uint32 v)
{    
    *cast(uint32*)(o + strtbl_ofs_num_strs(o)) = v;
}

void strtbl_set_str(refptr o, uint32 i, refptr v)
{    
    *cast(refptr*)(o + strtbl_ofs_str(o, i)) = v;
}

uint32 strtbl_comp_size(uint32 cap)
{    
    return (((((0 + 4) + 4) + 4) + 4) + (8 * cap));
}

uint32 strtbl_sizeof(refptr o)
{    
    return strtbl_comp_size(strtbl_get_cap(o));
}

refptr strtbl_alloc(Interp interp, uint32 cap)
{    
    auto o = interp.alloc(strtbl_comp_size(cap));
    strtbl_set_cap(o, cap);
    strtbl_set_header(o, 1);
    strtbl_set_num_strs(o, 0);
    for (uint32 i = 0; i < cap; ++i)
    {    
        strtbl_set_str(o, i, null);
    }
    return o;
}

void strtbl_visit_gc(Interp interp, refptr o)
{    
    auto cap = strtbl_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        strtbl_set_str(o, i, gcForward(interp, strtbl_get_str(o, i)));
    }
}

const uint32 LAYOUT_OBJ = 2;

uint32 obj_ofs_header(refptr o)
{    
    return 0;
}

uint32 obj_ofs_cap(refptr o)
{    
    return (0 + 4);
}

uint32 obj_ofs_class(refptr o)
{    
    return ((0 + 4) + 4);
}

uint32 obj_ofs_next(refptr o)
{    
    return (((0 + 4) + 4) + 8);
}

uint32 obj_ofs_proto(refptr o)
{    
    return ((((0 + 4) + 4) + 8) + 8);
}

uint32 obj_ofs_word(refptr o, uint32 i)
{    
    return ((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * i));
}

uint32 obj_ofs_type(refptr o, uint32 i)
{    
    return (((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * obj_get_cap(o))) + (1 * i));
}

uint32 obj_get_header(refptr o)
{    
    return *cast(uint32*)(o + obj_ofs_header(o));
}

uint32 obj_get_cap(refptr o)
{    
    return *cast(uint32*)(o + obj_ofs_cap(o));
}

refptr obj_get_class(refptr o)
{    
    return *cast(refptr*)(o + obj_ofs_class(o));
}

refptr obj_get_next(refptr o)
{    
    return *cast(refptr*)(o + obj_ofs_next(o));
}

refptr obj_get_proto(refptr o)
{    
    return *cast(refptr*)(o + obj_ofs_proto(o));
}

uint64 obj_get_word(refptr o, uint32 i)
{    
    return *cast(uint64*)(o + obj_ofs_word(o, i));
}

uint8 obj_get_type(refptr o, uint32 i)
{    
    return *cast(uint8*)(o + obj_ofs_type(o, i));
}

void obj_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + obj_ofs_header(o)) = v;
}

void obj_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + obj_ofs_cap(o)) = v;
}

void obj_set_class(refptr o, refptr v)
{    
    *cast(refptr*)(o + obj_ofs_class(o)) = v;
}

void obj_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + obj_ofs_next(o)) = v;
}

void obj_set_proto(refptr o, refptr v)
{    
    *cast(refptr*)(o + obj_ofs_proto(o)) = v;
}

void obj_set_word(refptr o, uint32 i, uint64 v)
{    
    *cast(uint64*)(o + obj_ofs_word(o, i)) = v;
}

void obj_set_type(refptr o, uint32 i, uint8 v)
{    
    *cast(uint8*)(o + obj_ofs_type(o, i)) = v;
}

uint32 obj_comp_size(uint32 cap)
{    
    return (((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * cap)) + (1 * cap));
}

uint32 obj_sizeof(refptr o)
{    
    return obj_comp_size(obj_get_cap(o));
}

refptr obj_alloc(Interp interp, uint32 cap)
{    
    auto o = interp.alloc(obj_comp_size(cap));
    obj_set_cap(o, cap);
    obj_set_header(o, 2);
    obj_set_next(o, null);
    for (uint32 i = 0; i < cap; ++i)
    {    
        obj_set_word(o, i, UNDEF.intVal);
    }
    for (uint32 i = 0; i < cap; ++i)
    {    
        obj_set_type(o, i, Type.CONST);
    }
    return o;
}

void obj_visit_gc(Interp interp, refptr o)
{    
    obj_set_class(o, gcForward(interp, obj_get_class(o)));
    obj_set_next(o, gcForward(interp, obj_get_next(o)));
    obj_set_proto(o, gcForward(interp, obj_get_proto(o)));
    auto cap = obj_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        obj_set_word(o, i, gcForward(interp, obj_get_word(o, i), obj_get_type(o, i)));
    }
}

const uint32 LAYOUT_CLOS = 3;

uint32 clos_ofs_header(refptr o)
{    
    return 0;
}

uint32 clos_ofs_cap(refptr o)
{    
    return (0 + 4);
}

uint32 clos_ofs_class(refptr o)
{    
    return ((0 + 4) + 4);
}

uint32 clos_ofs_next(refptr o)
{    
    return (((0 + 4) + 4) + 8);
}

uint32 clos_ofs_proto(refptr o)
{    
    return ((((0 + 4) + 4) + 8) + 8);
}

uint32 clos_ofs_word(refptr o, uint32 i)
{    
    return ((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * i));
}

uint32 clos_ofs_type(refptr o, uint32 i)
{    
    return (((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * clos_get_cap(o))) + (1 * i));
}

uint32 clos_ofs_fptr(refptr o)
{    
    return (((((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * clos_get_cap(o))) + (1 * clos_get_cap(o))) + 7) & -8);
}

uint32 clos_ofs_ctor_class(refptr o)
{    
    return ((((((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * clos_get_cap(o))) + (1 * clos_get_cap(o))) + 7) & -8) + 8);
}

uint32 clos_ofs_num_cells(refptr o)
{    
    return (((((((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * clos_get_cap(o))) + (1 * clos_get_cap(o))) + 7) & -8) + 8) + 8);
}

uint32 clos_ofs_cell(refptr o, uint32 i)
{    
    return ((((((((((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * clos_get_cap(o))) + (1 * clos_get_cap(o))) + 7) & -8) + 8) + 8) + 4) + 4) + (8 * i));
}

uint32 clos_get_header(refptr o)
{    
    return *cast(uint32*)(o + clos_ofs_header(o));
}

uint32 clos_get_cap(refptr o)
{    
    return *cast(uint32*)(o + clos_ofs_cap(o));
}

refptr clos_get_class(refptr o)
{    
    return *cast(refptr*)(o + clos_ofs_class(o));
}

refptr clos_get_next(refptr o)
{    
    return *cast(refptr*)(o + clos_ofs_next(o));
}

refptr clos_get_proto(refptr o)
{    
    return *cast(refptr*)(o + clos_ofs_proto(o));
}

uint64 clos_get_word(refptr o, uint32 i)
{    
    return *cast(uint64*)(o + clos_ofs_word(o, i));
}

uint8 clos_get_type(refptr o, uint32 i)
{    
    return *cast(uint8*)(o + clos_ofs_type(o, i));
}

funptr clos_get_fptr(refptr o)
{    
    return *cast(funptr*)(o + clos_ofs_fptr(o));
}

refptr clos_get_ctor_class(refptr o)
{    
    return *cast(refptr*)(o + clos_ofs_ctor_class(o));
}

uint32 clos_get_num_cells(refptr o)
{    
    return *cast(uint32*)(o + clos_ofs_num_cells(o));
}

refptr clos_get_cell(refptr o, uint32 i)
{    
    return *cast(refptr*)(o + clos_ofs_cell(o, i));
}

void clos_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + clos_ofs_header(o)) = v;
}

void clos_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + clos_ofs_cap(o)) = v;
}

void clos_set_class(refptr o, refptr v)
{    
    *cast(refptr*)(o + clos_ofs_class(o)) = v;
}

void clos_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + clos_ofs_next(o)) = v;
}

void clos_set_proto(refptr o, refptr v)
{    
    *cast(refptr*)(o + clos_ofs_proto(o)) = v;
}

void clos_set_word(refptr o, uint32 i, uint64 v)
{    
    *cast(uint64*)(o + clos_ofs_word(o, i)) = v;
}

void clos_set_type(refptr o, uint32 i, uint8 v)
{    
    *cast(uint8*)(o + clos_ofs_type(o, i)) = v;
}

void clos_set_fptr(refptr o, funptr v)
{    
    *cast(funptr*)(o + clos_ofs_fptr(o)) = v;
}

void clos_set_ctor_class(refptr o, refptr v)
{    
    *cast(refptr*)(o + clos_ofs_ctor_class(o)) = v;
}

void clos_set_num_cells(refptr o, uint32 v)
{    
    *cast(uint32*)(o + clos_ofs_num_cells(o)) = v;
}

void clos_set_cell(refptr o, uint32 i, refptr v)
{    
    *cast(refptr*)(o + clos_ofs_cell(o, i)) = v;
}

uint32 clos_comp_size(uint32 cap, uint32 num_cells)
{    
    return ((((((((((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * cap)) + (1 * cap)) + 7) & -8) + 8) + 8) + 4) + 4) + (8 * num_cells));
}

uint32 clos_sizeof(refptr o)
{    
    return clos_comp_size(clos_get_cap(o), clos_get_num_cells(o));
}

refptr clos_alloc(Interp interp, uint32 cap, uint32 num_cells)
{    
    auto o = interp.alloc(clos_comp_size(cap, num_cells));
    clos_set_cap(o, cap);
    clos_set_num_cells(o, num_cells);
    clos_set_header(o, 3);
    clos_set_next(o, null);
    for (uint32 i = 0; i < num_cells; ++i)
    {    
        clos_set_word(o, i, UNDEF.intVal);
    }
    for (uint32 i = 0; i < num_cells; ++i)
    {    
        clos_set_type(o, i, Type.CONST);
    }
    clos_set_ctor_class(o, null);
    for (uint32 i = 0; i < num_cells; ++i)
    {    
        clos_set_cell(o, i, null);
    }
    return o;
}

void clos_visit_gc(Interp interp, refptr o)
{    
    clos_set_class(o, gcForward(interp, clos_get_class(o)));
    clos_set_next(o, gcForward(interp, clos_get_next(o)));
    clos_set_proto(o, gcForward(interp, clos_get_proto(o)));
    auto cap = clos_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        clos_set_word(o, i, gcForward(interp, clos_get_word(o, i), clos_get_type(o, i)));
    }
    clos_set_ctor_class(o, gcForward(interp, clos_get_ctor_class(o)));
    auto num_cells = clos_get_num_cells(o);
    for (uint32 i = 0; i < num_cells; ++i)
    {    
        clos_set_cell(o, i, gcForward(interp, clos_get_cell(o, i)));
    }
}

const uint32 LAYOUT_CELL = 4;

uint32 cell_ofs_header(refptr o)
{    
    return 0;
}

uint32 cell_ofs_word(refptr o)
{    
    return ((0 + 4) + 4);
}

uint32 cell_ofs_type(refptr o)
{    
    return (((0 + 4) + 4) + 8);
}

uint32 cell_get_header(refptr o)
{    
    return *cast(uint32*)(o + cell_ofs_header(o));
}

uint64 cell_get_word(refptr o)
{    
    return *cast(uint64*)(o + cell_ofs_word(o));
}

uint8 cell_get_type(refptr o)
{    
    return *cast(uint8*)(o + cell_ofs_type(o));
}

void cell_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + cell_ofs_header(o)) = v;
}

void cell_set_word(refptr o, uint64 v)
{    
    *cast(uint64*)(o + cell_ofs_word(o)) = v;
}

void cell_set_type(refptr o, uint8 v)
{    
    *cast(uint8*)(o + cell_ofs_type(o)) = v;
}

uint32 cell_comp_size()
{    
    return ((((0 + 4) + 4) + 8) + 1);
}

uint32 cell_sizeof(refptr o)
{    
    return cell_comp_size();
}

refptr cell_alloc(Interp interp)
{    
    auto o = interp.alloc(cell_comp_size());
    cell_set_header(o, 4);
    cell_set_word(o, UNDEF.intVal);
    cell_set_type(o, Type.CONST);
    return o;
}

void cell_visit_gc(Interp interp, refptr o)
{    
    cell_set_word(o, gcForward(interp, cell_get_word(o), cell_get_type(o)));
}

const uint32 LAYOUT_ARR = 5;

uint32 arr_ofs_header(refptr o)
{    
    return 0;
}

uint32 arr_ofs_cap(refptr o)
{    
    return (0 + 4);
}

uint32 arr_ofs_class(refptr o)
{    
    return ((0 + 4) + 4);
}

uint32 arr_ofs_next(refptr o)
{    
    return (((0 + 4) + 4) + 8);
}

uint32 arr_ofs_proto(refptr o)
{    
    return ((((0 + 4) + 4) + 8) + 8);
}

uint32 arr_ofs_word(refptr o, uint32 i)
{    
    return ((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * i));
}

uint32 arr_ofs_type(refptr o, uint32 i)
{    
    return (((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * arr_get_cap(o))) + (1 * i));
}

uint32 arr_ofs_tbl(refptr o)
{    
    return (((((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * arr_get_cap(o))) + (1 * arr_get_cap(o))) + 7) & -8);
}

uint32 arr_ofs_len(refptr o)
{    
    return ((((((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * arr_get_cap(o))) + (1 * arr_get_cap(o))) + 7) & -8) + 8);
}

uint32 arr_get_header(refptr o)
{    
    return *cast(uint32*)(o + arr_ofs_header(o));
}

uint32 arr_get_cap(refptr o)
{    
    return *cast(uint32*)(o + arr_ofs_cap(o));
}

refptr arr_get_class(refptr o)
{    
    return *cast(refptr*)(o + arr_ofs_class(o));
}

refptr arr_get_next(refptr o)
{    
    return *cast(refptr*)(o + arr_ofs_next(o));
}

refptr arr_get_proto(refptr o)
{    
    return *cast(refptr*)(o + arr_ofs_proto(o));
}

uint64 arr_get_word(refptr o, uint32 i)
{    
    return *cast(uint64*)(o + arr_ofs_word(o, i));
}

uint8 arr_get_type(refptr o, uint32 i)
{    
    return *cast(uint8*)(o + arr_ofs_type(o, i));
}

refptr arr_get_tbl(refptr o)
{    
    return *cast(refptr*)(o + arr_ofs_tbl(o));
}

uint32 arr_get_len(refptr o)
{    
    return *cast(uint32*)(o + arr_ofs_len(o));
}

void arr_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arr_ofs_header(o)) = v;
}

void arr_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arr_ofs_cap(o)) = v;
}

void arr_set_class(refptr o, refptr v)
{    
    *cast(refptr*)(o + arr_ofs_class(o)) = v;
}

void arr_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + arr_ofs_next(o)) = v;
}

void arr_set_proto(refptr o, refptr v)
{    
    *cast(refptr*)(o + arr_ofs_proto(o)) = v;
}

void arr_set_word(refptr o, uint32 i, uint64 v)
{    
    *cast(uint64*)(o + arr_ofs_word(o, i)) = v;
}

void arr_set_type(refptr o, uint32 i, uint8 v)
{    
    *cast(uint8*)(o + arr_ofs_type(o, i)) = v;
}

void arr_set_tbl(refptr o, refptr v)
{    
    *cast(refptr*)(o + arr_ofs_tbl(o)) = v;
}

void arr_set_len(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arr_ofs_len(o)) = v;
}

uint32 arr_comp_size(uint32 cap)
{    
    return (((((((((((0 + 4) + 4) + 8) + 8) + 8) + (8 * cap)) + (1 * cap)) + 7) & -8) + 8) + 4);
}

uint32 arr_sizeof(refptr o)
{    
    return arr_comp_size(arr_get_cap(o));
}

refptr arr_alloc(Interp interp, uint32 cap)
{    
    auto o = interp.alloc(arr_comp_size(cap));
    arr_set_cap(o, cap);
    arr_set_header(o, 5);
    arr_set_next(o, null);
    for (uint32 i = 0; i < cap; ++i)
    {    
        arr_set_word(o, i, UNDEF.intVal);
    }
    for (uint32 i = 0; i < cap; ++i)
    {    
        arr_set_type(o, i, Type.CONST);
    }
    return o;
}

void arr_visit_gc(Interp interp, refptr o)
{    
    arr_set_class(o, gcForward(interp, arr_get_class(o)));
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

uint32 arrtbl_ofs_header(refptr o)
{    
    return 0;
}

uint32 arrtbl_ofs_cap(refptr o)
{    
    return (0 + 4);
}

uint32 arrtbl_ofs_word(refptr o, uint32 i)
{    
    return (((0 + 4) + 4) + (8 * i));
}

uint32 arrtbl_ofs_type(refptr o, uint32 i)
{    
    return ((((0 + 4) + 4) + (8 * arrtbl_get_cap(o))) + (1 * i));
}

uint32 arrtbl_get_header(refptr o)
{    
    return *cast(uint32*)(o + arrtbl_ofs_header(o));
}

uint32 arrtbl_get_cap(refptr o)
{    
    return *cast(uint32*)(o + arrtbl_ofs_cap(o));
}

uint64 arrtbl_get_word(refptr o, uint32 i)
{    
    return *cast(uint64*)(o + arrtbl_ofs_word(o, i));
}

uint8 arrtbl_get_type(refptr o, uint32 i)
{    
    return *cast(uint8*)(o + arrtbl_ofs_type(o, i));
}

void arrtbl_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arrtbl_ofs_header(o)) = v;
}

void arrtbl_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + arrtbl_ofs_cap(o)) = v;
}

void arrtbl_set_word(refptr o, uint32 i, uint64 v)
{    
    *cast(uint64*)(o + arrtbl_ofs_word(o, i)) = v;
}

void arrtbl_set_type(refptr o, uint32 i, uint8 v)
{    
    *cast(uint8*)(o + arrtbl_ofs_type(o, i)) = v;
}

uint32 arrtbl_comp_size(uint32 cap)
{    
    return ((((0 + 4) + 4) + (8 * cap)) + (1 * cap));
}

uint32 arrtbl_sizeof(refptr o)
{    
    return arrtbl_comp_size(arrtbl_get_cap(o));
}

refptr arrtbl_alloc(Interp interp, uint32 cap)
{    
    auto o = interp.alloc(arrtbl_comp_size(cap));
    arrtbl_set_cap(o, cap);
    arrtbl_set_header(o, 6);
    for (uint32 i = 0; i < cap; ++i)
    {    
        arrtbl_set_word(o, i, UNDEF.intVal);
    }
    for (uint32 i = 0; i < cap; ++i)
    {    
        arrtbl_set_type(o, i, Type.CONST);
    }
    return o;
}

void arrtbl_visit_gc(Interp interp, refptr o)
{    
    auto cap = arrtbl_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        arrtbl_set_word(o, i, gcForward(interp, arrtbl_get_word(o, i), arrtbl_get_type(o, i)));
    }
}

const uint32 LAYOUT_CLASS = 7;

uint32 class_ofs_header(refptr o)
{    
    return 0;
}

uint32 class_ofs_id(refptr o)
{    
    return (0 + 4);
}

uint32 class_ofs_cap(refptr o)
{    
    return ((0 + 4) + 4);
}

uint32 class_ofs_num_props(refptr o)
{    
    return (((0 + 4) + 4) + 4);
}

uint32 class_ofs_next(refptr o)
{    
    return ((((0 + 4) + 4) + 4) + 4);
}

uint32 class_ofs_arr_type(refptr o)
{    
    return (((((0 + 4) + 4) + 4) + 4) + 8);
}

uint32 class_ofs_prop_name(refptr o, uint32 i)
{    
    return (((((((0 + 4) + 4) + 4) + 4) + 8) + 8) + (8 * i));
}

uint32 class_ofs_prop_type(refptr o, uint32 i)
{    
    return ((((((((0 + 4) + 4) + 4) + 4) + 8) + 8) + (8 * class_get_cap(o))) + (8 * i));
}

uint32 class_ofs_prop_idx(refptr o, uint32 i)
{    
    return (((((((((0 + 4) + 4) + 4) + 4) + 8) + 8) + (8 * class_get_cap(o))) + (8 * class_get_cap(o))) + (4 * i));
}

uint32 class_get_header(refptr o)
{    
    return *cast(uint32*)(o + class_ofs_header(o));
}

uint32 class_get_id(refptr o)
{    
    return *cast(uint32*)(o + class_ofs_id(o));
}

uint32 class_get_cap(refptr o)
{    
    return *cast(uint32*)(o + class_ofs_cap(o));
}

uint32 class_get_num_props(refptr o)
{    
    return *cast(uint32*)(o + class_ofs_num_props(o));
}

refptr class_get_next(refptr o)
{    
    return *cast(refptr*)(o + class_ofs_next(o));
}

rawptr class_get_arr_type(refptr o)
{    
    return *cast(rawptr*)(o + class_ofs_arr_type(o));
}

refptr class_get_prop_name(refptr o, uint32 i)
{    
    return *cast(refptr*)(o + class_ofs_prop_name(o, i));
}

rawptr class_get_prop_type(refptr o, uint32 i)
{    
    return *cast(rawptr*)(o + class_ofs_prop_type(o, i));
}

uint32 class_get_prop_idx(refptr o, uint32 i)
{    
    return *cast(uint32*)(o + class_ofs_prop_idx(o, i));
}

void class_set_header(refptr o, uint32 v)
{    
    *cast(uint32*)(o + class_ofs_header(o)) = v;
}

void class_set_id(refptr o, uint32 v)
{    
    *cast(uint32*)(o + class_ofs_id(o)) = v;
}

void class_set_cap(refptr o, uint32 v)
{    
    *cast(uint32*)(o + class_ofs_cap(o)) = v;
}

void class_set_num_props(refptr o, uint32 v)
{    
    *cast(uint32*)(o + class_ofs_num_props(o)) = v;
}

void class_set_next(refptr o, refptr v)
{    
    *cast(refptr*)(o + class_ofs_next(o)) = v;
}

void class_set_arr_type(refptr o, rawptr v)
{    
    *cast(rawptr*)(o + class_ofs_arr_type(o)) = v;
}

void class_set_prop_name(refptr o, uint32 i, refptr v)
{    
    *cast(refptr*)(o + class_ofs_prop_name(o, i)) = v;
}

void class_set_prop_type(refptr o, uint32 i, rawptr v)
{    
    *cast(rawptr*)(o + class_ofs_prop_type(o, i)) = v;
}

void class_set_prop_idx(refptr o, uint32 i, uint32 v)
{    
    *cast(uint32*)(o + class_ofs_prop_idx(o, i)) = v;
}

uint32 class_comp_size(uint32 cap)
{    
    return (((((((((0 + 4) + 4) + 4) + 4) + 8) + 8) + (8 * cap)) + (8 * cap)) + (4 * cap));
}

uint32 class_sizeof(refptr o)
{    
    return class_comp_size(class_get_cap(o));
}

refptr class_alloc(Interp interp, uint32 cap)
{    
    auto o = interp.alloc(class_comp_size(cap));
    class_set_cap(o, cap);
    class_set_header(o, 7);
    class_set_num_props(o, 0);
    class_set_next(o, null);
    class_set_arr_type(o, null);
    for (uint32 i = 0; i < cap; ++i)
    {    
        class_set_prop_name(o, i, null);
    }
    for (uint32 i = 0; i < cap; ++i)
    {    
        class_set_prop_type(o, i, null);
    }
    return o;
}

void class_visit_gc(Interp interp, refptr o)
{    
    class_set_next(o, gcForward(interp, class_get_next(o)));
    auto cap = class_get_cap(o);
    for (uint32 i = 0; i < cap; ++i)
    {    
        class_set_prop_name(o, i, gcForward(interp, class_get_prop_name(o, i)));
    }
}

uint32 layout_sizeof(refptr o)
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
    if ((t == LAYOUT_CLASS))
    {    
        return class_sizeof(o);
    }
    assert(false);
}

uint32 layout_visit_gc(Interp interp, refptr o)
{    
    auto t = obj_get_header(o);
    if ((t == LAYOUT_STR))
    {    
        str_visit_gc(interp, o);
    }
    if ((t == LAYOUT_STRTBL))
    {    
        strtbl_visit_gc(interp, o);
    }
    if ((t == LAYOUT_OBJ))
    {    
        obj_visit_gc(interp, o);
    }
    if ((t == LAYOUT_CLOS))
    {    
        clos_visit_gc(interp, o);
    }
    if ((t == LAYOUT_CELL))
    {    
        cell_visit_gc(interp, o);
    }
    if ((t == LAYOUT_ARR))
    {    
        arr_visit_gc(interp, o);
    }
    if ((t == LAYOUT_ARRTBL))
    {    
        arrtbl_visit_gc(interp, o);
    }
    if ((t == LAYOUT_CLASS))
    {    
        class_visit_gc(interp, o);
    }
    assert(false);
}

