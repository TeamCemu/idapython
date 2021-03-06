// Make get_any_cmt() work
%apply unsigned char *OUTPUT { color_t *cmttype };

// For get_enum_id()
%apply unsigned char *OUTPUT { uchar *serial };

// get_[first|last]_serial_enum_member() won't take serials as input; it'll be present as output
%apply unsigned char *OUTPUT { uchar *out_serial };
// get_[next|prev]_serial_enum_member() take serials as input, and have the result present as output
%apply unsigned char *INOUT { uchar *in_out_serial };

// Unexported and kernel-only declarations
%ignore FlagsEnable;
%ignore FlagsDisable;
%ignore testf_t;
%ignore nextthat;
%ignore prevthat;
%ignore adjust_visea;
%ignore prev_visea;
%ignore next_visea;
%ignore visit_patched_bytes;
%ignore is_first_visea;
%ignore is_last_visea;
%ignore is_visible_finally;
%ignore invalidate_visea_cache;
%ignore fluFlags;
%ignore setFlbits;
%ignore clrFlbits;
%ignore get_8bit;
%ignore get_ascii_char;
%ignore del_opinfo;
%ignore del_one_opinfo;
%ignore doCode;
%ignore get_repeatable_cmt;
%ignore get_any_indented_cmt;
%ignore del_code_comments;
%ignore doFlow;
%ignore noFlow;
%ignore doRef;
%ignore noRef;
%ignore coagulate;
%ignore coagulate_dref;
%ignore init_hidden_areas;
%ignore save_hidden_areas;
%ignore term_hidden_areas;
%ignore check_move_args;
%ignore movechunk;
%ignore lock_dbgmem_config;
%ignore unlock_dbgmem_config;
%ignore set_op_type_no_event;
%ignore shuffle_tribytes;
%ignore set_enum_id;
%ignore validate_tofs;
%ignore set_flags_nomark;
%ignore set_flbits_nomark;
%ignore clr_flbits_nomark;
%ignore ida_vpagesize;
%ignore ida_vpages;
%ignore ida_npagesize;
%ignore ida_npages;
%ignore fpnum_digits;
%ignore fpnum_length;
%ignore FlagsInit;
%ignore FlagsTerm;
%ignore FlagsReset;
%ignore init_flags;
%ignore term_flags;
%ignore reset_flags;
%ignore flush_flags;
%ignore get_flags_linput;
%ignore data_type_t;
%ignore data_format_t;
%ignore get_custom_data_type;
%ignore get_custom_data_format;
%ignore unregister_custom_data_format;
%ignore register_custom_data_format;
%ignore unregister_custom_data_type;
%ignore register_custom_data_type;
%ignore get_many_bytes;
%ignore get_ascii_contents;
%ignore get_ascii_contents2;

// TODO: This could be fixed (if needed)
%ignore set_dbgmem_source;

%include "bytes.hpp"

%clear(void *buf, ssize_t size);

%clear(const void *buf, size_t size);
%clear(void *buf, ssize_t size);
%clear(opinfo_t *);

