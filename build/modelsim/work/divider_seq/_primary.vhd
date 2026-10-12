library verilog;
use verilog.vl_types.all;
entity divider_seq is
    generic(
        WIDTH           : integer := 64
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        num             : in     vl_logic_vector;
        den             : in     vl_logic_vector;
        busy            : out    vl_logic;
        done            : out    vl_logic;
        q               : out    vl_logic_vector;
        r               : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of WIDTH : constant is 2;
end divider_seq;
