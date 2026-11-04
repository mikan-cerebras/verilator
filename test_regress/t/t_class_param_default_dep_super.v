// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Calls to the base class through the default specialization of a class whose
// type parameter default depends on another parameter (IEEE 1800-2023 6.20.1, 8.15)

class item_c;
endclass

class base_c;
  int base_new;
  function new(string name = "base");
    base_new++;
  endfunction
endclass

class seq_c #(
    type REQ = item_c,
    type RSP = REQ
) extends base_c;
  int seq_new;
  int body_calls;
  int plain_calls;
  static int static_calls;
  function new(string name = "seq");
    super.new(name);
    seq_new++;
  endfunction
  virtual function void body();
    body_calls++;
  endfunction
  function void plain();
    plain_calls++;
  endfunction
  static function void sfunc();
    static_calls++;
  endfunction
endclass

// Default specialization, super.new with arguments
class vseq_c extends seq_c;
  function new(string name = "vseq");
    super.new(name);
  endfunction
  virtual function void body();
    super.body();
  endfunction
  function void plain();
    super.plain();
  endfunction
endclass

// Implicit super.new
class vseq_imp_c extends seq_c;
endclass

// Explicit specializations equal to the default
class vseq_x1_c extends seq_c #(item_c);
  function new();
    super.new();
  endfunction
  virtual function void body();
    super.body();
  endfunction
endclass

class vseq_x2_c extends seq_c #(item_c, item_c);
  virtual function void body();
    super.body();
  endfunction
endclass

// Derived from a derived class
class vseq2_c extends vseq_c;
  function new();
    super.new("vseq2");
  endfunction
  virtual function void body();
    super.body();
  endfunction
endclass

// Chain of dependent defaults, and a value parameter in between
class chain_c #(
    type A = item_c,
    int N = 3,
    type B = A,
    type C = B
);
  int chain_new;
  function new();
    chain_new = N;
  endfunction
  virtual function int get();
    return N;
  endfunction
endclass

class vchain_c extends chain_c;
  function new();
    super.new();
  endfunction
  virtual function int get();
    return super.get() + 10;
  endfunction
endclass

class vchain5_c extends chain_c #(.N(5));
  virtual function int get();
    return super.get() + 10;
  endfunction
endclass

// Nested parameterized class in a dependent default
class box_c #(
    type T = int
);
  T v;
endclass

class nest_c #(
    type T = item_c,
    type B = box_c#(T)
);
  B b;
  function new();
    b = new;
  endfunction
  virtual function int get();
    return 1;
  endfunction
endclass

class vnest_c extends nest_c;
  function new();
    super.new();
  endfunction
  virtual function int get();
    return super.get() + 1;
  endfunction
endclass

// UVM-like sequence and sequencer hierarchies
class uvm_sequence_item;
endclass

class my_item extends uvm_sequence_item;
endclass

class uvm_sequence_base;
  int base_new;
  function new(string name = "uvm_sequence_base");
    base_new++;
  endfunction
  virtual task body();
  endtask
endclass

class uvm_sequence #(
    type REQ = uvm_sequence_item,
    type RSP = REQ
) extends uvm_sequence_base;
  typedef uvm_sequence#(REQ, RSP) this_type;
  int seq_new;
  int body_calls;
  function new(string name = "uvm_sequence");
    super.new(name);
    seq_new++;
  endfunction
  virtual task body();
    body_calls++;
  endtask
  function this_type self();
    return this;
  endfunction
endclass

class uvm_sequencer_base;
  int base_new;
  function new(string name);
    base_new++;
  endfunction
endclass

class uvm_sequencer_param_base #(
    type REQ = uvm_sequence_item,
    type RSP = REQ
) extends uvm_sequencer_base;
  int param_new;
  function new(string name);
    super.new(name);
    param_new++;
  endfunction
endclass

class uvm_sequencer #(
    type REQ = uvm_sequence_item,
    type RSP = REQ
) extends uvm_sequencer_param_base #(REQ, RSP);
  typedef uvm_sequencer#(REQ, RSP) this_type;
  int sqr_new;
  function new(string name);
    super.new(name);
    sqr_new++;
  endfunction
endclass

class my_sequencer extends uvm_sequencer;
  function new(string name);
    super.new(name);
  endfunction
endclass

class my_item_sequencer extends uvm_sequencer #(my_item);
  function new(string name);
    super.new(name);
  endfunction
endclass

class my_vseq extends uvm_sequence;
  function new(string name = "my_vseq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
  endtask
endclass

class my_item_seq extends uvm_sequence #(my_item);
  function new(string name = "my_item_seq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
  endtask
endclass

module t;
  initial begin
    automatic vseq_c v = new;
    automatic vseq_imp_c vi = new;
    automatic vseq_x1_c vx1 = new;
    automatic vseq_x2_c vx2 = new;
    automatic vseq2_c v2 = new;
    automatic seq_c sd;
    automatic seq_c #(item_c, item_c) sx;
    automatic vchain_c vc = new;
    automatic vchain5_c vc5 = new;
    automatic vnest_c vn = new;
    automatic my_sequencer sqr = new("sqr");
    automatic my_item_sequencer isqr = new("isqr");
    automatic my_vseq mv = new;
    automatic my_item_seq mis = new;
    automatic uvm_sequence us;

    `checkd(v.base_new, 1);
    `checkd(v.seq_new, 1);
    v.body();
    v.plain();
    `checkd(v.body_calls, 1);
    `checkd(v.plain_calls, 1);
    `checkd(vi.base_new, 1);
    `checkd(vi.seq_new, 1);
    `checkd(vx1.seq_new, 1);
    vx1.body();
    `checkd(vx1.body_calls, 1);
    `checkd(vx2.seq_new, 1);
    vx2.body();
    `checkd(vx2.body_calls, 1);
    `checkd(v2.base_new, 1);
    `checkd(v2.seq_new, 1);
    v2.body();
    `checkd(v2.body_calls, 1);
    // The default specialization is the same type however it is written
    sd = v;
    sx = sd;
    sd = vx1;
    sd = vx2;
    sd.body();
    `checkd(vx2.body_calls, 2);
    seq_c#()::sfunc();
    `checkd(seq_c#(item_c)::static_calls, 1);

    `checkd(vc.chain_new, 3);
    `checkd(vc.get(), 13);
    `checkd(vc5.chain_new, 5);
    `checkd(vc5.get(), 15);
    `checkd(vn.get(), 2);

    `checkd(sqr.base_new, 1);
    `checkd(sqr.param_new, 1);
    `checkd(sqr.sqr_new, 1);
    `checkd(isqr.sqr_new, 1);
    `checkd(mv.base_new, 1);
    `checkd(mv.seq_new, 1);
    mv.body();
    `checkd(mv.body_calls, 1);
    us = mv.self();
    us.body();
    `checkd(mv.body_calls, 2);
    `checkd(mis.seq_new, 1);
    mis.body();
    `checkd(mis.body_calls, 1);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
