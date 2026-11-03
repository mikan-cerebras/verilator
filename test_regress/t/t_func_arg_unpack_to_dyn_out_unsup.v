// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  task automatic t_dyn_out(output int d[]);
    d = new[3];
  endtask
  task automatic t_queue_out(output int q[$]);
    q = {1, 2, 3};
  endtask
  task automatic t_queue_inout(inout int q[$]);
    q.push_back(1);
  endtask

  int fa[3];
  int fd[3:1];
  initial begin
    t_dyn_out(fa);  // <--- Unsupported
    t_queue_out(fd);  // <--- Unsupported
    t_queue_inout(fa);  // <--- Unsupported
  end
endmodule