%rename (visit_patched_bytes) py_visit_patched_bytes;
%rename (nextthat) py_nextthat;
%rename (prevthat) py_prevthat;
%rename (get_custom_data_type) py_get_custom_data_type;
%rename (get_custom_data_format) py_get_custom_data_format;
%rename (unregister_custom_data_format) py_unregister_custom_data_format;
%rename (register_custom_data_format) py_register_custom_data_format;
%rename (unregister_custom_data_type) py_unregister_custom_data_type;
%rename (register_custom_data_type) py_register_custom_data_type;
%rename (get_many_bytes) py_get_many_bytes;
%rename (get_ascii_contents) py_get_ascii_contents;
%rename (get_ascii_contents2) py_get_ascii_contents2;
%{
//<code(py_bytes)>
//------------------------------------------------------------------------
static bool idaapi py_testf_cb(flags_t flags, void *ud)
{
  PYW_GIL_CHECK_LOCKED_SCOPE();
  newref_t py_flags(PyLong_FromUnsignedLong(flags));
  newref_t result(PyObject_CallFunctionObjArgs((PyObject *) ud, py_flags.o, NULL));
  return result != NULL && PyObject_IsTrue(result.o);
}

//------------------------------------------------------------------------
// Wraps the (next|prev)that()
static ea_t py_npthat(ea_t ea, ea_t bound, PyObject *py_callable, bool next)
{
  PYW_GIL_CHECK_LOCKED_SCOPE();
  if ( !PyCallable_Check(py_callable) )
    return BADADDR;
  else
    return (next ? nextthat : prevthat)(ea, bound, py_testf_cb, py_callable);
}

//---------------------------------------------------------------------------
static int idaapi py_visit_patched_bytes_cb(
      ea_t ea,
      int32 fpos,
      uint32 o,
      uint32 v,
      void *ud)
{
  PYW_GIL_CHECK_LOCKED_SCOPE();
  newref_t py_result(
          PyObject_CallFunction(
                  (PyObject *)ud,
                  PY_FMT64 "iII",
                  pyul_t(ea),
                  fpos,
                  o,
                  v));
  PyW_ShowCbErr("visit_patched_bytes");
  return (py_result != NULL && PyInt_Check(py_result.o)) ? PyInt_AsLong(py_result.o) : 0;
}



//------------------------------------------------------------------------
class py_custom_data_type_t
{
  data_type_t dt;
  qstring dt_name, dt_menu_name, dt_hotkey, dt_asm_keyword;
  int dtid; // The data format id
  PyObject *py_self; // Associated Python object

  // may create data? NULL means always may
  static bool idaapi s_may_create_at(
    void *ud,                       // user-defined data
    ea_t ea,                        // address of the future item
    size_t nbytes)                  // size of the future item
  {
    py_custom_data_type_t *_this = (py_custom_data_type_t *)ud;

    PYW_GIL_GET;
    newref_t py_result(
            PyObject_CallMethod(
                    _this->py_self,
                    (char *)S_MAY_CREATE_AT,
                    PY_FMT64 PY_FMT64,
                    pyul_t(ea),
                    pyul_t(nbytes)));

    PyW_ShowCbErr(S_MAY_CREATE_AT);
    return py_result != NULL && PyObject_IsTrue(py_result.o);
  }

  // !=NULL means variable size datatype
  static asize_t idaapi s_calc_item_size(
    // This function is used to determine
    // size of the (possible) item at 'ea'
    void *ud,                       // user-defined data
    ea_t ea,                        // address of the item
    asize_t maxsize)               // maximal size of the item
  {
    PYW_GIL_GET;
    // Returns: 0-no such item can be created/displayed
    // this callback is required only for varsize datatypes
    py_custom_data_type_t *_this = (py_custom_data_type_t *)ud;
    newref_t py_result(
            PyObject_CallMethod(
                    _this->py_self,
                    (char *)S_CALC_ITEM_SIZE,
                    PY_FMT64 PY_FMT64,
                    pyul_t(ea),
                    pyul_t(maxsize)));

    if ( PyW_ShowCbErr(S_CALC_ITEM_SIZE) || py_result == NULL )
      return 0;

    uint64 num = 0;
    PyW_GetNumber(py_result.o, &num);
    return asize_t(num);
  }

public:
  const char *get_name() const
  {
    return dt_name.c_str();
  }

  py_custom_data_type_t()
  {
    dtid = -1;
    py_self = NULL;
  }

  int register_dt(PyObject *py_obj)
  {
    PYW_GIL_CHECK_LOCKED_SCOPE();

    // Already registered?
    if ( dtid >= 0 )
      return dtid;

    memset(&dt, 0, sizeof(dt));
    dt.cbsize = sizeof(dt);
    dt.ud = this;

    do
    {
      ref_t py_attr;

      // name
      if ( !PyW_GetStringAttr(py_obj, S_NAME, &dt_name) )
        break;

      dt.name = dt_name.c_str();

      // menu_name (optional)
      if ( PyW_GetStringAttr(py_obj, S_MENU_NAME, &dt_menu_name) )
        dt.menu_name = dt_menu_name.c_str();

      // asm_keyword (optional)
      if ( PyW_GetStringAttr(py_obj, S_ASM_KEYWORD, &dt_asm_keyword) )
        dt.asm_keyword = dt_asm_keyword.c_str();

      // hotkey (optional)
      if ( PyW_GetStringAttr(py_obj, S_HOTKEY, &dt_hotkey) )
        dt.hotkey = dt_hotkey.c_str();

      // value_size
      py_attr = PyW_TryGetAttrString(py_obj, S_VALUE_SIZE);
      if ( py_attr != NULL && PyInt_Check(py_attr.o) )
        dt.value_size = PyInt_AsLong(py_attr.o);
      py_attr = ref_t();

      // props
      py_attr = PyW_TryGetAttrString(py_obj, S_PROPS);
      if ( py_attr != NULL && PyInt_Check(py_attr.o) )
        dt.props = PyInt_AsLong(py_attr.o);
      py_attr = ref_t();

      // may_create_at
      py_attr = PyW_TryGetAttrString(py_obj, S_MAY_CREATE_AT);
      if ( py_attr != NULL && PyCallable_Check(py_attr.o) )
        dt.may_create_at = s_may_create_at;
      py_attr = ref_t();

      // calc_item_size
      py_attr = PyW_TryGetAttrString(py_obj, S_CALC_ITEM_SIZE);
      if ( py_attr != NULL && PyCallable_Check(py_attr.o) )
        dt.calc_item_size = s_calc_item_size;
      py_attr = ref_t();

      // Now try to register
      dtid = register_custom_data_type(&dt);
      if ( dtid < 0 )
        break;

      // Hold reference to the PyObject
      Py_INCREF(py_obj);
      py_self = py_obj;

      py_attr = newref_t(PyInt_FromLong(dtid));
      PyObject_SetAttrString(py_obj, S_ID, py_attr.o);
    } while ( false );
    return dtid;
  }

  bool unregister_dt()
  {
    PYW_GIL_CHECK_LOCKED_SCOPE();

    if ( dtid < 0 )
      return true;

    if ( !unregister_custom_data_type(dtid) )
      return false;

    // Release reference of Python object
    Py_XDECREF(py_self);
    py_self = NULL;
    dtid = -1;
    return true;
  }

  ~py_custom_data_type_t()
  {
    unregister_dt();
  }
};
typedef std::map<int, py_custom_data_type_t *> py_custom_data_type_map_t;
static py_custom_data_type_map_t py_dt_map;

//------------------------------------------------------------------------
class py_custom_data_format_t
{
private:
  data_format_t df;
  int dfid;
  PyObject *py_self;
  qstring df_name, df_menu_name, df_hotkey;

  static bool idaapi s_print(       // convert to colored string
    void *ud,                       // user-defined data
    qstring *out,                   // output buffer. may be NULL
    const void *value,              // value to print. may not be NULL
    asize_t size,                   // size of value in bytes
    ea_t current_ea,                // current address (BADADDR if unknown)
    int operand_num,                // current operand number
    int dtid)                       // custom data type id
  {
    PYW_GIL_GET;

    // Build a string from the buffer
    newref_t py_value(PyString_FromStringAndSize(
                              (const char *)value,
                              Py_ssize_t(size)));
    if ( py_value == NULL )
      return false;

    py_custom_data_format_t *_this = (py_custom_data_format_t *) ud;
    newref_t py_result(PyObject_CallMethod(
                               _this->py_self,
                               (char *)S_PRINTF,
                               "O" PY_FMT64 "ii",
                               py_value.o,
                               pyul_t(current_ea),
                               operand_num,
                               dtid));

    // Error while calling the function?
    if ( PyW_ShowCbErr(S_PRINTF) || py_result == NULL )
      return false;

    bool ok = false;
    if ( PyString_Check(py_result.o) )
    {
      Py_ssize_t len;
      char *buf;
      if ( out != NULL && PyString_AsStringAndSize(py_result.o, &buf, &len) != -1 )
      {
        out->qclear();
        out->append(buf, len);
      }
      ok = true;
    }
    return ok;
  }

  static bool idaapi s_scan(        // convert from uncolored string
    void *ud,                       // user-defined data
    bytevec_t *value,               // output buffer. may be NULL
    const char *input,              // input string. may not be NULL
    ea_t current_ea,                // current address (BADADDR if unknown)
    int operand_num,                // current operand number (-1 if unknown)
    qstring *errstr)                // buffer for error message
  {
    PYW_GIL_GET;

    py_custom_data_format_t *_this = (py_custom_data_format_t *) ud;
    newref_t py_result(
            PyObject_CallMethod(
                    _this->py_self,
                    (char *)S_SCAN,
                    "s" PY_FMT64,
                    input,
                    pyul_t(current_ea),
                    operand_num));

    // Error while calling the function?
    if ( PyW_ShowCbErr(S_SCAN) || py_result == NULL)
      return false;

    bool ok = false;
    do
    {
      // We expect a tuple(bool, string|None)
      if ( !PyTuple_Check(py_result.o) || PyTuple_Size(py_result.o) != 2 )
        break;

      borref_t py_bool(PyTuple_GetItem(py_result.o, 0));
      borref_t py_val(PyTuple_GetItem(py_result.o, 1));

      // Get return code from Python
      ok = PyObject_IsTrue(py_bool.o);

      // We expect None or the value (depending on probe)
      if ( ok )
      {
        // Probe-only? Then okay, no need to extract the 'value'
        if ( value == NULL )
          break;

        Py_ssize_t len;
        char *buf;
        if ( PyString_AsStringAndSize(py_val.o, &buf, &len) != -1 )
        {
          value->qclear();
          value->append(buf, len);
        }
      }
      // An error occured?
      else
      {
        // Make sure the user returned (False, String)
        if ( py_bool.o != Py_False || !PyString_Check(py_val.o) )
        {
          *errstr = "Invalid return value returned from the Python callback!";
          break;
        }
        // Get the error message
        *errstr = PyString_AsString(py_val.o);
      }
    } while ( false );
    return ok;
  }

  static void idaapi s_analyze(     // analyze custom data format occurrence
    void *ud,                       // user-defined data
    ea_t current_ea,                // current address (BADADDR if unknown)
    int operand_num)                // current operand number
    // this callback can be used to create
    // xrefs from the current item.
    // this callback may be missing.
  {
    PYW_GIL_GET;

    py_custom_data_format_t *_this = (py_custom_data_format_t *) ud;
    newref_t py_result(
            PyObject_CallMethod(
                    _this->py_self,
                    (char *)S_ANALYZE,
                    PY_FMT64 "i",
                    pyul_t(current_ea),
                    operand_num));

    PyW_ShowCbErr(S_ANALYZE);
  }
public:
  py_custom_data_format_t()
  {
    dfid = -1;
    py_self = NULL;
  }

  const char *get_name() const
  {
    return df_name.c_str();
  }

  int register_df(int dtid, PyObject *py_obj)
  {
    // Already registered?
    if ( dfid >= 0 )
      return dfid;

    memset(&df, 0, sizeof(df));
    df.cbsize = sizeof(df);
    df.ud = this;

    PYW_GIL_CHECK_LOCKED_SCOPE();
    do
    {
      ref_t py_attr;

      // name
      if ( !PyW_GetStringAttr(py_obj, S_NAME, &df_name) )
        break;
      df.name = df_name.c_str();

      // menu_name (optional)
      if ( PyW_GetStringAttr(py_obj, S_MENU_NAME, &df_menu_name) )
        df.menu_name = df_menu_name.c_str();

      // props
      py_attr = PyW_TryGetAttrString(py_obj, S_PROPS);
      if ( py_attr != NULL && PyInt_Check(py_attr.o) )
        df.props = PyInt_AsLong(py_attr.o);

      // hotkey
      if ( PyW_GetStringAttr(py_obj, S_HOTKEY, &df_hotkey) )
        df.hotkey = df_hotkey.c_str();

      // value_size
      py_attr = PyW_TryGetAttrString(py_obj, S_VALUE_SIZE);
      if ( py_attr != NULL && PyInt_Check(py_attr.o) )
        df.value_size = PyInt_AsLong(py_attr.o);

      // text_width
      py_attr = PyW_TryGetAttrString(py_obj, S_TEXT_WIDTH);
      if ( py_attr != NULL && PyInt_Check(py_attr.o) )
        df.text_width = PyInt_AsLong(py_attr.o);

      // print cb
      py_attr = PyW_TryGetAttrString(py_obj, S_PRINTF);
      if ( py_attr != NULL && PyCallable_Check(py_attr.o) )
        df.print = s_print;

      // scan cb
      py_attr = PyW_TryGetAttrString(py_obj, S_SCAN);
      if ( py_attr != NULL && PyCallable_Check(py_attr.o) )
        df.scan = s_scan;

      // analyze cb
      py_attr = PyW_TryGetAttrString(py_obj, S_ANALYZE);
      if ( py_attr != NULL && PyCallable_Check(py_attr.o) )
        df.analyze = s_analyze;

      // Now try to register
      dfid = register_custom_data_format(dtid, &df);
      if ( dfid < 0 )
        break;

      // Hold reference to the PyObject
      Py_INCREF(py_obj);
      py_self = py_obj;

      // Update the format ID
      py_attr = newref_t(PyInt_FromLong(dfid));
      PyObject_SetAttrString(py_obj, S_ID, py_attr.o);
    } while ( false );
    return dfid;
  }

  bool unregister_df(int dtid)
  {
    PYW_GIL_CHECK_LOCKED_SCOPE();

    // Never registered?
    if ( dfid < 0 )
      return true;

    if ( !unregister_custom_data_format(dtid, dfid) )
      return false;

    // Release reference of Python object
    Py_XDECREF(py_self);
    py_self = NULL;
    dfid = -1;
    return true;
  }

  ~py_custom_data_format_t()
  {
  }
};

//------------------------------------------------------------------------
// Helper class to bind <dtid, dfid> pairs to py_custom_data_format_t
class py_custom_data_format_list_t
{
  struct py_custom_data_format_entry_t
  {
    int dtid;
    int dfid;
    py_custom_data_format_t *df;
  };
  typedef qvector<py_custom_data_format_entry_t> ENTRY;
  ENTRY entries;
public:
  typedef ENTRY::iterator POS;
  void add(int dtid, int dfid, py_custom_data_format_t *df)
  {
    py_custom_data_format_entry_t &e = entries.push_back();
    e.dtid = dtid;
    e.dfid = dfid;
    e.df   = df;
  }
  py_custom_data_format_t *find(int dtid, int dfid, POS *loc = NULL)
  {
    for ( POS it=entries.begin(), it_end = entries.end(); it!=it_end; ++it )
    {
      if ( it->dfid == dfid && it->dtid == dtid )
      {
        if ( loc != NULL )
          *loc = it;
        return it->df;
      }
    }
    return NULL;
  }
  void erase(POS &pos)
  {
    entries.erase(pos);
  }
};
static py_custom_data_format_list_t py_df_list;

//------------------------------------------------------------------------
static PyObject *py_data_type_to_py_dict(const data_type_t *dt)
{
  PYW_GIL_CHECK_LOCKED_SCOPE();

  return Py_BuildValue("{s:" PY_FMT64 ",s:i,s:i,s:s,s:s,s:s,s:s}",
    S_VALUE_SIZE, pyul_t(dt->value_size),
    S_PROPS, dt->props,
    S_CBSIZE, dt->cbsize,
    S_NAME, dt->name == NULL ? "" : dt->name,
    S_MENU_NAME, dt->menu_name == NULL ? "" : dt->menu_name,
    S_HOTKEY, dt->hotkey == NULL ? "" : dt->hotkey,
    S_ASM_KEYWORD, dt->asm_keyword == NULL ? "" : dt->asm_keyword);
}

//------------------------------------------------------------------------
static PyObject *py_data_format_to_py_dict(const data_format_t *df)
{
  PYW_GIL_CHECK_LOCKED_SCOPE();

  return Py_BuildValue("{s:i,s:i,s:i,s:" PY_FMT64 ",s:s,s:s,s:s}",
    S_PROPS, df->props,
    S_CBSIZE, df->cbsize,
    S_TEXT_WIDTH, df->text_width,
    S_VALUE_SIZE, pyul_t(df->value_size),
    S_NAME, df->name == NULL ? "" : df->name,
    S_MENU_NAME, df->menu_name == NULL ? "" : df->menu_name,
    S_HOTKEY, df->hotkey == NULL ? "" : df->hotkey);
}
//</code(py_bytes)>
%}

