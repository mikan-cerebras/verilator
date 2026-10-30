// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// Each class has a foreach in a method defined in the class body and in one
// defined out-of-block, so their unnamed blocks get the same name

class CDyn;  // Dynamic array, out-of-block task
  int a[];
  task reset();
    foreach (a[i]) a[i] = 0;
  endtask
  extern task run();
endclass
task CDyn::run();
  foreach (a[i]) a[i] += i + 1;
endtask

package pkg_queue;
  class CQueue;  // Queue, out-of-block function
    int q[$];
    function void reset();
      foreach (q[i]) q[i] = 0;
    endfunction
    extern function int run();
  endclass
  function int CQueue::run();
    int sum = 0;
    foreach (q[i]) begin
      q[i]++;
      sum += q[i];
    end
    q.delete();
    return sum;
  endfunction
endpackage

package pkg_assoc;
  class CAssoc;  // Associative array
    int m[string];
    task reset();
      foreach (m[k]) m[k] = 0;
    endtask
    extern task run();
  endclass
  task CAssoc::run();
    foreach (m[k]) m[k] += k.len();
  endtask
endpackage

package pkg_string;
  class CString;  // String
    string s;
    task reset();
      foreach (s[j]) s[j] = "a";
    endtask
    extern task run();
  endclass
  task CString::run();
    foreach (s[j]) s[j] = s[j] + 8'(j);
  endtask
endpackage

module t;
  initial begin
    automatic CDyn cdyn = new;
    cdyn.a = '{5, 6, 7};
    cdyn.reset();
    cdyn.run();
    `checkd(cdyn.a[0], 1);
    `checkd(cdyn.a[2], 3);
  end

  initial begin
    automatic pkg_queue::CQueue cqueue = new;
    cqueue.q.push_back(4);
    cqueue.q.push_back(9);
    cqueue.reset();
    `checkd(cqueue.run(), 2);
    `checkd(cqueue.q.size(), 0);
  end

  initial begin
    automatic pkg_assoc::CAssoc cassoc = new;
    cassoc.m["x"] = 4;
    cassoc.m["yyy"] = 4;
    cassoc.reset();
    cassoc.run();
    `checkd(cassoc.m["x"], 1);
    `checkd(cassoc.m["yyy"], 3);
  end

  initial begin
    automatic pkg_string::CString cstring = new;
    cstring.s = "zzz";
    cstring.reset();
    cstring.run();
    `checks(cstring.s, "abc");
  end

  initial begin
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
