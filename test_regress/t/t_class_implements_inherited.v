// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Kristof Marien
// SPDX-License-Identifier: CC0-1.0

// A derived class may satisfy inherited pure virtual interface methods through
// concrete implementations inherited from its base class.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package if_pkg;
  interface class top_if;
    pure virtual function void set_value(string value);
    pure virtual function int get_a();
  endclass

  interface class mid_if extends top_if;
    pure virtual function int get_b();
  endclass

  interface class leaf_if extends mid_if;
    pure virtual function int get_c();
  endclass
endpackage

class base_cls implements if_pkg::mid_if;
  extern virtual function void set_value(string value);
  extern virtual function int get_a();
  extern virtual function int get_b();
endclass

function void base_cls::set_value(string value);
endfunction

function int base_cls::get_a();
  return 11;
endfunction

function int base_cls::get_b();
  return 22;
endfunction

class derived_cls extends base_cls implements if_pkg::leaf_if;
  extern virtual function void set_value(string value);
  extern virtual function int get_c();
endclass

function void derived_cls::set_value(string value);
endfunction

function int derived_cls::get_c();
  return 33;
endfunction

// Implementations two levels up
class grand_cls extends derived_cls implements if_pkg::leaf_if;
endclass

class pass_cls extends base_cls;
endclass

class from_pass_cls extends pass_cls implements if_pkg::mid_if;
endclass

// Implementations from a base class that does not implement the interface class
// (IEEE 1800-2023 8.26.2)
interface class other_if;
  pure virtual function int get_d(int x);
  pure virtual task get_e(output int v, input int x);
endclass

class plain_cls;
  extern virtual function int get_d(int x);
  virtual task get_e(output int v, input int x);
    v = 50 + x;
  endtask
endclass

function int plain_cls::get_d(int x);
  return 40 + x;
endfunction

class from_plain_cls extends plain_cls implements other_if;
endclass

class pass_plain_cls extends plain_cls;
endclass

class from_pass_plain_cls extends pass_plain_cls implements other_if;
endclass

// Implementation that is virtual because it overrides a virtual method (IEEE 1800-2023 8.20)
interface class f_if;
  pure virtual function int get_f();
endclass

class vbase_cls;
  virtual function int get_f();
    return 1;
  endfunction
endclass

class override_cls extends vbase_cls;
  function int get_f();
    return 60;
  endfunction
endclass

class from_override_cls extends override_cls implements f_if;
endclass

// Implementations from a parameterized base class
class param_cls #(type T = int) implements f_if;
  virtual function int get_f();
    return 70;
  endfunction
endclass

class from_param_cls extends param_cls #(int) implements f_if;
endclass

class pass_param_cls extends param_cls #(int);
endclass

class from_pass_param_cls extends pass_param_cls implements f_if;
endclass

// Implementations from a parameterized base class that does not implement the interface class
class plain_param_cls #(int N = 1);
  virtual function int get_f();
    return 80 + N;
  endfunction
endclass

class from_plain_param_cls extends plain_param_cls #(2) implements f_if;
endclass

class pass_plain_param_cls #(int N = 1) extends plain_param_cls #(N);
endclass

class from_pass_plain_param_cls extends pass_plain_param_cls #(3) implements f_if;
endclass

class param_from_plain_param_cls #(int N = 1) extends plain_param_cls #(N) implements f_if;
endclass

class type_from_plain_param_cls #(type T = plain_param_cls #(6)) extends T implements f_if;
endclass

// Implementations of a parameterized interface class and of a parameterized virtual class
interface class g_if #(type T = int);
  pure virtual function T get_g();
endclass

class from_g_if_cls extends plain_param_cls #(7) implements g_if #(int);
  virtual function int get_g();
    return 90;
  endfunction
endclass

virtual class abstract_param_cls #(type T = int);
  pure virtual function int get_h();
endclass

class from_abstract_param_cls extends abstract_param_cls #(int);
  virtual function int get_h();
    return 100;
  endfunction
endclass

// A class nested in one implementing an interface class is checked on its own
interface class f1_if;
  pure virtual function int f();
endclass
interface class f2_if;
  pure virtual function int f();
endclass
class nest_outer_param extends param_cls #(int) implements f1_if;
  virtual function int f();
    return 1;
  endfunction
  virtual class nest_inner implements f2_if;
  endclass
endclass
class nest_outer extends base_cls implements f1_if;
  virtual function int f();
    return 2;
  endfunction
  virtual class nest_inner implements f2_if;
  endclass
endclass

module t;
  initial begin
    derived_cls obj;
    grand_cls gobj;
    from_pass_cls pobj;
    from_plain_cls plobj;
    from_pass_plain_cls pplobj;
    from_override_cls ovobj;
    from_param_cls paobj;
    from_pass_param_cls ppaobj;
    from_plain_param_cls plpobj;
    from_pass_plain_param_cls pplpobj;
    param_from_plain_param_cls #(4) pfp4obj;
    param_from_plain_param_cls #(5) pfp5obj;
    type_from_plain_param_cls tfpobj;
    from_g_if_cls gobj2;
    from_abstract_param_cls apobj;
    g_if #(int) gifc;
    abstract_param_cls #(int) apcls;
    if_pkg::leaf_if ifc;
    if_pkg::mid_if mifc;
    other_if oifc;
    f_if fifc;
    int v;

    obj = new;
    ifc = obj;
    ifc.set_value("test");
    `checkd(ifc.get_a(), 11)
    `checkd(ifc.get_b(), 22)
    `checkd(ifc.get_c(), 33)

    gobj = new;
    ifc = gobj;
    `checkd(ifc.get_a(), 11)
    `checkd(ifc.get_b(), 22)
    `checkd(ifc.get_c(), 33)

    pobj = new;
    mifc = pobj;
    `checkd(mifc.get_a(), 11)
    `checkd(mifc.get_b(), 22)

    plobj = new;
    oifc = plobj;
    `checkd(oifc.get_d(1), 41)
    oifc.get_e(v, 2);
    `checkd(v, 52)

    pplobj = new;
    oifc = pplobj;
    `checkd(oifc.get_d(3), 43)
    oifc.get_e(v, 4);
    `checkd(v, 54)

    ovobj = new;
    fifc = ovobj;
    `checkd(fifc.get_f(), 60)

    paobj = new;
    fifc = paobj;
    `checkd(paobj.get_f(), 70)
    `checkd(fifc.get_f(), 70)

    ppaobj = new;
    fifc = ppaobj;
    `checkd(fifc.get_f(), 70)

    plpobj = new;
    fifc = plpobj;
    `checkd(plpobj.get_f(), 82)
    `checkd(fifc.get_f(), 82)

    pplpobj = new;
    fifc = pplpobj;
    `checkd(fifc.get_f(), 83)

    pfp4obj = new;
    fifc = pfp4obj;
    `checkd(fifc.get_f(), 84)
    pfp5obj = new;
    fifc = pfp5obj;
    `checkd(fifc.get_f(), 85)

    tfpobj = new;
    fifc = tfpobj;
    `checkd(fifc.get_f(), 86)

    gobj2 = new;
    gifc = gobj2;
    `checkd(gifc.get_g(), 90)
    `checkd(gobj2.get_f(), 87)

    apobj = new;
    apcls = apobj;
    `checkd(apcls.get_h(), 100)

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