%inline %{
//<inline(py_bytes)>

//------------------------------------------------------------------------
/*
#<pydoc>
def visit_patched_bytes(ea1, ea2, callable):
    """
    Enumerates patched bytes in the given range and invokes a callable
    @param ea1: start address
    @param ea2: end address
    @param callable: a Python callable with the following prototype:
                     callable(ea, fpos, org_val, patch_val).
                     If the callable returns non-zero then that value will be
                     returned to the caller and the enumeration will be
                     interrupted.
    @return: Zero if the enumeration was successful or the return
             value of the callback if enumeration was interrupted.
    """
    pass
#</pydoc>
*/
static int py_visit_patched_bytes(ea_t ea1, ea_t ea2, PyObject *py_callable)
{
  PYW_GIL_CHECK_LOCKED_SCOPE();
  if ( !PyCallable_Check(py_callable) )
    return 0;
  else
    return visit_patched_bytes(ea1, ea2, py_visit_patched_bytes_cb, py_callable);
}

//------------------------------------------------------------------------
/*
#<pydoc>
def nextthat(ea, maxea, callable):
    """
    Find next address with a flag satisfying the function 'testf'.
    Start searching from address 'ea'+1 and inspect bytes up to 'maxea'.
    maxea is not included in the search range.

    @param callable: a Python callable with the following prototype:
                     callable(flags). Return True to stop enumeration.
    @return: the found address or BADADDR.
    """
    pass
#</pydoc>
*/
static ea_t py_nextthat(ea_t ea, ea_t maxea, PyObject *callable)
{
  return py_npthat(ea, maxea, callable, true);
}

//---------------------------------------------------------------------------
static ea_t py_prevthat(ea_t ea, ea_t minea, PyObject *callable)
{
  return py_npthat(ea, minea, callable, false);
}

//------------------------------------------------------------------------
/*
#<pydoc>
def get_many_bytes(ea, size):
    """
    Get the specified number of bytes of the program into the buffer.
    @param ea: program address
    @param size: number of bytes to return
    @return: None or the string buffer
    """
    pass
#</pydoc>
*/
static PyObject *py_get_many_bytes(ea_t ea, unsigned int size)
{
  PYW_GIL_CHECK_LOCKED_SCOPE();
  do
  {
    if ( size <= 0 )
      break;

    // Allocate memory via Python
    newref_t py_buf(PyString_FromStringAndSize(NULL, Py_ssize_t(size)));
    if ( py_buf == NULL )
      break;

    // Read bytes
    if ( !get_many_bytes(ea, PyString_AsString(py_buf.o), size) )
      Py_RETURN_NONE;

    py_buf.incref();
    return py_buf.o;
  } while ( false );
  Py_RETURN_NONE;
}

//---------------------------------------------------------------------------
/*
#<pydoc>
# Conversion options for get_ascii_contents2():
ACFOPT_ASCII    = 0x00000000 # convert Unicode strings to ASCII
ACFOPT_UTF16    = 0x00000001 # return UTF-16 (aka wide-char) array for Unicode strings
                             # ignored for non-Unicode strings
ACFOPT_UTF8     = 0x00000002 # convert Unicode strings to UTF-8
                             # ignored for non-Unicode strings
ACFOPT_CONVMASK = 0x0000000F
ACFOPT_ESCAPE   = 0x00000010 # for ACFOPT_ASCII, convert non-printable
                             # characters to C escapes (\n, \xNN, \uNNNN)

def get_ascii_contents2(ea, len, type, flags = ACFOPT_ASCII):
  """
  Get bytes contents at location, possibly converted.
  It works even if the string has not been created in the database yet.

  Note that this will <b>always</b> return a simple string of bytes
  (i.e., a 'str' instance), and not a string of unicode characters.

  If you want auto-conversion to unicode strings (that is: real strings),
  you should probably be using the idautils.Strings class.

  @param ea: linear address of the string
  @param len: length of the string in bytes (including terminating 0)
  @param type: type of the string. Represents both the character encoding,
               <u>and</u> the 'type' of string at the given location.
  @param flags: combination of ACFOPT_..., to perform output conversion.
  @return: a bytes-filled str object.
  """
  pass
#</pydoc>
*/
static PyObject *py_get_ascii_contents2(
    ea_t ea,
    size_t len,
    int32 type,
    int flags = ACFOPT_ASCII)
{
  char *buf = (char *)qalloc(len+1);
  if ( buf == NULL )
    return NULL;

  size_t used_size;
  if ( !get_ascii_contents2(ea, len, type, buf, len+1, &used_size, flags) )
  {
    qfree(buf);
    Py_RETURN_NONE;
  }
  if ( type == ASCSTR_C && used_size > 0 && buf[used_size-1] == '\0' )
    used_size--;
  PYW_GIL_CHECK_LOCKED_SCOPE();
  newref_t py_buf(PyString_FromStringAndSize((const char *)buf, used_size));
  qfree(buf);
  py_buf.incref();
  return py_buf.o;
}
//---------------------------------------------------------------------------
/*
#<pydoc>
def get_ascii_contents(ea, len, type):
  """
  Get contents of ascii string
  This function returns the displayed part of the string
  It works even if the string has not been created in the database yet.

  @param ea: linear address of the string
  @param len: length of the string in bytes (including terminating 0)
  @param type: type of the string
  @return: string contents (not including terminating 0) or None
  """
  pass
#</pydoc>
*/
static PyObject *py_get_ascii_contents(
    ea_t ea,
    size_t len,
    int32 type)
{
  return py_get_ascii_contents2(ea, len, type);
}



//------------------------------------------------------------------------
/*
#<pydoc>
def register_custom_data_type(dt):
    """
    Registers a custom data type.
    @param dt: an instance of the data_type_t class
    @return:
        < 0 if failed to register
        > 0 data type id
    """
    pass
#</pydoc>
*/
// Given a py.data_format_t object, this function will register a datatype
static int py_register_custom_data_type(PyObject *py_dt)
{
  py_custom_data_type_t *inst = new py_custom_data_type_t();
  int r = inst->register_dt(py_dt);
  if ( r < 0 )
  {
    delete inst;
    return r;
  }
  // Insert the instance to the map
  py_dt_map[r] = inst;
  return r;
}

//------------------------------------------------------------------------
/*
#<pydoc>
def unregister_custom_data_type(dtid):
    """
    Unregisters a custom data type.
    @param dtid: the data type id
    @return: Boolean
    """
    pass
#</pydoc>
*/
static bool py_unregister_custom_data_type(int dtid)
{
  py_custom_data_type_map_t::iterator it = py_dt_map.find(dtid);

  // Maybe the user is trying to unregister a C api dt?
  if ( it == py_dt_map.end() )
    return unregister_custom_data_type(dtid);

  py_custom_data_type_t *inst = it->second;
  bool ok = inst->unregister_dt();

  // Perhaps it was automatically unregistered because the idb was close?
  if ( !ok )
  {
    // Is this type still registered with IDA?
    // If not found then mark the context for deletion
    ok = find_custom_data_type(inst->get_name()) < 0;
  }

  if ( ok )
  {
    py_dt_map.erase(it);
    delete inst;
  }
  return ok;
}

//------------------------------------------------------------------------
/*
#<pydoc>
def register_custom_data_format(dtid, df):
    """
    Registers a custom data format with a given data type.
    @param dtid: data type id
    @param df: an instance of data_format_t
    @return:
        < 0 if failed to register
        > 0 data format id
    """
    pass
#</pydoc>
*/
static int py_register_custom_data_format(int dtid, PyObject *py_df)
{
  py_custom_data_format_t *inst = new py_custom_data_format_t();
  int r = inst->register_df(dtid, py_df);
  if ( r < 0 )
  {
    delete inst;
    return r;
  }
  // Insert the instance
  py_df_list.add(dtid, r, inst);
  return r;
}

//------------------------------------------------------------------------
/*
#<pydoc>
def unregister_custom_data_format(dtid, dfid):
    """
    Unregisters a custom data format
    @param dtid: data type id
    @param dfid: data format id
    @return: Boolean
    """
    pass
#</pydoc>
*/
static bool py_unregister_custom_data_format(int dtid, int dfid)
{
  py_custom_data_format_list_t::POS pos;
  py_custom_data_format_t *inst = py_df_list.find(dtid, dfid, &pos);
  // Maybe the user is trying to unregister a C api data format?
  if ( inst == NULL )
    return unregister_custom_data_format(dtid, dfid);

  bool ok = inst->unregister_df(dtid);

  // Perhaps it was automatically unregistered because the type was unregistered?
  if ( !ok )
  {
    // Is this format still registered with IDA?
    // If not, mark the context for deletion
    ok = find_custom_data_format(inst->get_name()) < 0;
  }

  if ( ok )
  {
    py_df_list.erase(pos);
    delete inst;
  }
  return ok;
}

//------------------------------------------------------------------------
/*
#<pydoc>
def get_custom_data_format(dtid, dfid):
    """
    Returns a dictionary populated with the data format values or None on failure.
    @param dtid: data type id
    @param dfid: data format id
    """
    pass
#</pydoc>
*/
// Get definition of a registered custom data format and returns a dictionary
static PyObject *py_get_custom_data_format(int dtid, int fid)
{
  PYW_GIL_CHECK_LOCKED_SCOPE();
  const data_format_t *df = get_custom_data_format(dtid, fid);
  if ( df == NULL )
    Py_RETURN_NONE;
  return py_data_format_to_py_dict(df);
}

//------------------------------------------------------------------------
/*
#<pydoc>
def get_custom_data_type(dtid):
    """
    Returns a dictionary populated with the data type values or None on failure.
    @param dtid: data type id
    """
    pass
#</pydoc>
*/
// Get definition of a registered custom data format and returns a dictionary
static PyObject *py_get_custom_data_type(int dtid)
{
  PYW_GIL_CHECK_LOCKED_SCOPE();
  const data_type_t *dt = get_custom_data_type(dtid);
  if ( dt == NULL )
    Py_RETURN_NONE;
  return py_data_type_to_py_dict(dt);
}

//</inline(py_bytes)>
%}

