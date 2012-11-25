//
// Code auto-generated from "interp/layout.py". Do not modify.
//

var LAYOUT_STR = 0;

function str_ofs_type(o)
{    
    return 0;
}

function str_ofs_len(o)
{    
    return $ir_add_i32(0, 4);
}

function str_ofs_hash(o)
{    
    return $ir_add_i32($ir_add_i32(0, 4), 4);
}

function str_ofs_data(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), $ir_mul_i32(2, i));
}

function str_get_type(o)
{    
    return $ir_load_u32(o, str_ofs_type(o));
}

function str_get_len(o)
{    
    return $ir_load_u32(o, str_ofs_len(o));
}

function str_get_hash(o)
{    
    return $ir_load_u32(o, str_ofs_hash(o));
}

function str_get_data(o, i)
{    
    return $ir_load_u16(o, str_ofs_data(o, i));
}

function str_set_type(o, v)
{    
    $ir_store_u32(o, str_ofs_type(o), v);
}

function str_set_len(o, v)
{    
    $ir_store_u32(o, str_ofs_len(o), v);
}

function str_set_hash(o, v)
{    
    $ir_store_u32(o, str_ofs_hash(o), v);
}

function str_set_data(o, i, v)
{    
    $ir_store_u16(o, str_ofs_data(o, i), v);
}

function str_comp_size(len)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), $ir_mul_i32(2, len));
}

function str_sizeof(o)
{    
    return str_comp_size(str_get_len(o));
}

function str_alloc(len)
{    
    var o = $ir_alloc(str_comp_size(len));
    str_set_len(o, len);
    str_set_type(o, 0);
    return o;
}

var LAYOUT_STRTBL = 1;

function strtbl_ofs_type(o)
{    
    return 0;
}

function strtbl_ofs_cap(o)
{    
    return $ir_add_i32(0, 4);
}

function strtbl_ofs_num_strs(o)
{    
    return $ir_add_i32($ir_add_i32(0, 4), 4);
}

function strtbl_ofs_str(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), $ir_mul_i32(8, i));
}

function strtbl_get_type(o)
{    
    return $ir_load_u32(o, strtbl_ofs_type(o));
}

function strtbl_get_cap(o)
{    
    return $ir_load_u32(o, strtbl_ofs_cap(o));
}

function strtbl_get_num_strs(o)
{    
    return $ir_load_u32(o, strtbl_ofs_num_strs(o));
}

function strtbl_get_str(o, i)
{    
    return $ir_load_refptr(o, strtbl_ofs_str(o, i));
}

function strtbl_set_type(o, v)
{    
    $ir_store_u32(o, strtbl_ofs_type(o), v);
}

function strtbl_set_cap(o, v)
{    
    $ir_store_u32(o, strtbl_ofs_cap(o), v);
}

function strtbl_set_num_strs(o, v)
{    
    $ir_store_u32(o, strtbl_ofs_num_strs(o), v);
}

function strtbl_set_str(o, i, v)
{    
    $ir_store_refptr(o, strtbl_ofs_str(o, i), v);
}

function strtbl_comp_size(cap)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), $ir_mul_i32(8, cap));
}

function strtbl_sizeof(o)
{    
    return strtbl_comp_size(strtbl_get_cap(o));
}

function strtbl_alloc(cap)
{    
    var o = $ir_alloc(strtbl_comp_size(cap));
    strtbl_set_cap(o, cap);
    strtbl_set_type(o, 1);
    strtbl_set_num_strs(o, 0);
    for (var i = 0; i < cap; ++i)
    {    
        strtbl_set_str(o, i, null);
    }
    return o;
}

var LAYOUT_OBJ = 2;

function obj_ofs_type(o)
{    
    return 0;
}

function obj_ofs_cap(o)
{    
    return $ir_add_i32(0, 4);
}

function obj_ofs_class(o)
{    
    return $ir_add_i32($ir_add_i32(0, 4), 4);
}

function obj_ofs_next(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8);
}

function obj_ofs_proto(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8);
}

function obj_ofs_word(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, i));
}

function obj_ofs_type(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, obj_get_cap(o))), $ir_mul_i32(1, i));
}

function obj_get_type(o)
{    
    return $ir_load_u32(o, obj_ofs_type(o));
}

function obj_get_cap(o)
{    
    return $ir_load_u32(o, obj_ofs_cap(o));
}

function obj_get_class(o)
{    
    return $ir_load_refptr(o, obj_ofs_class(o));
}

function obj_get_next(o)
{    
    return $ir_load_refptr(o, obj_ofs_next(o));
}

function obj_get_proto(o)
{    
    return $ir_load_refptr(o, obj_ofs_proto(o));
}

function obj_get_word(o, i)
{    
    return $ir_load_u64(o, obj_ofs_word(o, i));
}

