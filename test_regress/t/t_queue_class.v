// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2019 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  class Cls;
    int que[$];

    task push_data(int val);
      que.push_back(val);
    endtask

    function logic ok;
      return '1;
    endfunction
  endclass

  interface class Ifc;
  endclass
  class Base;
  endclass
  class Impl extends Base implements Ifc;
  endclass

  initial begin
    // Elements of the queue's class by an upcast, or null
    Ifc iq[$];
    Impl impl;
    impl = new;
    iq = {iq, impl, null};
    if (iq.size() != 2) $stop;
    if (iq[0] != impl) $stop;
    if (iq[1] != null) $stop;
  end

  initial begin
    Cls c2[1:0];
    Cls cq[$];

    c2[0] = new();

    c2[0].push_data(20);  // Works

    if (c2[0].que.size() != 1) $stop;

    c2[0].que.push_back(10);  // Unsupported
    if (c2[0].que.size() != 2) $stop;

    // Test there's no side effect warning on iteration
    foreach (cq[i])
    case (cq[i].ok())
      '0: $stop;
      '1: $stop;
    endcase

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
