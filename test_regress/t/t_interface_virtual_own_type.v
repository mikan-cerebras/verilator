// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Interfaces declaring variables of their own virtual interface type

interface ifc;
  logic [6:0] r;
  modport mp(input r);
  function automatic bit same(virtual ifc o);
    virtual ifc v;
    virtual ifc.mp m;
    virtual ifc vs[2];
    v = o;
    m = o;
    vs[1] = o;
    return v == o && m.r == r && v.r == o.r && vs[1].r == o.r;
  endfunction
endinterface

// Two interfaces referencing each other's virtual interface type
interface ifa;
  logic [6:0] r;
  function automatic logic [6:0] get(virtual ifb o);
    return o.s;
  endfunction
endinterface

interface ifb;
  logic [6:0] s;
  function automatic logic [6:0] get(virtual ifa o);
    return o.r;
  endfunction
endinterface

// Many functions with arguments of the interface's own virtual interface type
interface ifm;
  int r;
  function automatic int f0(virtual ifm o);
    return o.r + 0;
  endfunction
  function automatic int f1(virtual ifm o);
    return o.r + 1;
  endfunction
  function automatic int f2(virtual ifm o);
    return o.r + 2;
  endfunction
  function automatic int f3(virtual ifm o);
    return o.r + 3;
  endfunction
  function automatic int f4(virtual ifm o);
    return o.r + 4;
  endfunction
  function automatic int f5(virtual ifm o);
    return o.r + 5;
  endfunction
  function automatic int f6(virtual ifm o);
    return o.r + 6;
  endfunction
  function automatic int f7(virtual ifm o);
    return o.r + 7;
  endfunction
  function automatic int f8(virtual ifm o);
    return o.r + 8;
  endfunction
  function automatic int f9(virtual ifm o);
    return o.r + 9;
  endfunction
  function automatic int f10(virtual ifm o);
    return o.r + 10;
  endfunction
  function automatic int f11(virtual ifm o);
    return o.r + 11;
  endfunction
  function automatic int f12(virtual ifm o);
    return o.r + 12;
  endfunction
  function automatic int f13(virtual ifm o);
    return o.r + 13;
  endfunction
  function automatic int f14(virtual ifm o);
    return o.r + 14;
  endfunction
  function automatic int f15(virtual ifm o);
    return o.r + 15;
  endfunction
  function automatic int f16(virtual ifm o);
    return o.r + 16;
  endfunction
  function automatic int f17(virtual ifm o);
    return o.r + 17;
  endfunction
  function automatic int f18(virtual ifm o);
    return o.r + 18;
  endfunction
  function automatic int f19(virtual ifm o);
    return o.r + 19;
  endfunction
endinterface

class Cls;
  virtual ifc v;
endclass

module t;
  ifc i ();
  ifc j ();
  ifa a ();
  ifb b ();
  ifm m ();

  initial begin
    automatic Cls c = new;
    c.v = i;
    i.r = 7'h15;
    j.r = 7'h2a;
    a.r = 7'h4c;
    b.s = 7'h33;
    `checkh(i.same(i), 1'b1);
    `checkh(i.same(j), 1'b0);
    `checkh(c.v.same(i), 1'b1);
    `checkh(c.v.same(j), 1'b0);
    `checkh(a.get(b), 7'h33);
    `checkh(b.get(a), 7'h4c);
    m.r = 5;
    `checkh(m.f19(m), 24);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