function obj_get_type(o, i)
{    
    return $ir_load_u8(o, obj_ofs_type(o, i));
}

function obj_set_type(o, v)
{    
    $ir_store_u32(o, obj_ofs_type(o), v);
}

function obj_set_cap(o, v)
{    
    $ir_store_u32(o, obj_ofs_cap(o), v);
}

function obj_set_class(o, v)
{    
    $ir_store_refptr(o, obj_ofs_class(o), v);
}

function obj_set_next(o, v)
{    
    $ir_store_refptr(o, obj_ofs_next(o), v);
}

function obj_set_proto(o, v)
{    
    $ir_store_refptr(o, obj_ofs_proto(o), v);
}

function obj_set_word(o, i, v)
{    
    $ir_store_u64(o, obj_ofs_word(o, i), v);
}

function obj_set_type(o, i, v)
{    
    $ir_store_u8(o, obj_ofs_type(o, i), v);
}

function obj_comp_size(cap)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, cap)), $ir_mul_i32(1, cap));
}

function obj_sizeof(o)
{    
    return obj_comp_size(obj_get_cap(o));
}

function obj_alloc(cap)
{    
    var o = $ir_alloc(obj_comp_size(cap));
    obj_set_cap(o, cap);
    obj_set_type(o, 2);
    obj_set_next(o, null);
    return o;
}

var LAYOUT_CLOS = 3;

function clos_ofs_type(o)
{    
    return 0;
}

function clos_ofs_cap(o)
{    
    return $ir_add_i32(0, 4);
}

function clos_ofs_class(o)
{    
    return $ir_add_i32($ir_add_i32(0, 4), 4);
}

function clos_ofs_next(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8);
}

function clos_ofs_proto(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8);
}

function clos_ofs_word(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, i));
}

function clos_ofs_type(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, clos_get_cap(o))), $ir_mul_i32(1, i));
}

function clos_ofs_fptr(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, clos_get_cap(o))), $ir_mul_i32(1, clos_get_cap(o)));
}

function clos_ofs_num_cells(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, clos_get_cap(o))), $ir_mul_i32(1, clos_get_cap(o))), 8);
}

function clos_ofs_cell(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, clos_get_cap(o))), $ir_mul_i32(1, clos_get_cap(o))), 8), 4), $ir_mul_i32(8, i));
}

function clos_get_type(o)
{    
    return $ir_load_u32(o, clos_ofs_type(o));
}

function clos_get_cap(o)
{    
    return $ir_load_u32(o, clos_ofs_cap(o));
}

function clos_get_class(o)
{    
    return $ir_load_refptr(o, clos_ofs_class(o));
}

function clos_get_next(o)
{    
    return $ir_load_refptr(o, clos_ofs_next(o));
}

function clos_get_proto(o)
{    
    return $ir_load_refptr(o, clos_ofs_proto(o));
}

function clos_get_word(o, i)
{    
    return $ir_load_u64(o, clos_ofs_word(o, i));
}

function clos_get_type(o, i)
{    
    return $ir_load_u8(o, clos_ofs_type(o, i));
}

function clos_get_fptr(o)
{    
    return $ir_load_rawptr(o, clos_ofs_fptr(o));
}

function clos_get_num_cells(o)
{    
    return $ir_load_u32(o, clos_ofs_num_cells(o));
}

function clos_get_cell(o, i)
{    
    return $ir_load_refptr(o, clos_ofs_cell(o, i));
}

function clos_set_type(o, v)
{    
    $ir_store_u32(o, clos_ofs_type(o), v);
}

function clos_set_cap(o, v)
{    
    $ir_store_u32(o, clos_ofs_cap(o), v);
}

function clos_set_class(o, v)
{    
    $ir_store_refptr(o, clos_ofs_class(o), v);
}

function clos_set_next(o, v)
{    
    $ir_store_refptr(o, clos_ofs_next(o), v);
}

function clos_set_proto(o, v)
{    
    $ir_store_refptr(o, clos_ofs_proto(o), v);
}

function clos_set_word(o, i, v)
{    
    $ir_store_u64(o, clos_ofs_word(o, i), v);
}

function clos_set_type(o, i, v)
{    
    $ir_store_u8(o, clos_ofs_type(o, i), v);
}

function clos_set_fptr(o, v)
{    
    $ir_store_rawptr(o, clos_ofs_fptr(o), v);
}

function clos_set_num_cells(o, v)
{    
    $ir_store_u32(o, clos_ofs_num_cells(o), v);
}

function clos_set_cell(o, i, v)
{    
    $ir_store_refptr(o, clos_ofs_cell(o, i), v);
}

function clos_comp_size(cap, num_cells)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, cap)), $ir_mul_i32(1, cap)), 8), 4), $ir_mul_i32(8, num_cells));
}

