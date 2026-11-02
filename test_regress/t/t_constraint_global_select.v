// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Constraints selecting through a rand member are solved with the member's own
// constraints (IEEE 1800-2023 18.5.9), whatever the form of the selection
class M;
  rand bit [7:0] x;
  rand bit [7:0] a[3];
  constraint c_x {x < 10;}
  constraint c_a {foreach (a[i]) a[i] < 20;}
endclass

class CExpr;
  rand M m;
  rand bit [7:0] y;
  function new;
    m = new;
  endfunction
  constraint c {y == m.x + 100;}
endclass

class CForeach;
  rand M m;
  rand bit [7:0] y;
  function new;
    m = new;
  endfunction
  constraint c {
    y inside {[10 : 15]};
    foreach (m.a[i]) m.a[i] > y;
  }
endclass

class CDist;
  rand M m;
  function new;
    m = new;
  endfunction
  constraint c {m.x dist {5 := 1, 50 := 1};}
endclass

class CImpl;
  rand M m;
  rand bit y;
  function new;
    m = new;
  endfunction
  constraint c {
    y == 1;
    y -> m.x > 6;
  }
endclass

class CIf;
  rand M m;
  rand bit [1:0] y;
  function new;
    m = new;
  endfunction
  constraint c {
    if (y == 0) m.x > 7;
    else m.x == 200 + y;
  }
endclass

class CBefore;
  rand M m;
  rand bit [7:0] y;
  function new;
    m = new;
  endfunction
  constraint c {
    y == m.x;
    solve m.x before y;
  }
endclass

// The selecting constraint is in a derived class of the container
class CBase;
  rand M m;
  function new;
    m = new;
  endfunction
endclass

class CDerived extends CBase;
  constraint c {m.x > 7;}
endclass

// Selected only by a 'with' clause of a randomize() call
class CWith;
  rand M m;
  function new;
    m = new;
  endfunction
endclass

module t;
  // Randomizing M on its own first must not make the containers solve it separately
  task automatic test_own();
    automatic M m = new;
    automatic int ok = m.randomize();
    `checkd(ok, 1);
    `checkd(m.x < 10, 1'b1);
  endtask

  initial begin
    automatic CExpr ce = new;
    automatic CForeach cf = new;
    automatic CDist cd = new;
    automatic CImpl ci = new;
    automatic CIf cif = new;
    automatic CBefore cb = new;
    automatic CDerived cdr = new;
    automatic CBase cbase = cdr;
    automatic CWith cw = new;
    automatic int ok;
    test_own();
    repeat (20) begin
      ok = ce.randomize();
      `checkd(ok, 1);
      `checkd(ce.m.x < 10, 1'b1);
      `checkd(ce.y, ce.m.x + 100);
      ok = cf.randomize();
      `checkd(ok, 1);
      foreach (cf.m.a[i]) `checkd(cf.m.a[i] > cf.y && cf.m.a[i] < 20, 1'b1);
      ok = cd.randomize();
      `checkd(ok, 1);
      `checkd(cd.m.x, 5);
      ok = ci.randomize();
      `checkd(ok, 1);
      `checkd(ci.m.x > 6 && ci.m.x < 10, 1'b1);
      ok = cif.randomize();
      `checkd(ok, 1);
      `checkd(cif.y, 0);
      `checkd(cif.m.x > 7 && cif.m.x < 10, 1'b1);
      ok = cb.randomize();
      `checkd(ok, 1);
      `checkd(cb.m.x < 10, 1'b1);
      `checkd(cb.y, cb.m.x);
      ok = cbase.randomize();
      `checkd(ok, 1);
      `checkd(cdr.m.x > 7 && cdr.m.x < 10, 1'b1);
      ok = cw.randomize() with {m.x > 7;};
      `checkd(ok, 1);
      `checkd(cw.m.x > 7 && cw.m.x < 10, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