%pythoncode %{
#<pycode(py_bytes)>
DTP_NODUP = 0x0001

class data_type_t(object):
    """
    Custom data type definition. All data types should inherit from this class.
    """

    def __init__(self, name, value_size = 0, menu_name = None, hotkey = None, asm_keyword = None, props = 0):
        """Please refer to bytes.hpp / data_type_t in the SDK"""
        self.name  = name
        self.props = props
        self.menu_name = menu_name
        self.hotkey = hotkey
        self.asm_keyword = asm_keyword
        self.value_size = value_size

        self.id = -1 # Will be initialized after registration
        """Contains the data type id after the data type is registered"""

    def register(self):
        """Registers the data type and returns the type id or < 0 on failure"""
        return _idaapi.register_custom_data_type(self)

    def unregister(self):
        """Unregisters the data type and returns True on success"""
        # Not registered?
        if self.id < 0:
            return True

        # Try to unregister
        r = _idaapi.unregister_custom_data_type(self.id)

        # Clear the ID
        if r:
            self.id = -1
        return r
#<pydoc>
#    def may_create_at(self, ea, nbytes):
#        """
#        (optional) If this callback is not defined then this means always may create data type at the given ea.
#        @param ea: address of the future item
#        @param nbytes: size of the future item
#        @return: Boolean
#        """
#
#        return False
#
#    def calc_item_size(self, ea, maxsize):
#        """
#        (optional) If this callback is defined it means variable size datatype
#        This function is used to determine size of the (possible) item at 'ea'
#        @param ea: address of the item
#        @param maxsize: maximal size of the item
#        @return: integer
#            Returns: 0-no such item can be created/displayed
#                     this callback is required only for varsize datatypes
#        """
#        return 0
#</pydoc>
# -----------------------------------------------------------------------
# Uncomment the corresponding callbacks in the inherited class
class data_format_t(object):
    """Information about a data format"""
    def __init__(self, name, value_size = 0, menu_name = None, props = 0, hotkey = None, text_width = 0):
        """Custom data format definition.
        @param name: Format name, must be unique
        @param menu_name: Visible format name to use in menus
        @param props: properties (currently 0)
        @param hotkey: Hotkey for the corresponding menu item
        @param value_size: size of the value in bytes. 0 means any size is ok
        @text_width: Usual width of the text representation
        """
        self.name = name
        self.menu_name = menu_name
        self.props = props
        self.hotkey = hotkey
        self.value_size = value_size
        self.text_width = text_width

        self.id = -1 # Will be initialized after registration
        """contains the format id after the format gets registered"""

    def register(self, dtid):
        """Registers the data format with the given data type id and returns the type id or < 0 on failure"""
        return _idaapi.register_custom_data_format(dtid, self)

    def unregister(self, dtid):
        """Unregisters the data format with the given data type id"""

        # Not registered?
        if self.id < 0:
            return True

        # Unregister
        r = _idaapi.unregister_custom_data_format(dtid, self.id)

        # Clear the ID
        if r:
            self.id = -1
        return r
#<pydoc>
#    def printf(self, value, current_ea, operand_num, dtid):
#        """
#        Convert a value buffer to colored string.
#
#        @param value: The value to be printed
#        @param current_ea: The ea of the value
#        @param operand_num: The affected operand
#        @param dtid: custom data type id (0-standard built-in data type)
#        @return: a colored string representing the passed 'value' or None on failure
#        """
#        return None
#
#    def scan(self, input, current_ea, operand_num):
#        """
#        Convert from uncolored string 'input' to byte value
#
#        @param input: input string
#        @param current_ea: current address (BADADDR if unknown)
#        @param operand_num: current operand number (-1 if unknown)
#
#        @return: tuple (Boolean, string)
#            - (False, ErrorMessage) if conversion fails
#            - (True, Value buffer) if conversion succeeds
#        """
#        return (False, "Not implemented")
#
#    def analyze(self, current_ea, operand_num):
#        """
#        (optional) Analyze custom data format occurrence.
#        It can be used to create xrefs from the current item.
#
#        @param current_ea: current address (BADADDR if unknown)
#        @param operand_num: current operand number
#        @return: None
#        """
#
#        pass
#</pydoc>
# -----------------------------------------------------------------------
def __walk_types_and_formats(formats, type_action, format_action, installing):
    broken = False
    for f in formats:
        if len(f) == 1:
            if not format_action(f[0], 0):
                broken = True
                break
        else:
            dt  = f[0]
            dfs = f[1:]
            # install data type before installing formats
            if installing and not type_action(dt):
                broken = True
                break
            # process formats using the correct dt.id
            for df in dfs:
                if not format_action(df, dt.id):
                    broken = True
                    break
            # uninstall data type after uninstalling formats
            if not installing and not type_action(dt):
                broken = True
                break
    return not broken

# -----------------------------------------------------------------------
def register_data_types_and_formats(formats):
    """
    Registers multiple data types and formats at once.
    To register one type/format at a time use register_custom_data_type/register_custom_data_format

    It employs a special table of types and formats described below:

    The 'formats' is a list of tuples. If a tuple has one element then it is the format to be registered with dtid=0
    If the tuple has more than one element, then tuple[0] is the data type and tuple[1:] are the data formats. For example:
    many_formats = [
      (pascal_data_type(), pascal_data_format()),
      (simplevm_data_type(), simplevm_data_format()),
      (makedword_data_format(),),
      (simplevm_data_format(),)
    ]
    The first two tuples describe data types and their associated formats.
    The last two tuples describe two data formats to be used with built-in data types.
    """
    def __reg_format(df, dtid):
        df.register(dtid)
        if dtid == 0:
            print "Registered format '%s' with built-in types, ID=%d" % (df.name, df.id)
        else:
            print "   Registered format '%s', ID=%d (dtid=%d)" % (df.name, df.id, dtid)
        return df.id != -1

    def __reg_type(dt):
        dt.register()
        print "Registered type '%s', ID=%d" % (dt.name, dt.id)
        return dt.id != -1
    ok = __walk_types_and_formats(formats, __reg_type, __reg_format, True)
    return 1 if ok else -1

# -----------------------------------------------------------------------
def unregister_data_types_and_formats(formats):
    """As opposed to register_data_types_and_formats(), this function
    unregisters multiple data types and formats at once.
    """
    def __unreg_format(df, dtid):
        print "%snregistering format '%s'" % ("U" if dtid == 0 else "   u", df.name)
        df.unregister(dtid)
        return True

    def __unreg_type(dt):
        print "Unregistering type '%s', ID=%d" % (dt.name, dt.id)
        dt.unregister()
        return True
    ok = __walk_types_and_formats(formats, __unreg_type, __unreg_format, False)
    return 1 if ok else -1

#</pycode(py_bytes)>
%}