function clos_sizeof(o)
{    
    return clos_comp_size(clos_get_cap(o), clos_get_num_cells(o));
}

function clos_alloc(cap, num_cells)
{    
    var o = $ir_alloc(clos_comp_size(cap, num_cells));
    clos_set_cap(o, cap);
    clos_set_num_cells(o, num_cells);
    clos_set_type(o, 3);
    clos_set_next(o, null);
    return o;
}

var LAYOUT_ARR = 4;

function arr_ofs_type(o)
{    
    return 0;
}

function arr_ofs_cap(o)
{    
    return $ir_add_i32(0, 4);
}

function arr_ofs_class(o)
{    
    return $ir_add_i32($ir_add_i32(0, 4), 4);
}

function arr_ofs_next(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8);
}

function arr_ofs_proto(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8);
}

function arr_ofs_word(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, i));
}

function arr_ofs_type(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, arr_get_cap(o))), $ir_mul_i32(1, i));
}

function arr_ofs_tbl(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, arr_get_cap(o))), $ir_mul_i32(1, arr_get_cap(o)));
}

function arr_ofs_len(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, arr_get_cap(o))), $ir_mul_i32(1, arr_get_cap(o))), 8);
}

function arr_get_type(o)
{    
    return $ir_load_u32(o, arr_ofs_type(o));
}

function arr_get_cap(o)
{    
    return $ir_load_u32(o, arr_ofs_cap(o));
}

function arr_get_class(o)
{    
    return $ir_load_refptr(o, arr_ofs_class(o));
}

function arr_get_next(o)
{    
    return $ir_load_refptr(o, arr_ofs_next(o));
}

function arr_get_proto(o)
{    
    return $ir_load_refptr(o, arr_ofs_proto(o));
}

function arr_get_word(o, i)
{    
    return $ir_load_u64(o, arr_ofs_word(o, i));
}

function arr_get_type(o, i)
{    
    return $ir_load_u8(o, arr_ofs_type(o, i));
}

function arr_get_tbl(o)
{    
    return $ir_load_refptr(o, arr_ofs_tbl(o));
}

function arr_get_len(o)
{    
    return $ir_load_u32(o, arr_ofs_len(o));
}

function arr_set_type(o, v)
{    
    $ir_store_u32(o, arr_ofs_type(o), v);
}

function arr_set_cap(o, v)
{    
    $ir_store_u32(o, arr_ofs_cap(o), v);
}

function arr_set_class(o, v)
{    
    $ir_store_refptr(o, arr_ofs_class(o), v);
}

function arr_set_next(o, v)
{    
    $ir_store_refptr(o, arr_ofs_next(o), v);
}

function arr_set_proto(o, v)
{    
    $ir_store_refptr(o, arr_ofs_proto(o), v);
}

function arr_set_word(o, i, v)
{    
    $ir_store_u64(o, arr_ofs_word(o, i), v);
}

function arr_set_type(o, i, v)
{    
    $ir_store_u8(o, arr_ofs_type(o, i), v);
}

function arr_set_tbl(o, v)
{    
    $ir_store_refptr(o, arr_ofs_tbl(o), v);
}

function arr_set_len(o, v)
{    
    $ir_store_u32(o, arr_ofs_len(o), v);
}

function arr_comp_size(cap)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 8), 8), 8), $ir_mul_i32(8, cap)), $ir_mul_i32(1, cap)), 8), 4);
}

function arr_sizeof(o)
{    
    return arr_comp_size(arr_get_cap(o));
}

function arr_alloc(cap)
{    
    var o = $ir_alloc(arr_comp_size(cap));
    arr_set_cap(o, cap);
    arr_set_type(o, 4);
    arr_set_next(o, null);
    return o;
}

var LAYOUT_ARRTBL = 5;

function arrtbl_ofs_type(o)
{    
    return 0;
}

function arrtbl_ofs_cap(o)
{    
    return $ir_add_i32(0, 4);
}

function arrtbl_ofs_word(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), $ir_mul_i32(8, i));
}

function arrtbl_ofs_type(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), $ir_mul_i32(8, arrtbl_get_cap(o))), $ir_mul_i32(1, i));
}

function arrtbl_get_type(o)
{    
    return $ir_load_u32(o, arrtbl_ofs_type(o));
}

function arrtbl_get_cap(o)
{    
    return $ir_load_u32(o, arrtbl_ofs_cap(o));
}

function arrtbl_get_word(o, i)
{    
    return $ir_load_u64(o, arrtbl_ofs_word(o, i));
}

function arrtbl_get_type(o, i)
{    
    return $ir_load_u8(o, arrtbl_ofs_type(o, i));
}

function arrtbl_set_type(o, v)
{    
    $ir_store_u32(o, arrtbl_ofs_type(o), v);
}

