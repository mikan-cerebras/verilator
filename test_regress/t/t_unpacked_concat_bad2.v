// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Yutetsu TAKATSUKASA
// SPDX-License-Identifier: CC0-1.0

module t;

  logic [7:0] s0;
  logic [7:0] s1[1:2];
  logic [7:0] s2[1:4];
  logic [7:0] s3[2][2];

  typedef int AI3[1:3];
  AI3 A3;
  logic [31:0] A9_logic[1:9];

  initial begin
    // RHS has too many elements.
    s1 = {s0, s2};
    s2 = {s1, s0, s0, s0};
    // Incompatible type
    s2 = {s0, s3};

    A9_logic = {A3, 4, 5, A3, 6};
    $write("*-* All Finished *-*\n");
    $finish;
  end

  class Cls;
  endclass
  class Other;
  endclass

  initial begin
    Cls cq[$];
    Cls cd[];
    Other o;
    // Item of an incompatible type, so neither an element nor an array
    cq = {cq, o};
    cd = {o, cd};
    cq = '{o};
  end

  initial begin
    Cls cq[$];
    Other oq[$];
    Other od[];
    Other ou[2];
    Other ob[$:2];
    // Array of an incompatible type, so not an array of elements
    cq = {cq, oq};
    cq = {od, cq};
    cq = {cq, ou};
    cq = {cq, ob};
  end
endmodule
