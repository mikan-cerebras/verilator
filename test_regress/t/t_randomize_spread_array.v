// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Elements of large arrays come out spread over their domains, with a bounded number of
// solver checks (the .py counts them)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Item;
  rand int unsigned n;
  rand bit [15:0] addr[];
  rand bit [2:0] chip[];
  rand bit [2:0] pcie[];
  rand bit [3:0] sel[];
  rand int unsigned dly[];
  rand int unsigned dmax;
  constraint c_size {
    n == 100;
    addr.size() == n;
    chip.size() == n;
    pcie.size() == n;
    sel.size() == n;
    dly.size() == n;
  }
  constraint c_dom {
    // A few elements constrained on their own, and all distinct
    foreach (addr[i]) {
      if (i < 3) addr[i] == 16'(32'h1000 + i);
      else addr[i] inside {[16'h1000 : 16'h1fff]};
      foreach (addr[j]) if (i != j) addr[i] != addr[j];
    }
    foreach (chip[i]) soft chip[i] inside {[0 : 3]};
    foreach (pcie[i]) soft pcie[i] inside {[0 : 7]};
    foreach (sel[i]) soft sel[i] inside {[0 : 7]};
    dmax == 2;
    foreach (dly[i]) soft dly[i] inside {[1 : dmax]};
  }
endclass

// Each wide element splits into parts that can each change, so spreading it takes a
// satisfied check per element, past the limit on those
class Wide;
  rand bit [255:0] w[100];
  constraint c_low {
    foreach (w[i]) {
      w[i][7:0] == 8'(i);
      w[i][135:128] == 8'(i);
    }
  }
endclass

module t;
  // Every value of [lo:hi] appears, none in more than most elements
  function automatic void check_spread(int counts[], int lo, int hi, int most);
    foreach (counts[v]) begin
      if ((v >= lo && v <= hi) ? (counts[v] == 0 || counts[v] > most) : counts[v] != 0) begin
        $write("%%Error: value %0d taken by %0d elements\n", v, counts[v]);
        `stop;
      end
    end
  endfunction

  initial begin
    automatic Item it = new;
    automatic Wide wide = new;
    begin
      automatic int chips[] = new[8];
      automatic int pcies[] = new[8];
      automatic int sels[] = new[16];
      automatic int dlys[] = new[3];
      automatic int addrBits[] = new[12];
      `checkd(it.randomize(), 1);
      foreach (it.chip[i]) begin
        ++chips[it.chip[i]];
        ++pcies[it.pcie[i]];
        ++sels[it.sel[i]];
        if (it.dly[i] > 2) `stop;
        ++dlys[it.dly[i]];
        if (i < 3) begin
          `checkd(it.addr[i], 16'(32'h1000 + i));
        end
        else begin
          `checkd(it.addr[i][15:12], 4'h1);
          foreach (addrBits[b]) addrBits[b] += it.addr[i][b];
        end
      end
      // Half of the 100 elements, or for two values, three quarters
      check_spread(chips, 0, 3, 50);
      check_spread(pcies, 0, 7, 50);
      check_spread(sels, 0, 7, 50);
      check_spread(dlys, 1, 2, 75);
      // Each free address bit is set in about half of the 97 elements
      foreach (addrBits[b]) begin
        if (addrBits[b] < 24 || addrBits[b] > 73) begin
          $write("%%Error: address bit %0d set in %0d elements\n", b, addrBits[b]);
          `stop;
        end
      end
    end
    `checkd(wide.randomize(), 1);
    foreach (wide.w[i]) begin
      `checkd(wide.w[i][7:0], 8'(i));
      `checkd(wide.w[i][135:128], 8'(i));
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
