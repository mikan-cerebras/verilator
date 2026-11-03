// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Cast as the index of a dynamic array or queue element

module t;
  initial begin
    automatic int d[] = '{10, 11, 12, 13};
    automatic int q[$] = '{20, 21, 22, 23};
    automatic bit [6:0] i;
    for (int k = 0; k < 4; k++) begin
      i = 7'(k + 4);
      `checkd(d[int'(i[1:0])], 10 + k);
      `checkd(d[2'(i)], 10 + k);
      `checkd(q[bit'(i) + 2'(i[1])], 20 + k[0] + k[1]);
      `checkd(q[$ - int'(i[1:0])], 23 - k);
    end
    for (int k = 0; k < 4; k++) begin
      i = 7'(k + 4);
      d[2'(i)] = 30 + k;
      q[int'(i[1:0])] = 40 + k;
    end
    `checkd(d[3], 33);
    `checkd(q[2], 42);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
