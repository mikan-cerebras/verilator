// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)

module t;
  bit clk;
  bit [2:0] y;
  bit [2:0] z;
  assign z[0] = 1'b1;
  assign z[1] = !(y[0]);
  assign z[2] = !(|y[1:0]);

  class A;
    virtual function void set(bit [2:0] v);
    endfunction
  endclass

  class B extends A;
    function void set(bit [2:0] v);
      // verilator no_inline_task
      y = v;
    endfunction
  endclass

  A a;

  // The same virtual call outside and inside a fork: only the forked one is in a suspendable
  always @(posedge clk) begin
    a.set(y);
    fork
      begin
        #1;
        a.set(3'b111);
      end
    join_none
  end

  initial begin
    static B b = new;
    a = b;
    #1;
    `checkh(z, 3'b111);
    clk = 1;
    #3;
    `checkh(z, 3'b001);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
