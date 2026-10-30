// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

typedef class LaterTarget;
typedef class LaterPTarget;

class c1;
      rand int c1_f;
endclass
class c2;
      rand int c2_f;
endclass
localparam int PARAM = 42;
class Cls;
  rand int x;
  int q[$] = {0};
  rand enum {
    ONE_Y,
    TWO_Y
  } y;
  virtual function int get_x();
    return x;
  endfunction
endclass
class SubA extends Cls;
  c1 e = new;
  rand enum {
    AMBIG,
    ONE_A,
    TWO_A
  } en;
  function c1 get_c();
    return e;
  endfunction
  function int op(int v);
    return v + 1;
  endfunction
endclass
class SubB extends Cls;
  int z;
endclass
class SubC extends SubB;
  c2 e = new;
  rand enum {
    AMBIG,
    ONE_B,
    TWO_B
  } en;
  SubA f = new;
  function c2 get_c();
    return e;
  endfunction
  function int op(int v);
    return v - 1;
  endfunction
  function int doit;
    // access ambiguous names so width complains if we miss something
    doit = 1;

    f.x = 4;
    x = 5;
    doit = f.randomize() with { x == local::x; };
    if (f.x != x) $stop;

    z = 6;
    doit &= f.randomize() with { x == z; };
    if (f.x != z) $stop;

    doit &= f.randomize() with { e.c1_f == local::e.c2_f; };
    doit &= f.randomize() with { get_x() == local::get_x(); };
    doit &= f.randomize() with { get_c().c1_f == local::get_c().c2_f; };
    doit &= f.randomize() with { (get_c).c1_f == (local::get_c).c2_f; };

    f.y = ONE_Y;
    y = TWO_Y;
    doit &= f.randomize() with { y == local::y; };
    if (f.y != y) $stop;

    f.en = SubA::ONE_A;
    doit &= f.randomize() with { en == AMBIG; };
    if (doit != 1) $stop;
    if (f.en != SubA::AMBIG) $stop;

    doit &= f.randomize() with { x == PARAM; };
    if (doit != 1) $stop;
    if (f.x != PARAM) $stop;

    f.en = SubA::ONE_A;
    doit &= f.randomize() with { en == ONE_A; };
    doit &= f.randomize() with { local::en == local::AMBIG; };
    en = ONE_B;
    doit &= f.randomize() with { local::en == ONE_B; };

    doit &= f.randomize() with { x == local::op(op(0)); };
    if (f.x != 0) $stop;
    doit &= f.randomize() with { x == op(local::op(1)); };
    if (f.x != 1) $stop;
    doit &= f.randomize() with { x == local::op(op(local::op(op(0)))); };
    if (f.x != 0) $stop;
    doit &= f.randomize() with { x == op(local::op(op(local::op(1)))); };
    if (f.x != 1) $stop;
    doit &= f.randomize() with { foreach (q[i]) x == i; };
    if (f.x != 0) $stop;
  endfunction
endclass

// Target class defined after the call, inheriting the names the caller also declares
class LaterBase;
  rand int m_v;
  rand int m_w;
endclass
class LaterPBase #(int N = 1);
  rand int m_p;
endclass
class LaterCaller;
  int m_v = 5;
  int m_w = 6;
  int m_p = 7;
  function int doit(LaterTarget t, LaterPTarget pt);
    doit = t.randomize() with { m_v == local::m_v; this.m_w == local::m_w + 1; };
    if (t.m_v != 5) $stop;
    if (t.m_w != 7) $stop;
    t.m_v = 1;
    doit &= t.randomize(m_w);
    if (t.m_v != 1) $stop;
    doit &= pt.randomize() with { m_p == local::m_p; };
    if (pt.m_p != 7) $stop;
  endfunction
endclass
class LaterTarget extends LaterBase;
endclass
class LaterPTarget extends LaterPBase #(2);
endclass

module t;
  SubC obj = new;
  LaterCaller lc = new;
  LaterTarget lt = new;
  LaterPTarget lpt = new;

  initial begin
    if (obj.doit != 1) $stop;
    if (lc.doit(lt, lpt) != 1) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
