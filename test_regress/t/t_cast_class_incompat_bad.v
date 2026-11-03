// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2011 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Base;
endclass
class BaseExtended extends Base;
endclass
class Other;
endclass
interface class Icls;
endclass

typedef Base Base_t;
typedef BaseExtended BaseExtended_t;
typedef Other Other_t;

module t;

  Base_t cls_a;
  BaseExtended_t cls_ab;
  Other_t other;
  Icls icls;

  initial begin
    cls_a = new;
    cls_ab = BaseExtended'(cls_a);  // bad-need dyn
    other = Other'(cls_ab);  // bad-incompat
    icls = Icls'(other);  // bad-need dyn, as a class derived from Other may implement Icls
  end

endmodule
