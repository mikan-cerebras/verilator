// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Virtual interfaces of an interface type that is instantiated only inside another interface

interface ch_if;
  logic [6:0] d;
endinterface

interface bus_if;
  ch_if o ();
  ch_if p ();
endinterface

// Only an array, or a queue, of virtual interfaces
module arr_user;  // verilator no_inline_module
  virtual ch_if va[3];
  initial va[1] = t.b.p;
  final `checkh(va[1].d, 7'h2a);
endmodule

module queue_user;  // verilator no_inline_module
  virtual ch_if vq[$];
  initial vq.push_back(t.b.p);
  final `checkh(vq[0].d, 7'h2a);
endmodule

module t;
  bus_if b ();
  arr_user u_arr ();
  queue_user u_queue ();
  virtual ch_if vif;
  virtual ch_if va[3];

  initial begin
    vif = b.o;
    va[2] = b.p;
    vif.d = 7'h15;
    va[2].d = 7'h2a;
    `checkh(b.o.d, 7'h15);
    `checkh(b.p.d, 7'h2a);
    b.o.d = 7'h33;
    `checkh(vif.d, 7'h33);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