function arrtbl_set_cap(o, v)
{    
    $ir_store_u32(o, arrtbl_ofs_cap(o), v);
}

function arrtbl_set_word(o, i, v)
{    
    $ir_store_u64(o, arrtbl_ofs_word(o, i), v);
}

function arrtbl_set_type(o, i, v)
{    
    $ir_store_u8(o, arrtbl_ofs_type(o, i), v);
}

function arrtbl_comp_size(cap)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), $ir_mul_i32(8, cap)), $ir_mul_i32(1, cap));
}

function arrtbl_sizeof(o)
{    
    return arrtbl_comp_size(arrtbl_get_cap(o));
}

function arrtbl_alloc(cap)
{    
    var o = $ir_alloc(arrtbl_comp_size(cap));
    arrtbl_set_cap(o, cap);
    arrtbl_set_type(o, 5);
    return o;
}

var LAYOUT_CLASS = 6;

function class_ofs_type(o)
{    
    return 0;
}

function class_ofs_id(o)
{    
    return $ir_add_i32(0, 4);
}

function class_ofs_cap(o)
{    
    return $ir_add_i32($ir_add_i32(0, 4), 4);
}

function class_ofs_num_props(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4);
}

function class_ofs_next(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), 4);
}

function class_ofs_arr_type(o)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), 4), 8);
}

function class_ofs_prop_name(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), 4), 8), 8), $ir_mul_i32(8, i));
}

function class_ofs_prop_type(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), 4), 8), 8), $ir_mul_i32(8, class_get_cap(o))), $ir_mul_i32(8, i));
}

function class_ofs_prop_idx(o, i)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), 4), 8), 8), $ir_mul_i32(8, class_get_cap(o))), $ir_mul_i32(8, class_get_cap(o))), $ir_mul_i32(4, i));
}

function class_get_type(o)
{    
    return $ir_load_u32(o, class_ofs_type(o));
}

function class_get_id(o)
{    
    return $ir_load_u32(o, class_ofs_id(o));
}

function class_get_cap(o)
{    
    return $ir_load_u32(o, class_ofs_cap(o));
}

function class_get_num_props(o)
{    
    return $ir_load_u32(o, class_ofs_num_props(o));
}

function class_get_next(o)
{    
    return $ir_load_refptr(o, class_ofs_next(o));
}

function class_get_arr_type(o)
{    
    return $ir_load_rawptr(o, class_ofs_arr_type(o));
}

function class_get_prop_name(o, i)
{    
    return $ir_load_refptr(o, class_ofs_prop_name(o, i));
}

function class_get_prop_type(o, i)
{    
    return $ir_load_rawptr(o, class_ofs_prop_type(o, i));
}

function class_get_prop_idx(o, i)
{    
    return $ir_load_u32(o, class_ofs_prop_idx(o, i));
}

function class_set_type(o, v)
{    
    $ir_store_u32(o, class_ofs_type(o), v);
}

function class_set_id(o, v)
{    
    $ir_store_u32(o, class_ofs_id(o), v);
}

function class_set_cap(o, v)
{    
    $ir_store_u32(o, class_ofs_cap(o), v);
}

function class_set_num_props(o, v)
{    
    $ir_store_u32(o, class_ofs_num_props(o), v);
}

function class_set_next(o, v)
{    
    $ir_store_refptr(o, class_ofs_next(o), v);
}

function class_set_arr_type(o, v)
{    
    $ir_store_rawptr(o, class_ofs_arr_type(o), v);
}

function class_set_prop_name(o, i, v)
{    
    $ir_store_refptr(o, class_ofs_prop_name(o, i), v);
}

function class_set_prop_type(o, i, v)
{    
    $ir_store_rawptr(o, class_ofs_prop_type(o, i), v);
}

function class_set_prop_idx(o, i, v)
{    
    $ir_store_u32(o, class_ofs_prop_idx(o, i), v);
}

function class_comp_size(cap)
{    
    return $ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32($ir_add_i32(0, 4), 4), 4), 4), 8), 8), $ir_mul_i32(8, cap)), $ir_mul_i32(8, cap)), $ir_mul_i32(4, cap));
}

function class_sizeof(o)
{    
    return class_comp_size(class_get_cap(o));
}

function class_alloc(cap)
{    
    var o = $ir_alloc(class_comp_size(cap));
    class_set_cap(o, cap);
    class_set_type(o, 6);
    class_set_num_props(o, 0);
    class_set_next(o, null);
    class_set_arr_type(o, null);
    for (var i = 0; i < cap; ++i)
    {    
        class_set_prop_name(o, i, null);
    }
    for (var i = 0; i < cap; ++i)
    {    
        class_set_prop_type(o, i, null);
    }
    return o;
}

